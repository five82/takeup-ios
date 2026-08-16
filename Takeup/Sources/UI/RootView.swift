import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case home, movies, shorts, tv, browse, search, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .shorts: "Short Films"
        case .tv: "TV"
        case .browse: "Browse"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .movies: "film"
        case .shorts: "film.stack"
        case .tv: "tv"
        case .browse: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }

    /// Loom library kind for the three library sections.
    var libraryKind: String? {
        switch self {
        case .movies: "movies"
        case .shorts: "shorts"
        case .tv: "tv"
        case .home, .browse, .search, .settings: nil
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var selection: SidebarSection? = .home
    @State private var autoplayItem: Item?

    var body: some View {
        Group {
            if appEnvironment.client == nil {
                OnboardingView()
            } else {
                mainSplitView
            }
        }
        .task { await handleAutoplayArgument() }
    }

    private var mainSplitView: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Takeup")
        } detail: {
            NavigationStack {
                switch selection ?? .home {
                case .home:
                    HomeView()
                case .browse:
                    BrowseView()
                case .search:
                    SearchView()
                case .settings:
                    SettingsView()
                case let section:
                    if let kind = section.libraryKind {
                        ItemGridView(source: .library(kind: kind), title: section.title)
                            .id(kind)
                    }
                }
            }
        }
        .fullScreenCover(item: $autoplayItem) { playable in
            PlayerScreen(item: playable)
        }
    }

    /// Debug hooks for CLI-driven simulator runs: `-autoplay <itemId>` jumps
    /// straight into playback, `-tab <section>` selects a sidebar section.
    private func handleAutoplayArgument() async {
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-server"),
           arguments.indices.contains(flagIndex + 1) {
            appEnvironment.serverURLString = arguments[flagIndex + 1]
        }
        if let flagIndex = arguments.firstIndex(of: "-tab"),
           arguments.indices.contains(flagIndex + 1),
           let section = SidebarSection(rawValue: arguments[flagIndex + 1]) {
            selection = section
        }
        guard let flagIndex = arguments.firstIndex(of: "-autoplay"),
              arguments.indices.contains(flagIndex + 1),
              let itemId = Int64(arguments[flagIndex + 1]),
              let client = appEnvironment.client
        else { return }
        autoplayItem = try? await client.item(id: itemId)
    }
}
