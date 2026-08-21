import Foundation
import Observation
import UIKit

struct DownloadEntry: Codable, Identifiable {
    let item: Item
    let relativePath: String
    let size: Int64
    let downloadedAt: Date

    var id: Int64 { item.id }
}

struct PendingProgress: Codable {
    let itemId: Int64
    let positionMs: Int64
    let durationMs: Int64
}

/// A value-only view of download storage, kept separate from the manager so
/// summary and stale-version decisions stay straightforward to test.
struct DownloadSummary: Equatable {
    let readyCount: Int
    let activeCount: Int
    let failedCount: Int
    let occupiedBytes: Int64
    let freeBytes: Int64?

    init(completed: [DownloadEntry], activeCount: Int, failedCount: Int, freeBytes: Int64?) {
        readyCount = completed.count
        self.activeCount = activeCount
        self.failedCount = failedCount
        occupiedBytes = completed.reduce(0) { $0 + $1.size }
        self.freeBytes = freeBytes
    }

    /// The Active section contains transfers and failed work awaiting retry.
    var activeWorkCount: Int { activeCount + failedCount }
    var totalManagedCount: Int { readyCount + activeWorkCount }
}

func downloadedMediaIsStale(storedMediaTag: String?, liveMediaTag: String?) -> Bool {
    guard let liveMediaTag, !liveMediaTag.isEmpty else { return false }
    return storedMediaTag != liveMediaTag
}

/// The artwork buckets saved alongside a download, matched to the widths the
/// UI already requests from Loom so playback and offline browsing share a cache.
enum ArtworkKind: String, CaseIterable {
    case poster, backdrop, thumb, logo

    var width: Int { self == .backdrop ? 1440 : 480 }

    func imageId(for item: Item) -> Int64? {
        switch self {
        case .poster: item.posterImageId
        case .backdrop: item.backdropImageId
        case .thumb: item.thumbImageId
        case .logo: item.logoImageId
        }
    }

    func imageTag(for item: Item) -> String? {
        switch self {
        case .poster: item.posterImageTag
        case .backdrop: item.backdropImageTag
        case .thumb: item.thumbImageTag
        case .logo: item.logoImageTag
        }
    }
}

