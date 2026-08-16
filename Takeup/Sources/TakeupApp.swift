import SwiftUI
import AVFAudio

@main
struct TakeupApp: App {
    @State private var environment = AppEnvironment()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}
