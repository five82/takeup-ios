import SwiftUI
import AVFAudio

/// Holds the completion handler iOS gives us when relaunching the app for
/// background download events; SessionDelegate calls it once events drain.
final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var backgroundCompletionHandler: (() -> Void)?

    /// `-landscape` narrows supported orientations so CLI-driven headless
    /// simulators (which cannot be rotated) come up in landscape.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        ProcessInfo.processInfo.arguments.contains("-landscape") ? .landscape : .all
    }

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
                // Dark-only, like the Android app: the logo artwork is
                // light-on-dark and a player lives in dim rooms.
                .preferredColorScheme(.dark)
                .tint(.ember)
                .environment(environment)
                .environment(environment.network)
                .environment(DownloadManager.shared)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    environment.network.recheck()
                    if let client = environment.client {
                        Task { await DownloadManager.shared.flushPendingProgress(client: client) }
                    }
                }
                // Walking back onto the LAN, or the tunnel coming up, is the
                // first moment anything queued while offline can be written.
                .onChange(of: environment.network.reach) { _, reach in
                    guard reach == .home || reach == .remote, let client = environment.client else { return }
                    Task { await DownloadManager.shared.flushPendingProgress(client: client) }
                }
        }
    }
}
