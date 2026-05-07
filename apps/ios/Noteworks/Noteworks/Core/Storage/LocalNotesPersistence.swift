//
//  LocalNotesPersistence.swift
//  Noteworks
//
//  File-IO helpers behind `NotesStore`. Two surfaces:
//
//  1. Snapshot JSON (`Documents/notes-store.json`) — bubble list + note
//     metadata. Saves are debounced (250ms) so frequent updates from a live
//     drawing canvas do not write a file every stroke.
//  2. Per-note, per-page drawings
//     (`Documents/notes/<noteId>/<pageIdx>.drawing`) — raw bytes from
//     `PKDrawing.dataRepresentation()`. Stored separately from the JSON so
//     the metadata file stays small and a corrupt drawing cannot lose the
//     whole library. The `<noteId>` folder is created lazily.
//
//  This is local-first storage; Phase 2 will layer Supabase sync on top.
//

import Foundation
import PencilKit

final class LocalNotesPersistence {

    static let shared = LocalNotesPersistence()

    // MARK: - Paths

    private let storeFilename = "notes-store.json"
    private let drawingDirectoryName = "notes"

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var storeURL: URL {
        documentsURL.appendingPathComponent(storeFilename)
    }

    private var drawingsRootURL: URL {
        documentsURL.appendingPathComponent(drawingDirectoryName, isDirectory: true)
    }

    private func drawingFolder(for noteId: String) -> URL {
        drawingsRootURL.appendingPathComponent(noteId, isDirectory: true)
    }

    private func drawingURL(for noteId: String, page: Int) -> URL {
        drawingFolder(for: noteId).appendingPathComponent("\(page).drawing")
    }

    /// v1 storage path — used only for one-shot migration.
    private func legacyDrawingURL(for noteId: String) -> URL {
        drawingsRootURL.appendingPathComponent("\(noteId).drawing")
    }

    // MARK: - State

