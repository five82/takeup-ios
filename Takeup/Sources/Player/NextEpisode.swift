import Foundation

/// The episode to offer after `currentId` finishes: the next number in its
/// season, else the first episode of the next season. Specials (season zero)
/// only chain within themselves, mirroring Loom's Next Up rule and the
/// Android app. `episodes` must hold the show's episodes; order does not
/// matter.
func nextEpisodeAfter(_ currentId: Int64, in episodes: [Item]) -> Item? {
    guard let current = episodes.first(where: { $0.id == currentId }) else { return nil }
    let currentIsSpecial = (current.seasonNumber ?? 0) == 0
    let ordered = episodes
        .filter { $0.kind == "episode" && (($0.seasonNumber ?? 0) == 0) == currentIsSpecial }
        .sorted { lhs, rhs in
            let left = (lhs.seasonNumber ?? 0) * 10_000 + (lhs.episodeNumber ?? 0)
            let right = (rhs.seasonNumber ?? 0) * 10_000 + (rhs.episodeNumber ?? 0)
            return left < right
        }
    guard let index = ordered.firstIndex(where: { $0.id == currentId }) else { return nil }
    return index + 1 < ordered.count ? ordered[index + 1] : nil
}
