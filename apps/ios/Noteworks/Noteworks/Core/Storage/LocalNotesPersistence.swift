//
//  LocalNotesPersistence.swift
//  Noteworks
//
//  File-IO helpers behind `NotesStore`. Every path is scoped to an
//  `activeUserId` so two accounts on the same device never see each other's
//  bubbles, notes, or drawings.
//
//  Layout under `Documents/`:
//
//    users/
//      <userId>/
//        notes-store.json          ← bubble list + note metadata (debounced)
//        notes/<noteId>/<page>.drawing  ← raw PKDrawing bytes
//        .migrated                 ← per-user "legacy import already ran" flag
//      .legacy-migrated            ← device-wide flag: legacy migration claimed
//
//  When no user is active, all IO is a no-op. Schedule a save right after
//  `clearActiveUser()` and the pending work item is cancelled before it can
//  write to a stale path.
//

import Foundation
import PencilKit

final class LocalNotesPersistence {

    static let shared = LocalNotesPersistence()

    // MARK: - Filenames

    private let storeFilename = "notes-store.json"
    private let drawingDirectoryName = "notes"
    private let overlayImageDirectoryName = "images"
    private let perUserSentinelName = ".migrated"
    private let deviceWideSentinelName = ".legacy-migrated"
    private let usersDirectoryName = "users"

    // MARK: - Roots

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var usersRootURL: URL {
        documentsURL.appendingPathComponent(usersDirectoryName, isDirectory: true)
    }

    private func userRoot(for userId: String) -> URL {
        usersRootURL.appendingPathComponent(userId, isDirectory: true)
    }

    private func storeURL(for userId: String) -> URL {
        userRoot(for: userId).appendingPathComponent(storeFilename)
    }

    private func drawingsRootURL(for userId: String) -> URL {
        userRoot(for: userId).appendingPathComponent(drawingDirectoryName, isDirectory: true)
    }

    private func drawingFolder(for userId: String, noteId: String) -> URL {
        drawingsRootURL(for: userId).appendingPathComponent(noteId, isDirectory: true)
    }

    private func drawingURL(for userId: String, noteId: String, page: Int) -> URL {
        drawingFolder(for: userId, noteId: noteId).appendingPathComponent("\(page).drawing")
    }

    private func overlayImageFolder(for userId: String, noteId: String) -> URL {
        drawingFolder(for: userId, noteId: noteId)
            .appendingPathComponent(overlayImageDirectoryName, isDirectory: true)
    }

    private func overlayImageURL(for userId: String, noteId: String, filename: String) -> URL {
        overlayImageFolder(for: userId, noteId: noteId).appendingPathComponent(filename)
    }

    /// v1 storage path — used only for one-shot per-note migration.
    private func legacyPerNoteDrawingURL(for userId: String, noteId: String) -> URL {
        drawingsRootURL(for: userId).appendingPathComponent("\(noteId).drawing")
    }

    /// Pre-Plan-2 device-wide layout.
    private var deviceWideLegacyStoreURL: URL {
        documentsURL.appendingPathComponent(storeFilename)
    }
    private var deviceWideLegacyDrawingsRootURL: URL {
        documentsURL.appendingPathComponent(drawingDirectoryName, isDirectory: true)
    }
    private var deviceWideMigrationSentinelURL: URL {
        usersRootURL.appendingPathComponent(deviceWideSentinelName)
    }

    // Convenience that returns `nil` once we're signed out — every public
    // method below short-circuits on it.
    private var currentStoreURL: URL? {
        guard let uid = activeUserId else { return nil }
        return storeURL(for: uid)
    }

    // MARK: - State

    /// All writes/reads to `activeUserId` happen from the main actor (the
    /// store calls into us from `@MainActor`). The serial `queue` is used
    /// only to actually touch the filesystem.
    private var activeUserId: String?

