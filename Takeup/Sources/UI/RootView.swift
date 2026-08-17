import SwiftUI
import UIKit

enum SidebarSection: String, CaseIterable, Identifiable {
    case home, movies, shorts, tv, collections, genres, search, downloads, settings

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
        case .downloads: "Downloads"
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
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }

    /// Loom library kind for the three library sections.
    var libraryKind: String? {
        switch self {
        case .movies: "movies"
        case .shorts: "shorts"
        case .tv: "tv"
        case .home, .collections, .genres, .search, .downloads, .settings: nil
        }
    }

    /// The thread color that marks this section in the sidebar. Home carries
    /// the full selvedge instead.
    var thread: Color? {
        switch self {
        case .movies: .ember
        case .tv: .teal
        case .shorts: .amber
        // Collections keeps the selvedge's violet thread from the old Browse
        // room; Genres gets its own cobalt so the two dots read apart.
        case .collections: .violet
        case .genres: .cobalt
        case .home, .search, .downloads, .settings: nil
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var selection: SidebarSection = .home
    @State private var autoplayItem: Item?
    @State private var detailPath = NavigationPath()

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

    // A hand-rolled shell instead of NavigationSplitView: the system split
    // view (as of the iOS 26 beta) ignores column-width hints and injects a
    // phantom leading inset that misaligns edge-to-edge artwork. A plain
    // HStack gives the design full control of both columns.
    private var mainSplitView: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: 220)
            GeometryReader { pane in
                NavigationStack(path: $detailPath) {
                    detailRoot
                }
                // A fresh stack per section: switching sections while pushed
                // deep must not leak the old push state into the new one.
                .id(selection)
                // Pushed destinations on the iOS 26 beta receive an
                // unspecified width proposal and balloon to their ideal
                // width; screens pin themselves to this measured pane.
                .environment(\.paneWidth, pane.size.width)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.stage)
        .onChange(of: selection) {
            // Selecting a section always lands on its root.
            detailPath = NavigationPath()
        }
        .fullScreenCover(item: $autoplayItem) { playable in
            PlayerScreen(item: playable)
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection {
        case .home:
            HomeView()
        case .collections:
            CollectionsView()
        case .genres:
            GenresView()
        case .search:
            SearchView()
        case .downloads:
            DownloadsView()
        case .settings:
            SettingsView()
        case let section:
            if let kind = section.libraryKind {
                ItemGridView(source: .library(kind: kind), title: section.title)
                    .id(kind)
            }
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
        if arguments.contains("-landscape") {
            try? await Task.sleep(for: .seconds(1))
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        if let flagIndex = arguments.firstIndex(of: "-download"),
           arguments.indices.contains(flagIndex + 1),
           let itemId = Int64(arguments[flagIndex + 1]),
           let client = appEnvironment.client,
           let item = try? await client.item(id: itemId) {
            await DownloadManager.shared.start(item: item, client: client)
        }
        // `-detail <itemId>` pushes an item's detail screen for CLI-driven
        // simulator checks. Falls back to the download snapshot so the offline
        // screens can be checked the same way.
        if let flagIndex = arguments.firstIndex(of: "-detail"),
           arguments.indices.contains(flagIndex + 1),
           let itemId = Int64(arguments[flagIndex + 1]),
           let item = await resolveItem(itemId) {
            detailPath.append(item)
            // `-person <name>` on top of `-detail` pushes the cast-card
            // person search, since headless simulators cannot tap.
            if let personIndex = arguments.firstIndex(of: "-person"),
               arguments.indices.contains(personIndex + 1) {
                detailPath.append(PersonSearch(name: arguments[personIndex + 1]))
            }
        }
        // `-artwork <itemId>` pushes the item's detail and then its artwork
        // picker, since headless simulators cannot tap the toolbar menu.
        if let flagIndex = arguments.firstIndex(of: "-artwork"),
           arguments.indices.contains(flagIndex + 1),
           let itemId = Int64(arguments[flagIndex + 1]),
           let client = appEnvironment.client,
           let item = try? await client.item(id: itemId) {
            detailPath.append(item)
            var pick = ArtworkPick(
                itemId: item.id, title: item.title,
                ambienceURL: detailArtURL(for: item, client: client, width: 240)
            )
            // `-artworkKind <poster|backdrop|logo|thumb>` opens on that kind.
            if let kindIndex = arguments.firstIndex(of: "-artworkKind"),
               arguments.indices.contains(kindIndex + 1) {
                pick.initialKind = arguments[kindIndex + 1]
            }
            detailPath.append(pick)
        }
        guard let flagIndex = arguments.firstIndex(of: "-autoplay"),
              arguments.indices.contains(flagIndex + 1),
              let itemId = Int64(arguments[flagIndex + 1])
        else { return }
        autoplayItem = await resolveItem(itemId)
    }

    /// Loom's copy of an item, or the download snapshot when Loom cannot be
    /// asked — the debug hooks have to work offline too.
    private func resolveItem(_ itemId: Int64) async -> Item? {
        if let client = appEnvironment.client, let item = try? await client.item(id: itemId) {
            return item
        }
        return DownloadManager.shared.offlineCatalog.item(itemId)
    }
}

/// The Takeup sidebar: Stage-dark ground, the wordmark over a selvedge, and
/// each section marked in its thread. The Home row's selection marker is the
/// full selvedge, exactly like the Android nav pill's markers.
private struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Takeup")
                        .font(.titleLarge)
                        .foregroundStyle(Color.ink)
                    Selvedge(height: 3)
                        .frame(width: 76)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 22)

                ForEach([SidebarSection.home, .movies, .tv, .shorts, .collections, .genres]) { section in
                    row(section)
                }

                Rectangle()
                    .fill(Color.line)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                ForEach([SidebarSection.search, .downloads, .settings]) { section in
                    row(section)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(hexValue: 0x0D111B))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.line).frame(width: 1).ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        // Cmd-1...6 jump between the six browsing sections.
        .background {
            ForEach(Array([SidebarSection.home, .movies, .tv, .shorts, .collections, .genres].enumerated()), id: \.element) { index, section in
                Button("") { selection = section }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .hidden()
            }
        }
    }

    private func row(_ section: SidebarSection) -> some View {
        let selected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(selected ? (section.thread ?? Color.ink) : Color.faint)
                Text(section.title)
                    .font(selected ? .titleSmall : .system(size: 14))
                    .foregroundStyle(selected ? Color.ink : Color.muted)
                Spacer(minLength: 0)
                if let thread = section.thread, !selected {
                    Circle()
                        .fill(thread)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(selected ? Color.surface1 : .clear)
            .overlay(alignment: .leading) {
                if selected {
                    marker(for: section)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 2, topTrailingRadius: 2))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    @ViewBuilder
    private func marker(for section: SidebarSection) -> some View {
        if section == .home {
            // The selvedge, rotated to the vertical edge bar.
            LinearGradient(
                stops: [
                    .init(color: .ember, location: 0), .init(color: .ember, location: 0.40),
                    .init(color: .teal, location: 0.40), .init(color: .teal, location: 0.69),
                    .init(color: .amber, location: 0.69), .init(color: .amber, location: 0.89),
                    .init(color: .violet, location: 0.89), .init(color: .violet, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            (section.thread ?? Color.ink)
        }
    }
}