/// Full-file downloads over a background URLSession, a JSON catalog of item
/// snapshots for offline browsing, locally saved posters, and a deferred
/// progress queue that flushes to Loom when it is reachable.
@Observable
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    private(set) var completed: [DownloadEntry] = []
    /// itemId -> fraction complete for queued/running downloads.
    private(set) var activeProgress: [Int64: Double] = [:]
    /// Item snapshots for in-flight downloads, persisted across relaunch.
    private(set) var pendingItems: [Int64: Item] = [:]
    /// Snapshots whose transfers failed. They stay out of OfflineCatalog: a
    /// failed file is never playable, but its title remains retryable.
    private(set) var failedItems: [Int64: Item] = [:]
    /// Captured seasons/shows above a downloaded episode, keyed by item id.
    private(set) var ancestors: [Int64: Item] = [:]
    /// Library id -> kind ("movies"/"shorts"/"tv"), learned whenever Loom
    /// answers /libraries. An item only carries its library's id, so offline
    /// this is the only thing that can tell a short film from a feature.
    private(set) var libraryKinds: [Int64: String] = [:]
    private var pendingProgressQueue: [PendingProgress] = []

    private let directory: URL
    private let catalogURL: URL
    private let pendingItemsURL: URL
    private let failedItemsURL: URL
    private let pendingProgressURL: URL
    private let ancestorsURL: URL
    private let libraryKindsURL: URL
    private let delegateProxy: SessionDelegate
    private var session: URLSession!

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: "Downloads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        catalogURL = directory.appending(path: "catalog.json")
        pendingItemsURL = directory.appending(path: "pending-items.json")
        failedItemsURL = directory.appending(path: "failed-items.json")
        pendingProgressURL = directory.appending(path: "pending-progress.json")
        ancestorsURL = directory.appending(path: "ancestors.json")
        libraryKindsURL = directory.appending(path: "library-kinds.json")
        completed = Self.load([DownloadEntry].self, from: catalogURL) ?? []
        pendingItems = Self.load([Int64: Item].self, from: pendingItemsURL) ?? [:]
        failedItems = Self.load([Int64: Item].self, from: failedItemsURL) ?? [:]
        pendingProgressQueue = Self.load([PendingProgress].self, from: pendingProgressURL) ?? []
        ancestors = Self.load([Int64: Item].self, from: ancestorsURL) ?? [:]
        libraryKinds = Self.load([Int64: String].self, from: libraryKindsURL) ?? [:]

        delegateProxy = SessionDelegate(directory: directory)
        let configuration = URLSessionConfiguration.background(withIdentifier: "xyz.five82.takeup.downloads")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = URLSession(configuration: configuration, delegate: delegateProxy, delegateQueue: nil)
        delegateProxy.manager = self

        // A prior run may have crashed between finishing a download and
        // pruning, or between losing a queued task and pruning; catch up now.
        pruneAncestors()

        // Reattach to tasks that survived an app relaunch.
        session.getAllTasks { tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for task in tasks {
                    if let description = task.taskDescription, let itemId = Int64(description),
                       self.activeProgress[itemId] == nil {
                        self.activeProgress[itemId] = 0
                    }
                }
                // A background task cannot be recreated after a relaunch.
                // Keep its snapshot as retryable failure instead of silently
                // dropping the title from Downloads.
                let live = Set(tasks.compactMap { $0.taskDescription.flatMap(Int64.init) })
                for itemId in self.pendingItems.keys where !live.contains(itemId) {
                    if let item = self.pendingItems[itemId] {
                        self.failedItems[itemId] = item
                    }
                    self.pendingItems[itemId] = nil
                    self.activeProgress[itemId] = nil
                }
                self.persistPendingItems()
                self.persistFailedItems()
                self.pruneAncestors()
            }
        }
    }

    // MARK: - Queries

    func entry(for itemId: Int64) -> DownloadEntry? {
        completed.first { $0.item.id == itemId }
    }

    func localURL(for entry: DownloadEntry) -> URL {
        directory.appending(path: entry.relativePath)
    }

    var completedBytesUsed: Int64 {
        completed.reduce(0) { $0 + $1.size }
    }

    var freeSpace: Int64? {
        try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    var summary: DownloadSummary {
        DownloadSummary(
            completed: completed,
            activeCount: activeProgress.count,
            failedCount: failedItems.count,
            freeBytes: freeSpace
        )
    }

    var totalManagedCount: Int { summary.totalManagedCount }

    func posterURL(for itemId: Int64) -> URL? {
        artworkURL(for: itemId, kind: .poster)
    }

    func artworkURL(for itemId: Int64, kind: ArtworkKind) -> URL? {
        let url = directory.appending(path: "\(itemId)-\(kind.rawValue).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A snapshot of the offline library as it stands right now, for views to
    /// read the same way they'd read a fetched Loom response.
    var offlineCatalog: OfflineCatalog {
        let pending = Dictionary(uniqueKeysWithValues: pendingProgressQueue.map { ($0.itemId, $0) })
        return OfflineCatalog(
            entries: completed,
            ancestors: ancestors,
            libraryKinds: libraryKinds,
            pending: pending,
            pendingItems: pendingItems
        )
    }

    // MARK: - Lifecycle

    func start(item: Item, client: LoomClient) async {
        guard entry(for: item.id) == nil, activeProgress[item.id] == nil else { return }
        // Store the listing snapshot before asking Loom for playback metadata.
        // It gives a queued row its real title immediately and is enough to
        // retry if that request fails before the fuller item response arrives.
        pendingItems[item.id] = item
        failedItems[item.id] = nil
        activeProgress[item.id] = 0
        persistPendingItems()
        persistFailedItems()
        do {
            let playback = try await client.playback(id: item.id)
            guard activeProgress[item.id] != nil, let url = client.streamURL(for: playback) else {
                if activeProgress[item.id] != nil { failDownload(itemId: item.id) }
                return
            }
            // Snapshot the full item (media, chapters, credits) for offline use.
            let full = (try? await client.item(id: item.id)) ?? item
            guard activeProgress[item.id] != nil else { return }
            pendingItems[item.id] = full
            persistPendingItems()

            let task = session.downloadTask(with: url)
            task.taskDescription = String(item.id)
            task.resume()

            await saveArtwork(for: full, client: client)
            // Both of these describe where the file belongs rather than the
            // file itself, and both are only answerable while Loom is
            // reachable. A failure costs context offline, never the download.
            await captureAncestors(for: full, client: client)
            if let libraries = try? await client.libraries() {
                updateLibraryKinds(libraries)
            }
        } catch {
            failDownload(itemId: item.id)
        }
    }

    func cancel(_ itemId: Int64) {
        session.getAllTasks { tasks in
            tasks.first { $0.taskDescription == String(itemId) }?.cancel()
        }
        activeProgress[itemId] = nil
        pendingItems[itemId] = nil
        failedItems[itemId] = nil
        persistPendingItems()
        persistFailedItems()
        pruneAncestors()
    }

    func remove(_ itemId: Int64) {
        if let entry = entry(for: itemId) {
            try? FileManager.default.removeItem(at: localURL(for: entry))
        }
        deleteArtwork(for: itemId)
        completed.removeAll { $0.item.id == itemId }
        persistCatalog()
        pruneAncestors()
    }

    func removeAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        for entry in completed {
            try? FileManager.default.removeItem(at: localURL(for: entry))
        }
        let managedIds = Set(completed.map(\.item.id))
            .union(pendingItems.keys)
            .union(failedItems.keys)
        for itemId in managedIds { deleteArtwork(for: itemId) }
        completed = []
        activeProgress = [:]
        pendingItems = [:]
        failedItems = [:]
        persistCatalog()
        persistPendingItems()
        persistFailedItems()
        pruneAncestors()
    }

    // MARK: - Delegate callbacks (hop from the session's background queue)

    func updateProgress(itemId: Int64, fraction: Double) {
        guard pendingItems[itemId] != nil || activeProgress[itemId] != nil else { return }
        activeProgress[itemId] = fraction
    }

    func finishDownload(itemId: Int64, relativePath: String, size: Int64) {
        let item = pendingItems[itemId] ?? completed.first { $0.item.id == itemId }?.item
        activeProgress[itemId] = nil
        pendingItems[itemId] = nil
        failedItems[itemId] = nil
        persistPendingItems()
        persistFailedItems()
        guard let item else {
            // A cancel/remove-all can race a just-finished background task.
            // Its delegate has already moved the file, so discard it here
            // rather than leaving untracked bytes on disk.
            try? FileManager.default.removeItem(at: directory.appending(path: relativePath))
            return
        }
        completed.removeAll { $0.item.id == itemId }
        completed.append(DownloadEntry(item: item, relativePath: relativePath, size: size, downloadedAt: Date()))
        completed.sort { $0.downloadedAt > $1.downloadedAt }
        persistCatalog()
        pruneAncestors()
    }

    func failDownload(itemId: Int64) {
        // Cancellation removes the pending snapshot first. The URLSession
        // cancellation callback arrives later, so this guard keeps a user
        // cancellation from being resurrected as a failed download.
        guard let item = pendingItems[itemId] else { return }
        activeProgress[itemId] = nil
        pendingItems[itemId] = nil
        failedItems[itemId] = item
        persistPendingItems()
        persistFailedItems()
        pruneAncestors()
    }

    // MARK: - Deferred progress

    func queueProgress(itemId: Int64, positionMs: Int64, durationMs: Int64) {
        pendingProgressQueue.removeAll { $0.itemId == itemId }
        pendingProgressQueue.append(PendingProgress(itemId: itemId, positionMs: positionMs, durationMs: durationMs))
        persist(pendingProgressQueue, to: pendingProgressURL)
    }

    func flushPendingProgress(client: LoomClient) async {
        guard !pendingProgressQueue.isEmpty else { return }
        var remaining: [PendingProgress] = []
        for pending in pendingProgressQueue {
            do {
                try await client.reportProgress(id: pending.itemId, positionMs: pending.positionMs, durationMs: pending.durationMs)
            } catch is LoomError {
                // Loom answered with an error; retrying the identical write cannot help.
            } catch {
                remaining.append(pending)
            }
        }
        pendingProgressQueue = remaining
        persist(pendingProgressQueue, to: pendingProgressURL)
    }

    // MARK: - Artwork

    private func saveArtwork(for item: Item, client: LoomClient) async {
        for kind in ArtworkKind.allCases {
            guard let url = client.imageURL(id: kind.imageId(for: item), tag: kind.imageTag(for: item), width: kind.width),
                  let (data, _) = try? await URLSession.shared.data(from: url)
            else { continue }
            try? data.write(to: directory.appending(path: "\(item.id)-\(kind.rawValue).jpg"))
        }
    }

    private func deleteArtwork(for itemId: Int64) {
        for kind in ArtworkKind.allCases {
            try? FileManager.default.removeItem(at: directory.appending(path: "\(itemId)-\(kind.rawValue).jpg"))
        }
    }

    // MARK: - Ancestors and library kinds

    /// Stores the season and show above an episode, artwork included, so an
    /// offline library can group episodes the way Loom does instead of
    /// listing them loose. Best-effort: a failure costs context offline,
    /// never the download.
    private func captureAncestors(for item: Item, client: LoomClient) async {
        var parentId = item.parentId
        var changed = false
        while let id = parentId, let parent = try? await client.item(id: id) {
            ancestors[parent.id] = parent
            changed = true
            await saveArtwork(for: parent, client: client)
            parentId = parent.parentId
        }
        if changed { persist(ancestors, to: ancestorsURL) }
    }

    /// Drops a captured show or season once the last download beneath it
    /// (completed or still in flight) is gone. Their artwork is the largest
    /// part of what they cost, so this runs on every change rather than
    /// waiting for a restart.
    private func pruneAncestors() {
        guard !ancestors.isEmpty else { return }
        var keep = Set<Int64>()
        let liveItems = completed.map(\.item) + Array(pendingItems.values)
        for liveItem in liveItems {
            var parentId = liveItem.parentId
            // A chain already walked cannot add anything new above it.
            while let id = parentId, keep.insert(id).inserted {
                parentId = ancestors[id]?.parentId
            }
        }
        let dead = Set(ancestors.keys).subtracting(keep)
        guard !dead.isEmpty else { return }
        for id in dead {
            ancestors[id] = nil
            deleteArtwork(for: id)
        }
        persist(ancestors, to: ancestorsURL)
    }

    /// Refreshed whenever Loom answers /libraries and remembered across
    /// relaunches: offline this is the only thing that can say which tab a
    /// download belongs in.
    func updateLibraryKinds(_ libraries: [Library]) {
        libraryKinds = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0.kind) })
        persist(libraryKinds, to: libraryKindsURL)
    }

    // MARK: - Persistence

    private func persistCatalog() { persist(completed, to: catalogURL) }
    private func persistPendingItems() { persist(pendingItems, to: pendingItemsURL) }
    private func persistFailedItems() { persist(failedItems, to: failedItemsURL) }

    private func persist(_ value: some Encodable, to url: URL) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Nonisolated URLSession delegate. Moves finished files synchronously (the
/// temp file dies when didFinishDownloadingTo returns), then hops to the
/// MainActor manager for state updates.
final class SessionDelegate: NSObject, URLSessionDownloadDelegate {
    weak var manager: DownloadManager?
    private let directory: URL
    private var lastReported: [Int64: Double] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let itemId = downloadTask.taskDescription.flatMap(Int64.init) else { return }
        let relativePath = "\(itemId).media"
        let destination = directory.appending(path: relativePath)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            Task { @MainActor [weak manager] in manager?.failDownload(itemId: itemId) }
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path))?[.size] as? Int64 ?? 0
        Task { @MainActor [weak manager] in
            manager?.finishDownload(itemId: itemId, relativePath: relativePath, size: size)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let itemId = downloadTask.taskDescription.flatMap(Int64.init),
              totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // Throttle UI updates to whole-percent steps.
        if fraction - (lastReported[itemId] ?? 0) >= 0.01 || fraction >= 1 {
            lastReported[itemId] = fraction
            Task { @MainActor [weak manager] in
                manager?.updateProgress(itemId: itemId, fraction: fraction)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let itemId = task.taskDescription.flatMap(Int64.init) else { return }
        _ = error
        Task { @MainActor [weak manager] in manager?.failDownload(itemId: itemId) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            AppDelegate.backgroundCompletionHandler?()
            AppDelegate.backgroundCompletionHandler = nil
        }
    }
}
