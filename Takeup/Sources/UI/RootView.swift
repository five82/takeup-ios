import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case movies, shorts, tv, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies: "Movies"
        case .shorts: "Short Films"
        case .tv: "TV"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .movies: "film"
        case .shorts: "film.stack"
        case .tv: "tv"
        case .settings: "gearshape"
        }
    }

    /// Loom library kind for the three library sections.
    var libraryKind: String? {
        switch self {
        case .movies: "movies"
        case .shorts: "shorts"
        case .tv: "tv"
        case .settings: nil
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var selection: SidebarSection? = .movies
    @State private var autoplayItem: Item?

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Takeup")
        } detail: {
            NavigationStack {
                switch selection ?? .movies {
                case .settings:
                    SettingsView()
                case let section:
                    if let kind = section.libraryKind {
                        LibraryGridView(libraryKind: kind, title: section.title)
                            .id(kind)
                    }
                }
            }
        }
        .fullScreenCover(item: $autoplayItem) { playable in
            PlayerScreen(item: playable)
        }
        .task { await handleAutoplayArgument() }
    }

    /// Debug hook: `-autoplay <itemId>` launch argument jumps straight into
    /// playback, so CLI-driven simulator runs can exercise the player.
    private func handleAutoplayArgument() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-autoplay"),
              arguments.indices.contains(flagIndex + 1),
              let itemId = Int64(arguments[flagIndex + 1]),
              let client = appEnvironment.client
        else { return }
        autoplayItem = try? await client.item(id: itemId)
    }
}
