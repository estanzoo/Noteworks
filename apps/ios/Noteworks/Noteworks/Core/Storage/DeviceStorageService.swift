//
//  DeviceStorageService.swift
//  Noteworks
//
//  Measures real on-device storage used by the app so the Profile →
//  General → Storage panel can replace the previously hard-coded values.
//
//  Three buckets, mirroring the design:
//    • Note Library — the per-user `users/<uid>/notes-store.json` plus
//      every `notes/<noteId>/<page>.drawing` file (the part the user
//      would lose if they deleted the app).
//    • Media Cache — `Library/Caches/*` and the system `URLCache`
//      (image previews, thumbnails, network caches).
//    • Offline Files — per-note overlay images that the user
//      explicitly imported into the editor (`notes/<id>/images/*`).
//
//  Sizes are reported in **bytes** so the UI can render either MB or
//  GB based on magnitude (we don't truncate to MB at the source).
//

import Foundation

/// Snapshot of the three storage buckets surfaced on the Storage panel.
/// Stored separately so the UI can render a total + per-bucket progress
/// bar without re-walking the filesystem.
struct StorageReport: Equatable {
    struct Bucket: Equatable, Identifiable {
        let id: String
        let label: String
        let detail: String
        var bytes: Int64
    }

    var noteLibrary: Bucket
    var mediaCache: Bucket
    var offlineFiles: Bucket

    var buckets: [Bucket] { [noteLibrary, mediaCache, offlineFiles] }
    var totalBytes: Int64 { buckets.reduce(0) { $0 + $1.bytes } }

    static let empty = StorageReport(
        noteLibrary: .init(
            id: "note-library",
            label: "Note Library",
            detail: "Downloaded notebooks, page thumbnails, and recent edits",
            bytes: 0
        ),
        mediaCache: .init(
            id: "media-cache",
            label: "Media Cache",
            detail: "Images, preview renders, and imported visual assets",
            bytes: 0
        ),
        offlineFiles: .init(
            id: "offline-files",
            label: "Offline Files",
            detail: "Files kept available for quick local access",
            bytes: 0
        )
    )
}

enum DeviceStorageService {

    private static let drawingDirectoryName = "notes"
    private static let overlayImageDirectoryName = "images"
    private static let usersDirectoryName = "users"

    // MARK: - Public API

    /// Walks the on-disk app sandbox off the main thread and returns a
    /// freshly measured `StorageReport`. Safe to call from any actor —
    /// the heavy IO runs inside `Task.detached`.
    static func measure() async -> StorageReport {
        await Task.detached(priority: .utility) {
            measureSync()
        }.value
    }

