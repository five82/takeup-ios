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
