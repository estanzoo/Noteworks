//
//  NotesStore.swift
//  Noteworks
//
//  The single source of truth for bubbles + notes across Home, Library, and
//  Canvas. Mirrors the JSX bubble model in `others/noteworks-library(2).jsx`
//  L6904–L7030 exactly: a bubble is just a string name, and a note carries a
//  single `subject: String?` that links it to one bubble. Renaming a bubble
//  bulk-rewrites those subjects; deleting one drops affected notes into the
//  Unnamed bucket.
//
//  This is local-first: the snapshot is persisted to
//  `Documents/notes-store.json` (debounced) and per-note PKDrawing bytes live
//  in `Documents/notes/<id>.drawing`. Phase 2 will wrap this store with a
//  Supabase sync layer.
//

import Foundation
import PencilKit
import Combine

// MARK: - Models

/// Per-page state attached to a note. Mirrors JSX `pageSettings[]`
/// (others/noteworks-library(2).jsx L2471–L2483): every page has an
/// independent background pattern + rotation. Drawing bytes live separately
/// on disk under `Documents/notes/<id>/<pageIdx>.drawing`.
struct NotePageSetting: Codable, Equatable, Hashable {
    var background: NotePageBackground
    var rotation: Int

    init(background: NotePageBackground = .blank, rotation: Int = 0) {
        self.background = background
        self.rotation = rotation
    }
}

/// Background pattern rendered behind the canvas. Matches the JSX
/// `backgroundOptions` array (L2562–L2566) — Blank / Dots / Single column.
enum NotePageBackground: String, Codable, CaseIterable, Hashable {
    case blank
    case dots
    case singleColumn = "single-column"

    var label: String {
        switch self {
        case .blank: return "Blank"
        case .dots: return "Dots"
        case .singleColumn: return "Single column"
        }
    }
}

/// Codable note record. Drawing bytes live separately on disk under
/// `Documents/notes/<id>/<pageIdx>.drawing` and are loaded lazily.
struct Note: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    /// The bubble the note belongs to. Single string, optional — JSX
    /// `note.subject` semantics (L23–L31). `nil` means the note sits in the
    /// "Unnamed" bucket.
    var subject: String?
    /// UI badge ("Draft", "Course", "Public", …). Independent of `subject`.
    var tag: String?
    var sharedBy: String?
    var pageCount: Int
    var createdAt: Date
    var updatedAt: Date
    /// Star/bookmark a note so it sorts to the top of the library and shows
    /// a filled badge on its card. Mirrors JSX `note.bookmarked`.
    var bookmarked: Bool = false
    /// Page the editor was last on (1-based, like the JSX). Restored on open.
    var currentPage: Int = 1
    /// One entry per page. Source of truth for page count is
    /// `pageSettings.count`; `pageCount` is kept in sync for the library card.
    var pageSettings: [NotePageSetting] = [NotePageSetting()]

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            return "TODAY"
        } else if calendar.isDateInYesterday(createdAt) {
            return "YESTERDAY"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MMM.dd  HH:mm"
            return f.string(from: createdAt).uppercased()
        }
    }
}

/// Persisted shape of the whole local store.
struct StoreSnapshot: Codable, Equatable {
    var bubbleNames: [String]
    var notes: [Note]
    /// Bumped by `LocalNotesPersistence` so we can migrate the JSON format
    /// later without nuking user data.
    var schemaVersion: Int

    /// v2 — adds `bookmarked`, `currentPage`, `pageSettings` to each note.
    /// Older snapshots are loaded with the missing fields defaulted in
    /// `LocalNotesPersistence.loadStore`.
    static let currentSchemaVersion = 2
}

// MARK: - NotesStore

@MainActor
final class NotesStore: ObservableObject {

    // MARK: - Published state

    /// Bubble name list — equivalent to JSX `bubbleCategories` (L6912).
    /// Order is preserved so the home bubble field is stable across launches.
    @Published private(set) var bubbleNames: [String] = []

    @Published private(set) var notes: [Note] = []

    /// Set when the user taps a bubble on Home. Read by `CourseSpaceView` on
    /// appear so the library opens pre-filtered. Mirrors JSX `activeSubject`
    /// (L6907 + `navigate(target, subject)` L6920–L6933).
    @Published var libraryFilter: String?

    // MARK: - Reserved names (match JSX L7002–L7004)

    static let reservedBubbleNames: Set<String> = ["unnamed", "uncategorized"]

    // MARK: - Dependencies

    private let persistence: LocalNotesPersistence

    // MARK: - Init

    init(persistence: LocalNotesPersistence = .shared, autoload: Bool = true) {
        self.persistence = persistence
        if autoload {
            load()
        }
    }

