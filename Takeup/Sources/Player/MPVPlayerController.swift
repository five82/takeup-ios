import UIKit
import Libmpv

/// One entry of mpv's `track-list` property.
struct MPVTrack: Decodable, Hashable {
    let id: Int
    let type: String
    let lang: String?
    let title: String?
    let codec: String?
    let isDefault: Bool?
    let selected: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, lang, title, codec, selected
        case isDefault = "default"
    }

    /// Stable identity across audio/sub tracks that share numeric ids.
    var uid: String { "\(type)-\(id)" }

    var displayName: String {
        var parts: [String] = []
        if let title, !title.isEmpty { parts.append(title) }
        if let lang, !lang.isEmpty { parts.append(lang.uppercased()) }
        if parts.isEmpty, let codec { parts.append(codec) }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
    }
}

/// Hosts a libmpv instance rendering into a CAMetalLayer.
/// Adapted from the MPVKit iOS demo (Metal path).
final class MPVPlayerController: UIViewController {
    struct ObservedState {
        var timeSeconds: Double = 0
        var durationSeconds: Double = 0
        var paused: Bool = false
        var buffering: Bool = true
    }

    var playURL: URL?
    var startSeconds: Double = 0
    /// Called on the main thread whenever an observed property changes.
    var onStateChange: ((ObservedState) -> Void)?
    /// Called on the main thread once the file loads, with the full track list.
    var onTracksChange: (([MPVTrack]) -> Void)?