    /// Clears `URLCache.shared` plus the contents of
    /// `Library/Caches/<bundle>/`. Returns the freshly measured report.
    @discardableResult
    static func clearMediaCache() async -> StorageReport {
        await Task.detached(priority: .utility) {
            URLCache.shared.removeAllCachedResponses()
            if let cachesRoot = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            ) {
                if let items = try? FileManager.default.contentsOfDirectory(
                    at: cachesRoot,
                    includingPropertiesForKeys: nil
                ) {
                    for url in items {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            return measureSync()
        }.value
    }

    /// Removes the per-note overlay images bucket — `Documents/users/*/notes/*/images/*` —
    /// for every user. The underlying PKDrawing files stay put so notes
    /// continue to render; only the imported images are deleted.
    @discardableResult
    static func clearOfflineFiles() async -> StorageReport {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            if let usersRoot = documentsURL()?.appendingPathComponent(usersDirectoryName, isDirectory: true),
               let userFolders = try? fm.contentsOfDirectory(at: usersRoot, includingPropertiesForKeys: nil) {
                for userFolder in userFolders {
                    let drawings = userFolder.appendingPathComponent(drawingDirectoryName, isDirectory: true)
                    if let noteFolders = try? fm.contentsOfDirectory(at: drawings, includingPropertiesForKeys: nil) {
                        for note in noteFolders {
                            let imagesFolder = note.appendingPathComponent(overlayImageDirectoryName, isDirectory: true)
                            try? fm.removeItem(at: imagesFolder)
                        }
                    }
                }
            }
            return measureSync()
        }.value
    }

    // MARK: - Synchronous helpers

    private static func measureSync() -> StorageReport {
        var report = StorageReport.empty

        let fm = FileManager.default
        guard let documents = documentsURL() else { return report }

        // Documents/users — note-library + offline-images buckets.
        let usersRoot = documents.appendingPathComponent(usersDirectoryName, isDirectory: true)
        if let userFolders = try? fm.contentsOfDirectory(at: usersRoot, includingPropertiesForKeys: nil) {
            for userFolder in userFolders {
                // `notes-store.json` and everything else at the user-root
                // counts as Note Library, except the `notes/` tree (which
                // we split further below).
                if let items = try? fm.contentsOfDirectory(at: userFolder, includingPropertiesForKeys: nil) {
                    for item in items {
                        let name = item.lastPathComponent
                        if name == drawingDirectoryName {
                            walkDrawingsRoot(item, report: &report)
                        } else if !name.hasPrefix(".") {
                            report.noteLibrary.bytes += sizeOfTree(at: item)
                        }
                    }
                }
            }
        }

        // Catch-all: any other Documents top-level file (legacy v1 store,
        // imported PDFs) still belongs to the Note Library bucket.
        if let topLevel = try? fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            for url in topLevel where url.lastPathComponent != usersDirectoryName {
                report.noteLibrary.bytes += sizeOfTree(at: url)
            }
        }

        // Library/Caches → Media Cache (plus the in-memory URLCache).
        if let cachesRoot = try? fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            report.mediaCache.bytes += sizeOfTree(at: cachesRoot)
        }
        report.mediaCache.bytes += Int64(URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage)

        // tmp/ is opportunistic image/PDF scratch space; group it with
        // Media Cache so the user can wipe it together.
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        report.mediaCache.bytes += sizeOfTree(at: tmpRoot)

        return report
    }

    private static func documentsURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Walks `users/<uid>/notes`. Each `<noteId>` folder's `images/`
    /// subfolder counts as Offline Files; everything else (the .drawing
    /// PencilKit blobs) belongs to the Note Library bucket.
    private static func walkDrawingsRoot(_ drawingsRoot: URL, report: inout StorageReport) {
        let fm = FileManager.default
        guard let noteFolders = try? fm.contentsOfDirectory(at: drawingsRoot, includingPropertiesForKeys: nil) else {
            return
        }
        for note in noteFolders {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: note.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                report.noteLibrary.bytes += sizeOfFile(at: note)
                continue
            }
            if let items = try? fm.contentsOfDirectory(at: note, includingPropertiesForKeys: nil) {
                for item in items {
                    if item.lastPathComponent == overlayImageDirectoryName {
                        report.offlineFiles.bytes += sizeOfTree(at: item)
                    } else {
                        report.noteLibrary.bytes += sizeOfTree(at: item)
                    }
                }
            }
        }
    }

    /// Returns the cumulative allocated size of a single file or the
    /// whole directory tree rooted at `url`. Uses `.fileSizeKey` so
    /// reported numbers match what the iOS Settings → Storage screen
    /// would show (without the directory-block overhead).
    private static func sizeOfTree(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return sizeOfFile(at: url) }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            total += sizeOfFile(at: item)
        }
        return total
    }

    private static func sizeOfFile(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else {
            return 0
        }
        if let bytes = values.totalFileAllocatedSize {
            return Int64(bytes)
        }
        if let bytes = values.fileSize {
            return Int64(bytes)
        }
        return 0
    }
}

// MARK: - Formatting

extension Int64 {
    /// Compact human-friendly representation used by the Storage panel.
    /// Picks KB/MB/GB based on magnitude so a fresh install shows
    /// "12 KB" instead of "0 MB".
    func formattedAsStorageSize() -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        bcf.allowedUnits = [.useKB, .useMB, .useGB]
        bcf.includesUnit = true
        return bcf.string(fromByteCount: self)
    }
}
