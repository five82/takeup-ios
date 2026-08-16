import SwiftUI
import AVFAudio

/// Holds the completion handler iOS gives us when relaunching the app for
/// background download events; SessionDelegate calls it once events drain.
final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var backgroundCompletionHandler: (() -> Void)?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            AppDelegate.backgroundCompletionHandler = completionHandler
        }
    }
}

@main
struct TakeupApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(DownloadManager.shared)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, let client = environment.client {
                        Task { await DownloadManager.shared.flushPendingProgress(client: client) }
                    }
                }
        }
    }
}
