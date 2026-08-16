import Foundation

// The home screen's rotating discovery shelves, ported from the Android app
// (ui/home/Discovery.kt). Seeded by the epoch day: stable all day, different
// tomorrow.

struct DiscoveryRow: Identifiable, Equatable {
    let key: String
    let title: String
    let items: [Item]

    var id: String { key }
}

private let discoveryRowCount = 3
private let discoveryRowItems = 12
// A shelf with a couple of stragglers reads as a mistake, so thin rows are
// skipped and another candidate takes the slot.
private let minRowItems = 4
private let quickWatchMaxMs: Int64 = 90 * 60 * 1000
private let highRating = 7.5

func featuredPickLabel(hour: Int) -> String {
    (6..<18).contains(hour) ? "Today's Pick" : "Tonight's Pick"
}

/// Deterministic RNG (SplitMix64) so the day's shuffle is the same on every
/// refresh without depending on any platform RNG's seeding behavior.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// The day's discovery shelves, drawn from a pool of candidates. Candidates
/// that cannot fill a shelf drop out and the next takes the slot.
func discoveryRows(
    movies: [Item],
    shows: [Item],
    collections: [MediaCollection],
    recentlyPlayed: [Item],
    epochDay: Int64
) -> [DiscoveryRow] {
    var random = SeededRandom(seed: UInt64(bitPattern: epochDay))
    let library = movies + shows
    let unstarted = library.filter { !$0.isStarted }
    var builders: [() -> DiscoveryRow?] = [
        { genreSpotlight(unstarted, &random) },
        { row("unstarted", "New to You", unstarted.shuffled(using: &random)) },
        { row("rated", "Highly Rated", unstarted.filter { ($0.voteAverage ?? 0) >= highRating }.shuffled(using: &random)) },
        { collectionSpotlight(collections, &random) },
        { row("different", "Something Different", library.shuffled(using: &random)) },
        // The server orders these by finish time; keep that order.
        { row("again", "Watch It Again", recentlyPlayed) },
        {
            row(
                "quick", "A Quick Watch",
                movies.filter { !$0.isStarted && (1..<quickWatchMaxMs).contains($0.durationMs ?? 0) }
                    .shuffled(using: &random)
            )
        },
    ]
    builders.shuffle(using: &random)
    var rows: [DiscoveryRow] = []
    for build in builders {
        if let built = build() { rows.append(built) }
        if rows.count == discoveryRowCount { break }
    }
    return rows
}

extension Item {
    // A show counts as started once any episode is watched; a movie once it
    // has any playback state at all.
    var isStarted: Bool {
        if kind == "show" {
            return (episodeCount ?? 0) > 0 && (unwatchedCount ?? 0) < (episodeCount ?? 0)
        }
        return progress != nil
    }
}

private func row(_ key: String, _ title: String, _ items: [Item]) -> DiscoveryRow? {
    items.count < minRowItems ? nil : DiscoveryRow(key: key, title: title, items: Array(items.prefix(discoveryRowItems)))
}

private func genreSpotlight(_ unstarted: [Item], _ random: inout SeededRandom) -> DiscoveryRow? {
    var byGenre: [String: [Item]] = [:]
    for item in unstarted {
        for genre in item.genres ?? [] {
            byGenre[genre.name, default: []].append(item)
        }
    }
    // Sorted so the seeded pick does not depend on dictionary order.
    let candidates = byGenre.filter { $0.value.count >= minRowItems }.sorted { $0.key < $1.key }
    guard !candidates.isEmpty else { return nil }
    let pick = candidates[Int(random.next() % UInt64(candidates.count))]
    return row("genre", "Tonight: \(pick.key)", pick.value.shuffled(using: &random))
}

// Loom only serves collections with at least two owned members, and a
// two-movie franchise is still a real shelf, so this skips the usual floor.
private func collectionSpotlight(_ collections: [MediaCollection], _ random: inout SeededRandom) -> DiscoveryRow? {
    guard !collections.isEmpty else { return nil }
    let pick = collections[Int(random.next() % UInt64(collections.count))]
    return DiscoveryRow(key: "col-\(pick.slug)", title: pick.title, items: Array(pick.items.prefix(discoveryRowItems)))
}
