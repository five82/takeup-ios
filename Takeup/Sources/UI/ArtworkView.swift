import SwiftUI

/// Navigation value: pushes the artwork picker for an item. Carries the
/// detail art URL so the picker keeps the item's gauze and woven accent.
struct ArtworkPick: Hashable {
    let itemId: Int64
    let title: String
    let ambienceURL: URL?
    /// Non-poster only for the `-artworkKind` debug push: headless
    /// simulators cannot tap the kind chips.
    var initialKind: String = "poster"
}

/// TMDB's order is arbitrary; surface the sharpest, best-liked candidates
/// first. Mirrors the Android app's sortArtworkOptions.
func sortedArtworkOptions(_ options: [ImageOption]) -> [ImageOption] {
    options.sorted { a, b in
        let areaA = Int64(a.width) * Int64(a.height)
        let areaB = Int64(b.width) * Int64(b.height)
        if areaA != areaB { return areaA > areaB }
        if (a.voteAverage ?? 0) != (b.voteAverage ?? 0) { return (a.voteAverage ?? 0) > (b.voteAverage ?? 0) }
        return (a.voteCount ?? 0) > (b.voteCount ?? 0)
    }
}

/// The chosen option becomes the sole selected entry, keyed by provider+path.
func selectingArtworkOption(_ options: [ImageOption], chosen: ImageOption) -> [ImageOption] {
    options.map { option in
        var updated = option
        updated.selected = option.provider == chosen.provider && option.providerPath == chosen.providerPath
        return updated
    }
}

/// Full-pane artwork picker: poster/backdrop/logo/thumb chips over a grid of
/// TMDB candidates. Where the phone app shows bare thumbnails, the iPad's
/// width pays for larger cells plus the resolution/language/vote line that
/// makes near-identical candidates comparable.
struct ArtworkView: View {
    let pick: ArtworkPick

    init(pick: ArtworkPick) {
        self.pick = pick
        _kind = State(initialValue: pick.initialKind)
    }

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var kind: String
    @State private var options: [String: [ImageOption]] = [:]
    @State private var loading = true
    @State private var errorText: String?
    @State private var busy = false
    @State private var threads: [RGB] = []
    @State private var accent = WovenAccent.neutral
    @Environment(\.paneWidth) private var paneWidth

    private static let kinds = ["poster", "backdrop", "logo", "thumb"]

    var body: some View {
        let current = options[kind]
        ZStack {
            GauzeBackground(url: pick.ambienceURL, seed: threads.first)
            if paneWidth > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if let current, !current.isEmpty {
                            grid(current)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    // Like the detail screen: the pushed destination's
                    // unspecified width proposal reaches the scroll content,
                    // so pin it to the measured pane explicitly.
                    .frame(width: paneWidth, alignment: .leading)
                }
            }
            if current == nil, loading {
                LoadingState()
            } else if current == nil, let errorText {
                ErrorState(message: errorText) {
                    Task { await load(kind, force: true) }
                }
            } else if let current, current.isEmpty {
                EmptyState(message: "TMDB has no \(kind) options for this title.")
            }
        }
        .paneConstrained()
        .background(Color.stage)
        .animation(.easeInOut(duration: 0.45), value: accent)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            apply(threads: await WovenExtractor.threads(for: pick.ambienceURL))
            await load(kind)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                RowLabel(text: "Artwork", color: accent.tint)
                Text(pick.title)
                    .font(.displaySmall)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
            }
            .padding(.top, 16)
            HStack(spacing: 8) {
                ForEach(Self.kinds, id: \.self) { candidate in
                    kindChip(candidate)
                }
                Spacer(minLength: 12)
                resetButton
            }
            if let errorText, options[kind]?.isEmpty == false {
                Text(errorText)
                    .font(.bodySmall)
                    .foregroundStyle(Color.ember)
            }
        }
        .padding(.bottom, 16)
    }

    private func kindChip(_ candidate: String) -> some View {
        let selected = candidate == kind
        return Button {
            selectKind(candidate)
        } label: {
            Text(candidate.capitalized)
                .font(.labelLarge)
                .foregroundStyle(selected ? Color.ink : Color.muted)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? accent.tint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent.tint : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private var resetButton: some View {
        Button {
            Task { await reset() }
        } label: {
            Text("Reset to default")
                .font(.labelLarge)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Color.ink.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(busy || options[kind] == nil)
        .opacity(busy ? 0.5 : 1)
    }

    // MARK: - Grid

    private func grid(_ current: [ImageOption]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: kind == "poster" ? 160 : 250), spacing: 12)],
            alignment: .leading, spacing: 16
        ) {
            ForEach(current, id: \.providerPath) { option in
                optionCell(option)
            }
        }
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
    }

    private func optionCell(_ option: ImageOption) -> some View {
        Button {
            choose(option)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.surface1
                    if let url = URL(string: option.thumbnailUrl) {
                        // Logos have arbitrary shapes; never crop them.
                        if kind == "logo" {
                            CachedImage(url: url, contentMode: .fit) { Color.clear }
                                .padding(14)
                        } else {
                            CachedImage(url: url, contentMode: .fill) { Color.clear }
                        }
                    }
                }
                .aspectRatio(kind == "poster" ? 2 / 3 : 16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(option.selected ? accent.tint : Color.line, lineWidth: option.selected ? 2 : 1)
                )
                .overlay(alignment: .bottomLeading) {
                    if option.selected {
                        RowLabel(text: "Selected", color: accent.onFill, font: .labelSmall)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accent.fill.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
                Text(optionCaption(option))
                    .font(.labelSmall)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    /// The comparison line the phone app never had room for.
    private func optionCaption(_ option: ImageOption) -> String {
        var parts: [String] = []
        if option.width > 0, option.height > 0 {
            parts.append("\(option.width) × \(option.height)")
        }
        if let language = option.language, !language.isEmpty {
            parts.append(language.uppercased())
        }
        if let vote = option.voteAverage, vote > 0 {
            parts.append("★ " + String(format: "%.1f", vote))
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    // MARK: - Data

    private func selectKind(_ candidate: String) {
        guard candidate != kind else { return }
        kind = candidate
        errorText = nil
        if options[candidate] == nil {
            Task { await load(candidate) }
        }
    }

    private func load(_ kind: String, force: Bool = false) async {
        guard force || options[kind] == nil, let client = appEnvironment.client else { return }
        loading = true
        errorText = nil
        do {
            options[kind] = sortedArtworkOptions(try await client.imageOptions(id: pick.itemId, kind: kind))
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }

    /// Optimistic: Loom downloads the full-size original from TMDB before
    /// answering, which takes seconds; flip the badge now, roll back on
    /// failure.
    private func choose(_ option: ImageOption) {
        guard !option.selected, let previous = options[kind], let client = appEnvironment.client else { return }
        let chosenKind = kind
        options[chosenKind] = selectingArtworkOption(previous, chosen: option)
        errorText = nil
        Task {
            do {
                try await client.selectImage(
                    id: pick.itemId, kind: chosenKind,
                    provider: option.provider, providerPath: option.providerPath
                )
            } catch {
                options[chosenKind] = previous
                errorText = error.localizedDescription
            }
        }
    }

    private func reset() async {
        guard let client = appEnvironment.client else { return }
        busy = true
        errorText = nil
        do {
            try await client.resetImage(id: pick.itemId, kind: kind)
        } catch {
            errorText = error.localizedDescription
        }
        await load(kind, force: true)
        busy = false
    }

    private func apply(threads: [RGB]) {
        self.threads = threads
        if let seed = threads.first {
            accent = .from(seed: seed)
        }
    }
}
