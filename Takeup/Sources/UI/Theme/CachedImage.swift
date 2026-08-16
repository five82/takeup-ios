import SwiftUI
import UIKit

/// In-memory image store over the shared URLCache. AsyncImage refetches on
/// every cell recycle; grids scroll through the same posters constantly, so
/// decoded images are worth keeping.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 600
    }

    func cached(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data)
            else { return nil }
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// Drop-in artwork view: cached, fades in on first decode, reports the
/// decoded image up (the logo lane needs its aspect ratio).
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var onLoad: ((UIImage) -> Void)? = nil
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = ImageStore.shared.cached(for: url) {
                // Cached artwork paints on the first frame, no fade.
                image = hit
                onLoad?(hit)
                return
            }
            guard let fetched = await ImageStore.shared.image(for: url) else { return }
            withAnimation(.easeIn(duration: 0.2)) { image = fetched }
            onLoad?(fetched)
        }
    }
}

extension CachedImage where Placeholder == Color {
    init(url: URL?, contentMode: ContentMode = .fill, onLoad: ((UIImage) -> Void)? = nil) {
        self.init(url: url, contentMode: contentMode, onLoad: onLoad) { Color.surface1 }
    }
}
