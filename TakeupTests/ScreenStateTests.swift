import SwiftUI
import Testing
import UIKit
import Vision
@testable import Takeup

/// Mount screens in a real window so SwiftUI evaluates their state-dependent
/// bodies and tasks, rather than merely constructing an inert View value.
@MainActor
private func mounted<V: View>(_ view: V, environment: AppEnvironment) async throws -> UIWindow {
    let controller = UIHostingController(rootView:
        NavigationStack { view }
            .environment(environment)
            .environment(environment.network)
            .environment(DownloadManager.shared)
            .environment(\.paneWidth, 700)
    )
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 834, height: 1210)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    try? await Task.sleep(for: .milliseconds(100))
    return window
}

@MainActor
private func recognizedText(in window: UIWindow) throws -> [(text: String, bounds: CGRect)] {
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: #require(image.cgImage)).perform([request])
    return (request.results ?? []).compactMap { observation in
        observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
    }
}

@Suite(.serialized) @MainActor struct ScreenStateTests {
    @Test func offlineCatalogScreensExplainWhatIsUnavailable() async throws {
        let environment = AppEnvironment()
        let saved = environment.serverURLString
        defer { environment.serverURLString = saved }
        environment.serverURLString = "http://127.0.0.1:1"
        environment.network.markUnreachable()

        let screens: [(AnyView, String)] = [
            (AnyView(CollectionsView()), "Collections and genres come from Loom"),
            (AnyView(GenresView()), "Collections and genres come from Loom"),
            (AnyView(ItemGridView(source: .library(kind: "test-empty-library"), title: "Empty library")), "Nothing from here is downloaded"),
            (AnyView(ItemGridView(source: .genre(Genre(id: 28, name: "Action", itemCount: 1)), title: "Action")), "Collections and genres come from Loom"),
            (AnyView(ItemDetailView(itemId: -1000, fallbackTitle: "Missing")), "not downloaded to this device"),
            (AnyView(SearchView(initialQuery: "unavailable")), "searching what is downloaded"),
            (AnyView(DownloadsView()), "Downloads"),
        ]
        for (view, expected) in screens {
            let window = try await mounted(view, environment: environment)
            let text = try recognizedText(in: window).map(\.text).joined(separator: " ")
            #expect(text.localizedCaseInsensitiveContains(expected), "Expected \(expected) in rendered screen: \(text)")
            window.isHidden = true
        }
    }

    @Test func setupAndSettingsShowActionableOfflineStates() async throws {
        let environment = AppEnvironment()
        let saved = environment.serverURLString
        defer { environment.serverURLString = saved }
        environment.serverURLString = ""
        environment.network.markUnreachable()

        let screens: [(AnyView, [String])] = [
            (AnyView(OnboardingView()), ["Takeup", "a client for Loom", "Connect"]),
            (AnyView(SettingsView()), ["Settings", "Scanning needs Loom", "Discovered on network"]),
            (AnyView(ArtworkView(pick: ArtworkPick(itemId: -1100, title: "Missing artwork", ambienceURL: nil))),
             ["Missing artwork", "Poster", "Reset to default"]),
            (AnyView(PlayerScreen(item: makeItem(id: -1101, kind: "movie", title: "Unavailable film"))),
             ["No Loom server configured", "Unavailable film"]),
        ]
        for (view, expected) in screens {
            let window = try await mounted(view, environment: environment)
            let text = try recognizedText(in: window).map(\.text).joined(separator: " ")
            for phrase in expected {
                #expect(text.localizedCaseInsensitiveContains(phrase), "Expected \(phrase) in rendered screen: \(text)")
            }
            window.isHidden = true
        }
    }

    @Test func subtitleAnchorsStayOnOppositeSidesOfThePicture() async throws {
        let cues = SubtitleCue.parse("{\\an8}TOP CUE\nBOTTOM CUE")
        let window = try await mounted(
            ZStack {
                Color.black
                SubtitleOverlay(cues: cues, aspect: 16.0 / 9.0, lift: 0)
            },
            environment: AppEnvironment()
        )
        let text = try recognizedText(in: window)
        let top = try #require(text.first { $0.text.localizedCaseInsensitiveContains("TOP CUE") })
        let bottom = try #require(text.first { $0.text.localizedCaseInsensitiveContains("BOTTOM CUE") })
        // Vision's coordinates start at the bottom of the surface.
        #expect(top.bounds.midY > bottom.bounds.midY)
        window.isHidden = true
    }
}
