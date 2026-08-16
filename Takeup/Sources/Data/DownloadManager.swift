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
    private var pendingProgressQueue: [PendingProgress] = []

    private let directory: URL
    private let catalogURL: URL
    private let pendingItemsURL: URL
    private let pendingProgressURL: URL
    private let delegateProxy: SessionDelegate
    private var session: URLSession!

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: "Downloads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        catalogURL = directory.appending(path: "catalog.json")
        pendingItemsURL = directory.appending(path: "pending-items.json")
        pendingProgressURL = directory.appending(path: "pending-progress.json")
        completed = Self.load([DownloadEntry].self, from: catalogURL) ?? []
        pendingItems = Self.load([Int64: Item].self, from: pendingItemsURL) ?? [:]
        pendingProgressQueue = Self.load([PendingProgress].self, from: pendingProgressURL) ?? []

        delegateProxy = SessionDelegate(directory: directory)
        let configuration = URLSessionConfiguration.background(withIdentifier: "xyz.five82.takeup.downloads")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = URLSession(configuration: configuration, delegate: delegateProxy, delegateQueue: nil)
        delegateProxy.manager = self

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
                // Drop pending snapshots with no surviving task.
                let live = Set(tasks.compactMap { $0.taskDescription.flatMap(Int64.init) })
                for itemId in self.pendingItems.keys where !live.contains(itemId) {
                    self.pendingItems[itemId] = nil
                    self.activeProgress[itemId] = nil
                }
                self.persistPendingItems()
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

    func posterURL(for itemId: Int64) -> URL? {
        let url = directory.appending(path: "\(itemId)-poster.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Lifecycle

    func start(item: Item, client: LoomClient) async {
        guard entry(for: item.id) == nil, activeProgress[item.id] == nil else { return }
        activeProgress[item.id] = 0
        do {
            let playback = try await client.playback(id: item.id)
            guard let url = client.streamURL(for: playback) else {
                activeProgress[item.id] = nil
                return
            }
            // Snapshot the full item (media, chapters, credits) for offline use.
            let full = (try? await client.item(id: item.id)) ?? item
            pendingItems[item.id] = full
            persistPendingItems()

            let task = session.downloadTask(with: url)
            task.taskDescription = String(item.id)
            task.resume()

            await savePoster(for: full, client: client)
        } catch {
            activeProgress[item.id] = nil
        }
    }

    func cancel(_ itemId: Int64) {
        session.getAllTasks { tasks in
            tasks.first { $0.taskDescription == String(itemId) }?.cancel()
        }
        activeProgress[itemId] = nil
        pendingItems[itemId] = nil
        persistPendingItems()
    }

    func remove(_ itemId: Int64) {
        if let entry = entry(for: itemId) {
            try? FileManager.default.removeItem(at: localURL(for: entry))
        }
        if let poster = posterURL(for: itemId) {
            try? FileManager.default.removeItem(at: poster)
        }
        completed.removeAll { $0.item.id == itemId }
        persistCatalog()
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
        persistPendingItems()
        guard let item else { return }
        completed.removeAll { $0.item.id == itemId }
        completed.append(DownloadEntry(item: item, relativePath: relativePath, size: size, downloadedAt: Date()))
        completed.sort { $0.downloadedAt > $1.downloadedAt }
        persistCatalog()
    }

    func failDownload(itemId: Int64) {
        activeProgress[itemId] = nil
        pendingItems[itemId] = nil
        persistPendingItems()
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
            } catch {
                remaining.append(pending)
            }
        }
        pendingProgressQueue = remaining
        persist(pendingProgressQueue, to: pendingProgressURL)
    }

    // MARK: - Persistence

    private func savePoster(for item: Item, client: LoomClient) async {
        guard let url = client.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 480),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return }
        try? data.write(to: directory.appending(path: "\(item.id)-poster.jpg"))
    }

    private func persistCatalog() { persist(completed, to: catalogURL) }
    private func persistPendingItems() { persist(pendingItems, to: pendingItemsURL) }

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