    private let queue = DispatchQueue(label: "com.noteworks.localnotespersistence", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceSeconds: TimeInterval = 0.25

    // MARK: - Init

    private init() {}

    // MARK: - User lifecycle

    /// Binds all subsequent IO to `userId`. Drains any pending debounced
    /// save first so a freshly-signed-out user's snapshot never lands in
    /// the next user's folder. Returns the freshly-loaded snapshot (or
    /// `nil` for a brand-new account with no on-disk file yet).
    @discardableResult
    func setActiveUser(_ userId: String) -> StoreSnapshot? {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        activeUserId = userId

        let root = userRoot(for: userId)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        migrateDeviceWideLegacyIfNeeded(into: userId)
        return loadStore()
    }

    /// Drops the active user binding. After this call every public method
    /// is a no-op until `setActiveUser(_:)` runs again.
    func clearActiveUser() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        activeUserId = nil
    }

    // MARK: - Snapshot IO

    /// Loads and decodes the active user's notes-store JSON. Returns `nil`
    /// for a brand-new user (file missing), no active user, or
    /// unrecoverable decode errors. The v1 → v2 schema fixup that used to
    /// run device-wide now runs inside the active user's folder so each
    /// account gets the migration exactly once.
    func loadStore() -> StoreSnapshot? {
        guard let url = currentStoreURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let snapshot = try? decoder.decode(StoreSnapshot.self, from: data),
               snapshot.schemaVersion >= StoreSnapshot.currentSchemaVersion {
                return snapshot
            }
            if let migrated = migrateLegacyStoreSchema(data: data) {
                saveImmediately(migrated)
                return migrated
            }
            return try decoder.decode(StoreSnapshot.self, from: data)
        } catch {
            #if DEBUG
            print("[NotesStore] Failed to decode \(url.lastPathComponent): \(error)")
            #endif
            return nil
        }
    }

    /// Schedules a debounced save so back-to-back updates collapse into one
    /// disk write. Captures the destination URL synchronously so a
    /// sign-out racing with the debounce timer cannot redirect the write.
    func scheduleSave(_ snapshot: StoreSnapshot) {
        guard let url = currentStoreURL else { return }
        pendingSaveWorkItem?.cancel()
        let item = DispatchWorkItem {
            Self.writeSnapshotToDisk(snapshot, at: url)
        }
        pendingSaveWorkItem = item
        queue.asyncAfter(deadline: .now() + saveDebounceSeconds, execute: item)
    }

    /// Writes immediately, bypassing the debounce. Used by the schema
    /// migration so the rewritten JSON lands before the next launch.
    func saveImmediately(_ snapshot: StoreSnapshot) {
        guard let url = currentStoreURL else { return }
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        queue.sync { Self.writeSnapshotToDisk(snapshot, at: url) }
    }

    private static func writeSnapshotToDisk(_ snapshot: StoreSnapshot, at url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("[NotesStore] Failed to write \(url.lastPathComponent): \(error)")
            #endif
        }
    }

    // MARK: - v1 → current schema migration (inside one user's folder)

    /// Decodes the snapshot using the lenient pre-`pageSettings` shape and
    /// hydrates the new fields (`bookmarked`, `currentPage`, `pageSettings`)
    /// from `pageCount` so existing data round-trips cleanly.
    private func migrateLegacyStoreSchema(data: Data) -> StoreSnapshot? {
        struct LegacyNote: Decodable {
            let id: String
            var title: String
            var subject: String?
            var tag: String?
            var sharedBy: String?
            var pageCount: Int
            var createdAt: Date
            var updatedAt: Date
            var bookmarked: Bool?
            var currentPage: Int?
            var pageSettings: [NotePageSetting]?
        }
        struct LegacySnapshot: Decodable {
            var bubbleNames: [String]
            var bubbles: [NoteBubble]?
            var notes: [LegacyNote]
            var schemaVersion: Int
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? decoder.decode(LegacySnapshot.self, from: data) else {
            return nil
        }
        let migratedNotes: [Note] = legacy.notes.map { old in
            let pageSettings = old.pageSettings ?? Array(
                repeating: NotePageSetting(),
                count: max(1, old.pageCount)
            )
            return Note(
                id: old.id,
                title: old.title,
                subject: old.subject,
                tag: old.tag,
                sharedBy: old.sharedBy,
                pageCount: max(1, old.pageCount),
                createdAt: old.createdAt,
                updatedAt: old.updatedAt,
                bookmarked: old.bookmarked ?? false,
                currentPage: max(1, min(old.currentPage ?? 1, max(1, old.pageCount))),
                pageSettings: pageSettings
            )
        }
        for note in migratedNotes {
            migrateLegacyPerNoteDrawing(for: note.id)
        }
        return StoreSnapshot(
            bubbleNames: legacy.bubbleNames,
            bubbles: legacy.bubbles ?? legacy.bubbleNames.map { NoteBubble(name: $0, courseCode: $0) },
            notes: migratedNotes,
            schemaVersion: StoreSnapshot.currentSchemaVersion
        )
    }

    /// v1 stored each note's PKDrawing at `notes/<id>.drawing` instead of
    /// `notes/<id>/0.drawing`. Move the file in-place when we encounter it.
    private func migrateLegacyPerNoteDrawing(for noteId: String) {
        guard let userId = activeUserId else { return }
        let legacy = legacyPerNoteDrawingURL(for: userId, noteId: noteId)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let folder = drawingFolder(for: userId, noteId: noteId)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = drawingURL(for: userId, noteId: noteId, page: 0)
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.moveItem(at: legacy, to: target)
            } else {
                try? FileManager.default.removeItem(at: legacy)
            }
        } catch {
            #if DEBUG
            print("[NotesStore] Drawing migration failed for \(noteId): \(error)")
            #endif
        }
    }

    // MARK: - One-shot device-wide legacy migration

    /// Copies the pre-Plan-2 device-wide files into the first user who
    /// opens the upgraded app, then writes a device-wide sentinel so
    /// subsequent users (a different account on the same device, or this
    /// user's first sign-in after the migration already happened) start
    /// from a fresh state.
    ///
    /// Skip conditions, in order:
    /// 1. The current user already has a per-user `notes-store.json`.
    /// 2. The current user already has a `.migrated` sentinel.
    /// 3. The device-wide sentinel exists (another account on this device
    ///    already claimed the legacy data).
    /// 4. There is no device-wide legacy file to migrate from.
    private func migrateDeviceWideLegacyIfNeeded(into userId: String) {
        let fm = FileManager.default
        let userRoot = userRoot(for: userId)
        let perUserSentinel = userRoot.appendingPathComponent(perUserSentinelName)

        if fm.fileExists(atPath: storeURL(for: userId).path) { return }
        if fm.fileExists(atPath: perUserSentinel.path) { return }
        if fm.fileExists(atPath: deviceWideMigrationSentinelURL.path) { return }
        guard fm.fileExists(atPath: deviceWideLegacyStoreURL.path) else { return }

        do {
            try fm.createDirectory(at: userRoot, withIntermediateDirectories: true)
            try fm.copyItem(at: deviceWideLegacyStoreURL, to: storeURL(for: userId))
            if fm.fileExists(atPath: deviceWideLegacyDrawingsRootURL.path) {
                try fm.copyItem(
                    at: deviceWideLegacyDrawingsRootURL,
                    to: drawingsRootURL(for: userId)
                )
            }
            try fm.createDirectory(
                at: usersRootURL,
                withIntermediateDirectories: true
            )
            try Data().write(to: perUserSentinel)
            try Data().write(to: deviceWideMigrationSentinelURL)
            #if DEBUG
            print("[NotesStore] Imported device-wide legacy library into user \(userId.prefix(8))…")
            #endif
        } catch {
            #if DEBUG
            print("[NotesStore] Device-wide legacy migration failed: \(error)")
            #endif
        }
    }

    // MARK: - Drawing IO

    private func ensureDrawingFolderExists(userId: String, noteId: String) {
        let folder = drawingFolder(for: userId, noteId: noteId)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
    }

    func loadDrawing(for noteId: String, page: Int) -> PKDrawing? {
        guard let userId = activeUserId else { return nil }
        let url = drawingURL(for: userId, noteId: noteId, page: page)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try PKDrawing(data: data)
        } catch {
            #if DEBUG
            print("[NotesStore] Failed to load drawing \(url.lastPathComponent): \(error)")
            #endif
            return nil
        }
    }

    func saveDrawing(_ drawing: PKDrawing, for noteId: String, page: Int) {
        guard let userId = activeUserId else { return }
        ensureDrawingFolderExists(userId: userId, noteId: noteId)
        let url = drawingURL(for: userId, noteId: noteId, page: page)
        let data = drawing.dataRepresentation()
        queue.async {
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                #if DEBUG
                print("[NotesStore] Failed to write drawing \(url.lastPathComponent): \(error)")
                #endif
            }
        }
    }

    func deleteDrawing(for noteId: String, page: Int) {
        guard let userId = activeUserId else { return }
        let url = drawingURL(for: userId, noteId: noteId, page: page)
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteAllDrawings(for noteId: String) {
        guard let userId = activeUserId else { return }
        let folder = drawingFolder(for: userId, noteId: noteId)
        let legacy = legacyPerNoteDrawingURL(for: userId, noteId: noteId)
        queue.async {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    /// Renumbers drawing files inside a note's folder by `delta` slots,
    /// starting at `fromIndex` (inclusive). Used to make/heal a hole when
    /// inserting or deleting a page. The folder URL is captured up-front
    /// so a sign-out racing with the dispatched work cannot redirect us.
    func shiftDrawings(for noteId: String, fromIndex: Int, by delta: Int) {
        guard delta != 0, let userId = activeUserId else { return }
        ensureDrawingFolderExists(userId: userId, noteId: noteId)
        let folder = drawingFolder(for: userId, noteId: noteId)
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let existingIndices: [Int] = contents.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            return Int(name)
        }
        let affected = existingIndices.filter { $0 >= fromIndex }.sorted()
        // Positive delta: move from highest down so we never overwrite a
        // file we still need. Negative delta: move from lowest up.
        let order = delta > 0 ? affected.reversed() : Array(affected)
        queue.async {
            for index in order {
                let src = folder.appendingPathComponent("\(index).drawing")
                let dst = folder.appendingPathComponent("\(index + delta).drawing")
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: src, to: dst)
            }
        }
    }

    /// Copies the drawing at `fromIndex` to `toIndex` inside the note's
    /// folder. No-op if the source file doesn't exist.
    func copyDrawing(for noteId: String, fromIndex: Int, toIndex: Int) {
        guard let userId = activeUserId else { return }
        let src = drawingURL(for: userId, noteId: noteId, page: fromIndex)
        let dst = drawingURL(for: userId, noteId: noteId, page: toIndex)
        queue.async {
            let fm = FileManager.default
            guard fm.fileExists(atPath: src.path) else { return }
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        }
    }

    // MARK: - Overlay image IO

    private func ensureOverlayImageFolderExists(userId: String, noteId: String) {
        let folder = overlayImageFolder(for: userId, noteId: noteId)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    /// Persists raw image bytes (PNG/JPEG, caller's choice) for a note
    /// overlay. `filename` should be a UUID-derived name with extension
    /// so concurrent saves can't collide.
    func saveOverlayImage(_ data: Data, for noteId: String, filename: String) {
        guard let userId = activeUserId else { return }
        ensureOverlayImageFolderExists(userId: userId, noteId: noteId)
        let url = overlayImageURL(for: userId, noteId: noteId, filename: filename)
        queue.async {
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                #if DEBUG
                print("[NotesStore] Failed to write overlay image \(url.lastPathComponent): \(error)")
                #endif
            }
        }
    }

    /// Loads previously-persisted overlay image bytes. Returns `nil` for
    /// a missing file or no active user (e.g. mid-sign-out).
    func loadOverlayImage(for noteId: String, filename: String) -> Data? {
        guard let userId = activeUserId else { return nil }
        let url = overlayImageURL(for: userId, noteId: noteId, filename: filename)
        return try? Data(contentsOf: url)
    }

    /// Removes a single overlay image file. Safe to call for files that
    /// don't exist.
    func deleteOverlayImage(for noteId: String, filename: String) {
        guard let userId = activeUserId else { return }
        let url = overlayImageURL(for: userId, noteId: noteId, filename: filename)
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