    // MARK: - Loading / saving

    private func load() {
        if let snapshot = persistence.loadStore() {
            bubbleNames = snapshot.bubbleNames
            notes = snapshot.notes
        } else {
            // First run — seed with the JSX-style defaults so the home + library
            // are not empty.
            let seed = NotesStore.firstRunSeed()
            bubbleNames = seed.bubbleNames
            notes = seed.notes
            saveNow()
        }
    }

    private var snapshot: StoreSnapshot {
        StoreSnapshot(
            bubbleNames: bubbleNames,
            notes: notes,
            schemaVersion: StoreSnapshot.currentSchemaVersion
        )
    }

    private func saveDebounced() {
        persistence.scheduleSave(snapshot)
    }

    private func saveNow() {
        persistence.saveImmediately(snapshot)
    }

    // MARK: - Bubble actions (mirror JSX L6999–L7030)

    /// Adds a new bubble. Returns `nil` on success, or an error message that
    /// the dialog should surface (mirrors JSX `createBubble` L6999–L7007).
    @discardableResult
    func addBubble(name rawName: String) -> String? {
        let name = NotesStore.normalizeBubbleName(rawName)
        guard !name.isEmpty else { return "Enter a bubble name." }
        if NotesStore.isReservedName(name) {
            return "That name is reserved for uncategorized notes."
        }
        if bubbleNameTaken(name) {
            return "A bubble with this name already exists."
        }
        bubbleNames.append(name)
        saveDebounced()
        return nil
    }

    /// Renames a bubble and bulk-rewrites every linked note's `subject`
    /// (mirrors JSX `renameBubble` L7010–L7023).
    @discardableResult
    func renameBubble(from currentName: String, to rawNextName: String) -> String? {
        let nextName = NotesStore.normalizeBubbleName(rawNextName)
        guard !nextName.isEmpty else { return "Enter a bubble name." }
        if NotesStore.isReservedName(nextName) {
            return "That name is reserved for uncategorized notes."
        }
        if currentName.caseInsensitiveCompare(nextName) == .orderedSame {
            return nil
        }
        if bubbleNameTaken(nextName, excluding: currentName) {
            return "A bubble with this name already exists."
        }

        bubbleNames = bubbleNames.map {
            $0.caseInsensitiveCompare(currentName) == .orderedSame ? nextName : $0
        }
        for idx in notes.indices {
            if notes[idx].subject?.caseInsensitiveCompare(currentName) == .orderedSame {
                notes[idx].subject = nextName
                notes[idx].updatedAt = Date()
            }
        }
        if libraryFilter?.caseInsensitiveCompare(currentName) == .orderedSame {
            libraryFilter = nextName
        }
        saveDebounced()
        return nil
    }

    /// Removes a bubble and sets matching notes' `subject` to nil so they
    /// fall into the Unnamed bucket (mirrors JSX `deleteBubble` L7026–L7030).
    func deleteBubble(name: String) {
        bubbleNames.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        for idx in notes.indices {
            if notes[idx].subject?.caseInsensitiveCompare(name) == .orderedSame {
                notes[idx].subject = nil
                notes[idx].updatedAt = Date()
            }
        }
        if libraryFilter?.caseInsensitiveCompare(name) == .orderedSame {
            libraryFilter = nil
        }
        saveDebounced()
    }

    // MARK: - Note actions

    /// Mirrors JSX `createDraftNote` (L182–L194) — produces a fresh draft and
    /// inserts it at the top of the list. Returns the new note so callers can
    /// navigate straight into the editor.
    @discardableResult
    func createDraftNote(subject: String? = nil, title: String? = nil) -> Note {
        let now = Date()
        let note = Note(
            id: UUID().uuidString,
            title: title ?? "Untitled Note",
            subject: subject,
            tag: "Draft",
            sharedBy: nil,
            pageCount: 1,
            createdAt: now,
            updatedAt: now,
            bookmarked: false,
            currentPage: 1,
            pageSettings: [NotePageSetting()]
        )
        notes.insert(note, at: 0)
        saveDebounced()
        return note
    }

