import SwiftUI

private struct MPVPlayerView: UIViewControllerRepresentable {
    let url: URL
    let startSeconds: Double
    let model: PlayerModel

    func makeUIViewController(context: Context) -> MPVPlayerController {
        let controller = MPVPlayerController()
        controller.playURL = url
        controller.startSeconds = startSeconds
        controller.onStateChange = { [weak model] state in
            model?.apply(state)
        }
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: MPVPlayerController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: MPVPlayerController, coordinator: ()) {
        uiViewController.shutdown()
    }
}

@Observable
@MainActor
final class PlayerModel {
    var timeSeconds: Double = 0
    var durationSeconds: Double = 0
    var paused = false
    var buffering = true

    weak var controller: MPVPlayerController?

    func apply(_ state: MPVPlayerController.ObservedState) {
        timeSeconds = state.timeSeconds
        durationSeconds = state.durationSeconds
        paused = state.paused
        buffering = state.buffering
    }
}

/// Full-screen playback with minimal overlay controls. Mirrors the Android
/// app's progress protocol: report every 10s while playing, on pause, and
/// once more on exit.
struct PlayerScreen: View {
    let item: Item

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var model = PlayerModel()
    @State private var playbackURL: URL?
    @State private var loadError: String?
    @State private var controlsVisible = true
    @State private var scrubbing = false
    @State private var scrubTarget: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let playbackURL {
                MPVPlayerView(
                    url: playbackURL,
                    startSeconds: Double(item.progress?.resumePositionMs ?? 0) / 1000,
                    model: model
                )
                .ignoresSafeArea()
            } else if let loadError {
                ContentUnavailableView("Playback Failed", systemImage: "play.slash", description: Text(loadError))
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }

            if controlsVisible {
                controls
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                controlsVisible.toggle()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .task { await progressLoop() }
        .onDisappear {
            Task { await reportProgress() }
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .padding(12)
                        .background(.black.opacity(0.5), in: Circle())
                }
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if model.buffering {
                    ProgressView().tint(.white)
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubTarget : model.timeSeconds },
                        set: { scrubTarget = $0 }
                    ),
                    in: 0...max(model.durationSeconds, 1)
                ) { editing in
                    if editing {
                        scrubTarget = model.timeSeconds
                        scrubbing = true
                    } else {
                        model.controller?.seek(to: scrubTarget)
                        scrubbing = false
                    }
                }
                HStack {
                    Text(formatTime(model.timeSeconds))
                    Spacer()
                    Button {
                        model.controller?.togglePause()
                    } label: {
                        Image(systemName: model.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 40))
                    }
                    Spacer()
                    Text(formatTime(model.durationSeconds))
                }
                .font(.subheadline.monospacedDigit())
            }
            .padding(16)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding()
        .foregroundStyle(.white)
    }

    private func start() async {
        guard let client = appEnvironment.client else { return }
        do {
            let playback = try await client.playback(id: item.id)
            playbackURL = client.streamURL(for: playback)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func progressLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            await reportProgress()
        }
    }

    private func reportProgress() async {
        guard let client = appEnvironment.client, model.timeSeconds > 0, model.durationSeconds > 0 else { return }
        try? await client.reportProgress(
            id: item.id,
            positionMs: Int64(model.timeSeconds * 1000),
            durationMs: Int64(model.durationSeconds * 1000)
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
