import SwiftUI

enum TVSection: String, CaseIterable, Identifiable {
    case home, movies, tv, shorts, collections, genres, search, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .shorts: "Short Films"
        case .tv: "TV"
        case .collections: "Collections"
        case .genres: "Genres"
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
        case .collections: "square.stack"
        case .genres: "theatermasks"
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
        case .home, .collections, .genres, .search, .settings: nil
        }
    }
}

/// The TV shell: the system's adaptable sidebar carrying the same sections as
/// the iPad's sidebar, minus Downloads — the Apple TV always lives on the
/// Loom LAN, so nothing is ever stored on it.
struct TVRootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var selection: TVSection = .home
    @State private var autoplayItem: Item?
    /// The Home tab's push stack; the `-detail` debug hook drives it.
    @State private var homePath = NavigationPath()

    var body: some View {
        Group {
            if appEnvironment.client == nil {
                TVOnboardingView()
            } else {
                shell
            }
        }
        .background(Color.stage)
        .task { await handleLaunchArguments() }
    }

    private var shell: some View {
        TabView(selection: $selection) {
            Tab(TVSection.home.title, systemImage: TVSection.home.icon, value: .home) {
                NavigationStack(path: $homePath) { TVHomeView() }
            }
            Tab(TVSection.movies.title, systemImage: TVSection.movies.icon, value: .movies) {
                NavigationStack { TVGridView(source: .library(kind: "movies"), title: TVSection.movies.title) }
            }
            Tab(TVSection.tv.title, systemImage: TVSection.tv.icon, value: .tv) {
                NavigationStack { TVGridView(source: .library(kind: "tv"), title: TVSection.tv.title) }
            }
            Tab(TVSection.shorts.title, systemImage: TVSection.shorts.icon, value: .shorts) {
                NavigationStack { TVGridView(source: .library(kind: "shorts"), title: TVSection.shorts.title) }
            }
            Tab(TVSection.collections.title, systemImage: TVSection.collections.icon, value: .collections) {
                NavigationStack { TVCollectionsView() }
            }
            Tab(TVSection.genres.title, systemImage: TVSection.genres.icon, value: .genres) {
                NavigationStack { TVGenresView() }
            }
            Tab(TVSection.search.title, systemImage: TVSection.search.icon, value: .search, role: .search) {
                NavigationStack { TVSearchView() }
            }
            Tab(TVSection.settings.title, systemImage: TVSection.settings.icon, value: .settings) {
                NavigationStack { TVSettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            VStack(alignment: .leading, spacing: 12) {
                Text("Takeup")
                    .font(.titleLarge)
                    .foregroundStyle(Color.ink)
                Selvedge(height: 4)
                    .frame(width: 96)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fullScreenCover(item: $autoplayItem) { playable in
            TVPlayerScreen(item: playable)
        }
    }

    /// Debug hooks for CLI-driven simulator runs, mirroring the iPad's:
    /// `-server <address>`, `-tab <section>`, `-detail <itemId>`, and
    /// `-autoplay <itemId>`. The download/artwork/landscape hooks have no TV
    /// counterpart.
    private func handleLaunchArguments() async {
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-server"),
           arguments.indices.contains(flagIndex + 1) {
            appEnvironment.serverURLString = arguments[flagIndex + 1]
        }
        if let flagIndex = arguments.firstIndex(of: "-tab"),
           arguments.indices.contains(flagIndex + 1),
           let section = TVSection(rawValue: arguments[flagIndex + 1]) {
            selection = section
        }
        if let flagIndex = arguments.firstIndex(of: "-detail"),
           arguments.indices.contains(flagIndex + 1),
           let itemId = Int64(arguments[flagIndex + 1]),
           let client = appEnvironment.client,
           let item = try? await client.item(id: itemId) {
            selection = .home
            homePath.append(item)
        }
        guard let flagIndex = arguments.firstIndex(of: "-autoplay"),
              arguments.indices.contains(flagIndex + 1),
              let itemId = Int64(arguments[flagIndex + 1]),
              let client = appEnvironment.client,
              let item = try? await client.item(id: itemId)
        else { return }
        autoplayItem = item
    }
}