    /// Partial update — only non-nil arguments are written. Drawing data is
    /// persisted separately to disk if provided (the metadata `updatedAt`
    /// timestamp is bumped either way).
    func updateNote(
        id: String,
        title: String? = nil,
        subject: SubjectUpdate = .keep,
        tag: TagUpdate = .keep,
        drawing: PKDrawing? = nil
    ) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }

        if let title { notes[idx].title = title }
        switch subject {
        case .keep: break
        case .clear: notes[idx].subject = nil
        case .set(let value): notes[idx].subject = value
        }
        switch tag {
        case .keep: break
        case .clear: notes[idx].tag = nil
        case .set(let value): notes[idx].tag = value
        }
        notes[idx].updatedAt = Date()

        if let drawing {
            // Legacy path: callers that don't know about pages always
            // address page 1 (the only page on a v1 note).
            let targetPage = max(1, notes[idx].currentPage) - 1
            persistence.saveDrawing(drawing, for: id, page: targetPage)
        }
        saveDebounced()
    }

    func deleteNote(id: String) {
        notes.removeAll { $0.id == id }
        persistence.deleteAllDrawings(for: id)
        saveDebounced()
    }

    func setBookmarked(noteId: String, value: Bool) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[idx].bookmarked = value
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    func setCurrentPage(noteId: String, page: Int) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let clamped = max(1, min(page, notes[idx].pageSettings.count))
        if notes[idx].currentPage == clamped { return }
        notes[idx].currentPage = clamped
        saveDebounced()
    }

    // MARK: - Page actions (mirror JSX L2630–L2705)

    /// Appends a blank page to the end of the note and jumps the active page
    /// to it. Mirrors `addBlankPage` (L2630).
    @discardableResult
    func addPage(noteId: String) -> Int? {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return nil }
        notes[idx].pageSettings.append(NotePageSetting())
        notes[idx].pageCount = notes[idx].pageSettings.count
        notes[idx].currentPage = notes[idx].pageSettings.count
        notes[idx].updatedAt = Date()
        saveDebounced()
        return notes[idx].currentPage
    }

    /// Duplicates the current page (settings + drawing) and lands on the
    /// copy. Mirrors `handleCopyPage` (L2639).
    @discardableResult
    func copyCurrentPage(noteId: String) -> Int? {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return nil }
        let page = notes[idx].currentPage
        let total = notes[idx].pageSettings.count
        let clamped = max(1, min(page, total))
        let setting = notes[idx].pageSettings[clamped - 1]
        // Settings: insert a copy right after the current page.
        notes[idx].pageSettings.insert(setting, at: clamped)
        notes[idx].pageCount = notes[idx].pageSettings.count
        notes[idx].currentPage = clamped + 1
        notes[idx].updatedAt = Date()
        // Disk: shift any drawings at indices ≥ clamped down by one, then
        // copy the original drawing to the new slot.
        persistence.shiftDrawings(for: noteId, fromIndex: clamped - 1, by: 1)
        persistence.copyDrawing(for: noteId, fromIndex: clamped - 1, toIndex: clamped)
        saveDebounced()
        return notes[idx].currentPage
    }

    /// Removes the current page. Refuses if it's the only page (returns
    /// "Can't delete the only page"). Mirrors `handleDeletePage` (L2668).
    @discardableResult
    func deleteCurrentPage(noteId: String) -> String? {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else {
            return "Note not found."
        }
        let total = notes[idx].pageSettings.count
        if total <= 1 {
            return "Can't delete the only page"
        }
        let page = notes[idx].currentPage
        let clamped = max(1, min(page, total))
        notes[idx].pageSettings.remove(at: clamped - 1)
        notes[idx].pageCount = notes[idx].pageSettings.count
        notes[idx].currentPage = min(clamped, notes[idx].pageSettings.count)
        notes[idx].updatedAt = Date()
        persistence.deleteDrawing(for: noteId, page: clamped - 1)
        // Shift any remaining drawings beyond the deleted one up by one.
        persistence.shiftDrawings(for: noteId, fromIndex: clamped, by: -1)
        saveDebounced()
        return nil
    }

    /// Sets the rotation (0/90/180/270) on the current page.
    func rotateCurrentPage(noteId: String, to rotation: Int) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let page = notes[idx].currentPage
        let clamped = max(1, min(page, notes[idx].pageSettings.count))
        notes[idx].pageSettings[clamped - 1].rotation = ((rotation % 360) + 360) % 360
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    func setBackground(noteId: String, background: NotePageBackground) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let page = notes[idx].currentPage
        let clamped = max(1, min(page, notes[idx].pageSettings.count))
        notes[idx].pageSettings[clamped - 1].background = background
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    /// Wipes drawing on the current page without removing the page itself.
    /// Mirrors `handleClearPage` (L2706) once it's confirmed.
    func clearCurrentPage(noteId: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let page = notes[idx].currentPage
        let clamped = max(1, min(page, notes[idx].pageSettings.count))
        persistence.saveDrawing(PKDrawing(), for: noteId, page: clamped - 1)
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    // MARK: - Drawing IO

    func loadDrawing(for noteId: String, page: Int) -> PKDrawing? {
        persistence.loadDrawing(for: noteId, page: page - 1)
    }

    func saveDrawing(_ drawing: PKDrawing, for noteId: String, page: Int) {
        persistence.saveDrawing(drawing, for: noteId, page: page - 1)
        if let idx = notes.firstIndex(where: { $0.id == noteId }) {
            notes[idx].updatedAt = Date()
            saveDebounced()
        }
    }

    func note(id: String) -> Note? {
        notes.first(where: { $0.id == id })
    }

    // MARK: - Lookups for the UI

    /// Live note count for a bubble. The "Unnamed"/"Uncategorized" name is
    /// treated specially — it counts notes with `subject == nil`.
    func noteCount(for bubbleName: String) -> Int {
        if NotesStore.isReservedName(bubbleName) {
            return notes.filter { ($0.subject ?? "").isEmpty }.count
        }
        return notes.filter {
            $0.subject?.caseInsensitiveCompare(bubbleName) == .orderedSame
        }.count
    }

    /// Whether any note currently has no subject — drives the auto-Unnamed
    /// bubble on Home (mirrors JSX `Unnamed` rollup at L1426–L1435).
    var hasUnnamedNotes: Bool {
        notes.contains(where: { ($0.subject ?? "").isEmpty })
    }

    // MARK: - Helpers

    private func bubbleNameTaken(_ name: String, excluding current: String? = nil) -> Bool {
        bubbleNames.contains { existing in
            if let current, existing.caseInsensitiveCompare(current) == .orderedSame {
                return false
            }
            return existing.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    static func normalizeBubbleName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isReservedName(_ name: String) -> Bool {
        reservedBubbleNames.contains(name.lowercased())
    }
}

// MARK: - Update enums

/// Three-state update value so the partial `updateNote` API can distinguish
/// "leave alone" from "set to nil" cleanly.
enum SubjectUpdate {
    case keep
    case clear
    case set(String)
}

enum TagUpdate {
    case keep
    case clear
    case set(String)
}

// MARK: - First-run seed (matches the previous in-memory defaults)

extension NotesStore {
    static func firstRunSeed() -> StoreSnapshot {
        let now = Date()
        let calendar = Calendar.current
        func date(monthsAgo: Int = 0, daysAgo: Int = 0) -> Date {
            var c = DateComponents()
            c.day = -daysAgo
            c.month = -monthsAgo
            return calendar.date(byAdding: c, to: now) ?? now
        }

        func seedNote(
            title: String,
            subject: String?,
            tag: String?,
            sharedBy: String?,
            pageCount: Int,
            createdAt: Date,
            bookmarked: Bool = false
        ) -> Note {
            Note(
                id: UUID().uuidString,
                title: title,
                subject: subject,
                tag: tag,
                sharedBy: sharedBy,
                pageCount: pageCount,
                createdAt: createdAt,
                updatedAt: createdAt,
                bookmarked: bookmarked,
                currentPage: 1,
                pageSettings: Array(repeating: NotePageSetting(), count: max(1, pageCount))
            )
        }

        let notes: [Note] = [
            seedNote(title: "Lab Report", subject: "Chemistry", tag: "Course", sharedBy: nil, pageCount: 9, createdAt: date(daysAgo: 9)),
            seedNote(title: "Cell Biology", subject: "Biology", tag: nil, sharedBy: "Amy", pageCount: 16, createdAt: date(daysAgo: 1)),
            seedNote(title: "Organic Chem", subject: "Chemistry", tag: "Public", sharedBy: "Sam", pageCount: 34, createdAt: now),
            seedNote(title: "Grammer Rules", subject: nil, tag: "Course", sharedBy: "Sam", pageCount: 11, createdAt: date(daysAgo: 13)),
            seedNote(title: "Perspective Drawing", subject: "Art", tag: nil, sharedBy: nil, pageCount: 6, createdAt: date(daysAgo: 15)),
            seedNote(title: "Physics Lab 3", subject: "Physics", tag: nil, sharedBy: nil, pageCount: 4, createdAt: date(daysAgo: 18)),
            seedNote(title: "Calc II Notes", subject: "Mathematics", tag: "Course", sharedBy: nil, pageCount: 12, createdAt: date(daysAgo: 21)),
            seedNote(title: "Calc III Review", subject: "Mathematics", tag: nil, sharedBy: nil, pageCount: 8, createdAt: date(daysAgo: 23)),
        ]
        let bubbleNames = ["Biology", "Art", "Physics", "Chemistry", "Mathematics"]

        return StoreSnapshot(
            bubbleNames: bubbleNames,
            notes: notes,
            schemaVersion: StoreSnapshot.currentSchemaVersion
        )
    }
}
