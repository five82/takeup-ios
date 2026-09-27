import Foundation
import Testing
@testable import Takeup

@Suite @MainActor struct DownloadManagerTests {
    private func storage() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "takeup-download-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func manager(at directory: URL) -> DownloadManager {
        DownloadManager(directory: directory, sessionConfiguration: .ephemeral)
    }

    @Test func restoredCatalogReportsStorageAndRemovesFiles() throws {
        let directory = try storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = makeItem(id: 901, kind: "movie", title: "Saved movie")
        let entry = DownloadEntry(item: item, relativePath: "901.media", size: 17, downloadedAt: .now)
        try JSONEncoder().encode([entry]).write(to: directory.appending(path: "catalog.json"))
        try Data(repeating: 42, count: 17).write(to: directory.appending(path: "901.media"))
        try Data([1, 2, 3]).write(to: directory.appending(path: "901-poster.jpg"))

        let downloads = manager(at: directory)
        #expect(downloads.entry(for: 901)?.item.title == "Saved movie")
        #expect(downloads.summary.readyCount == 1)
        #expect(downloads.completedBytesUsed == 17)
        #expect(downloads.totalManagedCount == 1)
        #expect(downloads.posterURL(for: 901) != nil)
        #expect(downloads.offlineCatalog.item(901)?.title == "Saved movie")

        downloads.remove(901)
        #expect(downloads.entry(for: 901) == nil)
        #expect(downloads.posterURL(for: 901) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "901.media").path))
        #expect(manager(at: directory).completed.isEmpty)
    }

    @Test func latestQueuedProgressSurvivesRestartAndFoldsIntoOfflineItem() throws {
        let directory = try storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = makeItem(id: 902, kind: "movie", title: "Resumable")
        let entry = DownloadEntry(item: item, relativePath: "902.media", size: 10, downloadedAt: .now)
        try JSONEncoder().encode([entry]).write(to: directory.appending(path: "catalog.json"))
        let downloads = manager(at: directory)
        downloads.queueProgress(itemId: 902, positionMs: 30_000, durationMs: 600_000)
        downloads.queueProgress(itemId: 902, positionMs: 60_000, durationMs: 600_000)

        let restored = manager(at: directory)
        #expect(restored.offlineCatalog.item(902)?.progress?.resumePositionMs == 60_000)
        let queue = try JSONDecoder().decode([PendingProgress].self, from: Data(contentsOf: directory.appending(path: "pending-progress.json")))
        #expect(queue.count == 1)
        #expect(queue.first?.positionMs == 60_000)
    }

    @Test func failedPlaybackRequestKeepsRetryableSnapshotAcrossRestart() async throws {
        let directory = try storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = makeItem(id: 904, kind: "movie", title: "Retry later")
        let downloads = manager(at: directory)
        let client = LoomClient(baseURL: URL(string: "http://127.0.0.1:1")!, blocked: { true })

        await downloads.start(item: item, client: client)
        #expect(downloads.failedItems[904]?.title == "Retry later")
        #expect(downloads.activeProgress.isEmpty)
        #expect(downloads.offlineCatalog.item(904) == nil)
        #expect(downloads.summary.failedCount == 1)
        #expect(manager(at: directory).failedItems[904]?.title == "Retry later")

        downloads.cancel(904)
        #expect(downloads.failedItems.isEmpty)
        #expect(manager(at: directory).failedItems.isEmpty)
    }

    @Test func removingLastEpisodePrunesCapturedAncestorsAndArtwork() throws {
        let directory = try storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let show = makeItem(id: 905, kind: "show", title: "Saved show")
        let season = makeItem(id: 906, kind: "season", parentId: 905, season: 1)
        let first = makeItem(id: 907, parentId: 906, season: 1, episode: 1)
        let second = makeItem(id: 908, parentId: 906, season: 1, episode: 2)
        try JSONEncoder().encode([first, second].map {
            DownloadEntry(item: $0, relativePath: "\($0.id).media", size: 2, downloadedAt: .now)
        }).write(to: directory.appending(path: "catalog.json"))
        try JSONEncoder().encode([show.id: show, season.id: season]).write(to: directory.appending(path: "ancestors.json"))
        let art = directory.appending(path: "905-backdrop.jpg")
        try Data([1]).write(to: art)
        let downloads = manager(at: directory)
        #expect(downloads.completed.map(\.id).sorted() == [907, 908])
        #expect(downloads.ancestors.keys.sorted() == [905, 906])
        #expect(downloads.offlineCatalog.children(905).map(\.id) == [906])
        downloads.remove(907)
        #expect(downloads.ancestors.count == 2)
        #expect(FileManager.default.fileExists(atPath: art.path))
        downloads.remove(908)
        #expect(downloads.ancestors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: art.path))
        #expect(manager(at: directory).offlineCatalog.item(905) == nil)
    }

    @Test func removeAllClearsCompletedFailedAndQueuedWork() throws {
        let directory = try storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = makeItem(id: 909, kind: "movie")
        let entry = DownloadEntry(item: item, relativePath: "909.media", size: 3, downloadedAt: .now)
        try JSONEncoder().encode([entry]).write(to: directory.appending(path: "catalog.json"))
        let failed = makeItem(id: 910, kind: "movie")
        try JSONEncoder().encode([failed.id: failed]).write(to: directory.appending(path: "failed-items.json"))
        try Data([1, 2, 3]).write(to: directory.appending(path: "909.media"))
        try Data([1]).write(to: directory.appending(path: "910-poster.jpg"))
        let downloads = manager(at: directory)
        downloads.queueProgress(itemId: 909, positionMs: 90_000, durationMs: 600_000)
        downloads.removeAll()
        #expect(downloads.totalManagedCount == 0)
        #expect(downloads.offlineCatalog.item(909) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "909.media").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "910-poster.jpg").path))
        #expect(manager(at: directory).completed.isEmpty)
    }

    @Test func orphanedCompletionDeletesFileInsteadOfMakingItPlayable() throws {
        let directory = try storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = manager(at: directory)
        let file = directory.appending(path: "903.media")
        try Data([1, 2, 3]).write(to: file)

        downloads.finishDownload(itemId: 903, relativePath: "903.media", size: 3)
        downloads.failDownload(itemId: 903) // Late cancellation callback must not create a failed row.
        downloads.updateProgress(itemId: 903, fraction: 0.5)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(downloads.summary.totalManagedCount == 0)
        #expect(downloads.failedItems.isEmpty)
        #expect(downloads.activeProgress.isEmpty)
    }
}