    private let queue = DispatchQueue(label: "com.noteworks.localnotespersistence", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceSeconds: TimeInterval = 0.25

    // MARK: - Init

    private init() {
        ensureDrawingsRootExists()
    }

    // MARK: - Snapshot IO

    /// Loads and decodes the notes-store JSON. Returns nil for first-run
    /// (file missing) or unrecoverable decode errors so the caller can seed
    /// fresh defaults.
    ///
    /// Handles schema v1 → v2 migration transparently: v1 notes don't carry
    /// `bookmarked`, `currentPage`, or `pageSettings`. We decode the raw
    /// JSON, fill those defaults from `pageCount`, bump the schema version,
    /// and rewrite immediately so the next launch is clean.
    func loadStore() -> StoreSnapshot? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // Try the current schema first.
            if let snapshot = try? decoder.decode(StoreSnapshot.self, from: data),
               snapshot.schemaVersion >= StoreSnapshot.currentSchemaVersion {
                return snapshot
            }
            // Fall back to the v1-tolerant migration.
            if let migrated = migrateLegacyStore(data: data) {
                saveImmediately(migrated)
                return migrated
            }
            return try decoder.decode(StoreSnapshot.self, from: data)
        } catch {
            #if DEBUG
            print("[NotesStore] Failed to decode \(storeURL.lastPathComponent): \(error)")
            #endif
            return nil
        }
    }

    /// Schedules a debounced save so back-to-back updates collapse into one
    /// disk write. Safe to call from the main actor.
    func scheduleSave(_ snapshot: StoreSnapshot) {
        pendingSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeSnapshotToDisk(snapshot)
        }
        pendingSaveWorkItem = item
        queue.asyncAfter(deadline: .now() + saveDebounceSeconds, execute: item)
    }

    /// Writes immediately, bypassing the debounce. Used for first-run seed
    /// so a relaunch right after install still finds the data.
    func saveImmediately(_ snapshot: StoreSnapshot) {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        queue.sync { writeSnapshotToDisk(snapshot) }
    }

    private func writeSnapshotToDisk(_ snapshot: StoreSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("[NotesStore] Failed to write \(storeURL.lastPathComponent): \(error)")
            #endif
        }
    }

    // MARK: - v1 → v2 migration

    /// Decodes the snapshot using the lenient pre-`pageSettings` shape and
    /// hydrates the new fields (`bookmarked`, `currentPage`, `pageSettings`)
    /// from `pageCount` so existing data round-trips cleanly.
    private func migrateLegacyStore(data: Data) -> StoreSnapshot? {
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
        // Move any v1 single-file drawings into their new per-note folders.
        for note in migratedNotes {
            migrateLegacyDrawing(for: note.id)
        }
        return StoreSnapshot(
            bubbleNames: legacy.bubbleNames,
            notes: migratedNotes,
            schemaVersion: StoreSnapshot.currentSchemaVersion
        )
    }

    /// If `Documents/notes/<id>.drawing` exists from v1, move it to
    /// `Documents/notes/<id>/0.drawing`. No-op when the new layout already
    /// exists.
    private func migrateLegacyDrawing(for noteId: String) {
        let legacy = legacyDrawingURL(for: noteId)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let folder = drawingFolder(for: noteId)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = drawingURL(for: noteId, page: 0)
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

    // MARK: - Drawing IO

    private func ensureDrawingsRootExists() {
        if !FileManager.default.fileExists(atPath: drawingsRootURL.path) {
            try? FileManager.default.createDirectory(
                at: drawingsRootURL,
                withIntermediateDirectories: true
            )
        }
    }

    private func ensureDrawingFolderExists(for noteId: String) {
        let folder = drawingFolder(for: noteId)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
    }

    func loadDrawing(for noteId: String, page: Int) -> PKDrawing? {
        let url = drawingURL(for: noteId, page: page)
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
        ensureDrawingFolderExists(for: noteId)
        let url = drawingURL(for: noteId, page: page)
        let data = drawing.dataRepresentation()
        // Drawings can be a few hundred KB — write off the main thread.
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
        let url = drawingURL(for: noteId, page: page)
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteAllDrawings(for noteId: String) {
        let folder = drawingFolder(for: noteId)
        let legacy = legacyDrawingURL(for: noteId)
        queue.async {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    /// Renumbers drawing files inside a note's folder by `delta` slots,
    /// starting at `fromIndex` (inclusive). Used to make/heal a hole when
    /// inserting or deleting a page.
    ///
    /// `delta = +1` shifts files at indices `[fromIndex, ∞)` up by one
    /// (e.g. `5.drawing` → `6.drawing`). `delta = -1` shifts down. Performs
    /// the moves in the order that avoids overwrites.
    func shiftDrawings(for noteId: String, fromIndex: Int, by delta: Int) {
        guard delta != 0 else { return }
        ensureDrawingFolderExists(for: noteId)
        let folder = drawingFolder(for: noteId)
        let fm = FileManager.default
        // Snapshot the indices currently on disk (filenames are "<n>.drawing").
        let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let existingIndices: [Int] = contents.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            return Int(name)
        }
        let affected = existingIndices.filter { $0 >= fromIndex }.sorted()
        // For positive delta we move from the highest index down so we
        // never overwrite a file we still need. For negative delta we move
        // from lowest up.
        let order = delta > 0 ? affected.reversed() : Array(affected)
        queue.async { [weak self] in
            guard let self else { return }
            for index in order {
                let src = self.drawingURL(for: noteId, page: index)
                let dst = self.drawingURL(for: noteId, page: index + delta)
                try? fm.removeItem(at: dst)
                try? fm.moveItem(at: src, to: dst)
            }
        }
    }

    /// Copies the drawing at `fromIndex` to `toIndex` inside the note's
    /// folder. No-op if the source file doesn't exist.
    func copyDrawing(for noteId: String, fromIndex: Int, toIndex: Int) {
        let src = drawingURL(for: noteId, page: fromIndex)
        let dst = drawingURL(for: noteId, page: toIndex)
        queue.async {
            let fm = FileManager.default
            guard fm.fileExists(atPath: src.path) else { return }
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        }
    }
}
