import Foundation

// Text formatting shared across screens, matching the Android app's voice:
// "1 h 58 m", "S1E4", "22 m left".

func formatRuntime(_ milliseconds: Int64) -> String {
    let totalMinutes = Int(milliseconds / 60_000)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours) h \(minutes) m" : "\(minutes) m"
}

func episodeLabel(_ item: Item) -> String? {
    guard let season = item.seasonNumber, let episode = item.episodeNumber else { return nil }
    if let end = item.episodeEndNumber, end > episode {
        return "S\(season)E\(episode)-\(end)"
    }
    return "S\(season)E\(episode)"
}

/// "2 h 57 m left" for an item mid-watch, nil otherwise.
func remainingLabel(_ item: Item) -> String? {
    guard let progress = item.progress,
          let position = progress.resumePositionMs, position > 0,
          let duration = progress.durationMs, duration > 0,
          duration > position
    else { return nil }
    return "\(formatRuntime(duration - position)) left"
}

/// "S2E3 · Title": which episode this is, under the show named on the card
/// above it. The show is not repeated here - unlike a movie or a show, an
/// episode wears its own still rather than art with a title baked in, so the
/// card carries the show as its heading instead. nil for anything that is not
/// an episode.
func episodeLine(_ item: Item) -> String? {
    guard item.kind == "episode", let label = episodeLabel(item) else { return nil }
    return "\(label) · \(item.title)"
}

/// `episodeLine` with what is left to watch; for a movie, just what is left.
func continueLine(_ item: Item) -> String {
    [episodeLine(item), remainingLabel(item)].compactMap { $0 }.joined(separator: " · ")
}

func formatClock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}

func resolutionBadge(_ resolution: String?) -> String? {
    switch resolution {
    case "4k": "4K"
    case "1080p": "1080p"
    case "720p": "720p"
    case "sd": "SD"
    default: nil
    }
}
