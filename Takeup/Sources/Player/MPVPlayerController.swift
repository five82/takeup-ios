import UIKit
import Libmpv

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

    private var metalLayer = MetalLayer()
    private var mpv: OpaquePointer!
    private let eventQueue = DispatchQueue(label: "mpv.events", qos: .userInitiated)
    private var state = ObservedState()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        metalLayer.frame = view.frame
        metalLayer.contentsScale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)

        setupMpv()
        if let playURL {
            loadFile(playURL, startSeconds: startSeconds)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer.frame = view.frame
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

    func shutdown() {
        command("quit")
    }

    // MARK: - Property helpers

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
        checkError(mpv_command(mpv, &cargs))
    }

    // MARK: - Events

    private func readEvents() {
        eventQueue.async { [weak self] in
            guard let self else { return }
            while self.mpv != nil {
                guard let event = mpv_wait_event(self.mpv, 0), event.pointee.event_id != MPV_EVENT_NONE else {
                    break
                }
                switch event.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    self.handlePropertyChange(event)
                case MPV_EVENT_SHUTDOWN:
                    mpv_terminate_destroy(self.mpv)
                    self.mpv = nil
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

    private func checkError(_ status: CInt) {
        if status < 0 {
            print("mpv API error: \(String(cString: mpv_error_string(status)))")
        }
    }
}