    private var metalLayer = MetalLayer()
    private var mpv: OpaquePointer!
    private let eventQueue = DispatchQueue(label: "mpv.events", qos: .userInitiated)
    private var state = ObservedState()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)

        setupMpv()
        if let playURL {
            loadFile(playURL, startSeconds: startSeconds)
        }
    }

    /// MPVKit's Metal/MoltenVK context has no live-resize support (MPVKit
    /// issue #3): no VOCTRL handling, and reconfig-based nudges reapply the
    /// stale surface size no matter when they run. The only reliable path is
    /// rebuilding the player at the new size, resuming position, pause
    /// state, and track selections. Costs a brief blink after rotating.
    @objc private func refreshRenderSize() {
        guard mpv != nil, let playURL else { return }
        let resumeSeconds = getDouble("time-pos")
        let wasPaused = getFlag("pause")
        let audioTrack = getString("aid")
        let subtitleTrack = getString("sid")

        shutdown()
        metalLayer.removeFromSuperlayer()
        metalLayer = MetalLayer()
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)

        setupMpv()
        loadFile(playURL, startSeconds: max(0, resumeSeconds))
        if wasPaused {
            setFlag("pause", true)
        }
        if let audioTrack {
            mpv_set_property_string(mpv, "aid", audioTrack)
        }
        if let subtitleTrack {
            mpv_set_property_string(mpv, "sid", subtitleTrack)
        }
    }

    private var lastLayoutSize: CGSize = .zero

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // bounds, not frame: frame is expressed in the rotating superview's
        // coordinate space, which leaves the layer with stale geometry after
        // an orientation change (picture cut off / off-center). Disable the
        // implicit CALayer animation so the resize tracks rotation cleanly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        // MoltenVK sets drawableSize explicitly, which stops it tracking the
        // layer's bounds — without this the drawable keeps its pre-rotation
        // size and mpv renders the picture off-center.
        let scale = metalLayer.contentsScale
        metalLayer.drawableSize = CGSize(
            width: view.bounds.width * scale,
            height: view.bounds.height * scale
        )
        CATransaction.commit()

        // Trigger the reconfig off layout (viewWillTransition is not
        // reliably forwarded to representable-hosted children), debounced
        // until the transition settles. Also covers windowed resizes.
        let size = view.bounds.size
        if lastLayoutSize != .zero, lastLayoutSize != size {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshRenderSize), object: nil)
            // A full second: firing inside the rotation animation lets the
            // swapchain negotiate against MoltenVK's still-stale surface
            // extent, which re-applies the old size.
            perform(#selector(refreshRenderSize), with: nil, afterDelay: 1.0)
        }
        lastLayoutSize = size
    }

    private func setupMpv() {
        mpv = mpv_create()
        guard mpv != nil else {
            assertionFailure("mpv_create failed")
            return
        }

#if DEBUG
        checkError(mpv_request_log_messages(mpv, "warn"))
#else
        checkError(mpv_request_log_messages(mpv, "no"))
#endif
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayer))
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
        // HDR passthrough: mpv signals the video's color space to the Metal
        // layer, which activates the screen's EDR mode (see MetalLayer).
        // Must be set before init; it can't be toggled at runtime.
        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(mpv, "subs-fallback", "yes"))

        checkError(mpv_initialize(mpv))

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)

        mpv_set_wakeup_callback(mpv, { ctx in
            let controller = unsafeBitCast(ctx, to: MPVPlayerController.self)
            controller.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    // MARK: - Commands

    func loadFile(_ url: URL, startSeconds: Double = 0) {
        var args = [url.absoluteString, "replace"]
        if startSeconds > 0 {
            // mpv >= 0.38 loadfile signature: url [flags [index [options]]].
            // The index (-1 = append position, unused for "replace") must be
            // present or the options string is rejected and nothing loads.
            args.append("-1")
            args.append("start=\(startSeconds)")
        }
        command("loadfile", args: args)
    }

    func togglePause() {
        setFlag("pause", !getFlag("pause"))
    }

    func seek(to seconds: Double) {
        command("seek", args: [String(seconds), "absolute"])
    }

    func seek(by seconds: Double) {
        command("seek", args: [String(seconds), "relative"])
    }

    func stepChapter(_ delta: Int) {
        command("add", args: ["chapter", String(delta)])
    }

    func setAudioTrack(_ id: Int) {
        guard mpv != nil else { return }
        mpv_set_property_string(mpv, "aid", String(id))
    }

    /// Pass nil to turn subtitles off.
    func setSubtitleTrack(_ id: Int?) {
        guard mpv != nil else { return }
        mpv_set_property_string(mpv, "sid", id.map(String.init) ?? "no")
    }

    /// Tears down mpv synchronously enough to be safe: the wakeup callback is
    /// detached first so it can never fire into a deallocated controller, then
    /// the handle is destroyed on the event queue after any in-flight drain.
    func shutdown() {
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        eventQueue.async {
            mpv_terminate_destroy(handle)
        }
    }

    deinit {
        shutdown()
    }

    // MARK: - Property helpers

    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    private func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        guard let cString = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }

    private func getFlag(_ name: String) -> Bool {
        guard mpv != nil else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard mpv != nil else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func command(_ command: String, args: [String?] = []) {
        guard mpv != nil else { return }
        var strArgs: [String?] = [command] + args
        strArgs.append(nil)
        var cargs = strArgs.map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for pointer in cargs where pointer != nil {
                free(UnsafeMutablePointer(mutating: pointer!))
            }
        }
        checkError(mpv_command(mpv, &cargs), context: ([command] + args.compactMap { $0 }).joined(separator: " "))
    }

    // MARK: - Events

    private func readEvents() {
        eventQueue.async { [weak self] in
            // Capture the handle once: shutdown() enqueues mpv_terminate_destroy
            // on this same serial queue, so it stays valid for the whole drain.
            guard let self, let handle = self.mpv else { return }
            while self.mpv != nil {
                guard let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE else {
                    break
                }
                switch event.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    self.handlePropertyChange(event)
                case MPV_EVENT_FILE_LOADED:
                    self.publishTracks()
                case MPV_EVENT_SHUTDOWN:
                    if let handle = self.mpv {
                        self.mpv = nil
                        mpv_set_wakeup_callback(handle, nil, nil)
                        mpv_terminate_destroy(handle)
                    }
                case MPV_EVENT_LOG_MESSAGE:
                    if let message = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data)) {
                        print("[mpv \(String(cString: message.pointee.level!))] \(String(cString: message.pointee.text!))", terminator: "")
                    }
                default:
                    break
                }
            }
        }
    }

    private func publishTracks() {
        guard let json = getString("track-list"),
              let data = json.data(using: .utf8),
              let tracks = try? JSONDecoder().decode([MPVTrack].self, from: data)
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onTracksChange?(tracks)
        }
    }

    private func handlePropertyChange(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let property = UnsafePointer<mpv_event_property>(OpaquePointer(event.pointee.data))?.pointee else { return }
        let name = String(cString: property.name)

        switch name {
        case "time-pos":
            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                state.timeSeconds = value
            }
        case "duration":
            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                state.durationSeconds = value
            }
        case "pause":
            if let value = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                state.paused = value
            }
        case "paused-for-cache":
            if let value = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                state.buffering = value
            }
        default:
            return
        }

        let snapshot = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(snapshot)
        }
    }

    private func checkError(_ status: CInt, context: String = "") {
        if status < 0 {
            print("mpv API error\(context.isEmpty ? "" : " (\(context))"): \(String(cString: mpv_error_string(status)))")
        }
    }
}
