import SwiftUI
import AVFAudio

@main
struct TakeupTVApp: App {
    @State private var environment = AppEnvironment()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            TVRootView()
                // Dark-only, like the iPad and Android apps: the logo artwork
                // is light-on-dark and a television lives in a dim room.
                .preferredColorScheme(.dark)
                .tint(.ember)
                .environment(environment)
        }
    }
}
