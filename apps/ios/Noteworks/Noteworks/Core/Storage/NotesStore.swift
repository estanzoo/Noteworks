//
//  NotesStore.swift
//  Noteworks
//
//  The single source of truth for bubbles + notes across Home, Library, and
//  Canvas. Mirrors the JSX bubble model in `others/noteworks-library(2).jsx`
//  L6904–L7030 exactly: a bubble is just a string name, and a note carries a
//  single `subject: String?` that links it to one bubble. Renaming a bubble
//  bulk-rewrites those subjects; deleting one drops affected notes into the
//  Unnamed bucket — orphan notes file into `initialGuestBubbleName`
//  ("Untitled Bubble") instead.
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
    /// Optional page-sized image rendered underneath PencilKit. Used for
    /// imported PDFs so ink appears above the document instead of behind it.
    var backgroundImageFilename: String?
    /// Height ÷ width for this logical page. Blank notes use the reference
    /// editor aspect; imported PDF pages preserve their original shape.
    var aspectHeightOverWidth: CGFloat

    init(
        background: NotePageBackground = .blank,
        rotation: Int = 0,
        backgroundImageFilename: String? = nil,
        aspectHeightOverWidth: CGFloat = 1.4
    ) {
        self.background = background
        self.rotation = rotation
        self.backgroundImageFilename = backgroundImageFilename
        self.aspectHeightOverWidth = aspectHeightOverWidth
    }

    private enum CodingKeys: String, CodingKey {
        case background, rotation, backgroundImageFilename, aspectHeightOverWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = (try c.decodeIfPresent(NotePageBackground.self, forKey: .background)) ?? .blank
        rotation = (try c.decodeIfPresent(Int.self, forKey: .rotation)) ?? 0
        backgroundImageFilename = try c.decodeIfPresent(String.self, forKey: .backgroundImageFilename)
        aspectHeightOverWidth = (try c.decodeIfPresent(CGFloat.self, forKey: .aspectHeightOverWidth)) ?? 1.4
    }
}

/// Background pattern rendered behind the canvas.
enum NotePageBackground: String, Codable, CaseIterable, Hashable {
    case blank
    case dots
    /// Horizontal ruled lines. Raw value kept for saved notes compatibility.
    case singleColumn = "single-column"
    case grid
    case cornell

    var label: String {
        switch self {
        case .blank: return "Blank"
        case .dots: return "Dots"
        case .singleColumn: return "Ruled"
        case .grid: return "Grid"
        case .cornell: return "Cornell"
        }
    }
}

/// Local bubble metadata. `name` remains the user-facing bubble label while
/// `courseId` stores the backend `courses.id` used by notes/posts.
///
/// `manualOffsetX` / `manualOffsetY` are populated when the user drags a
/// bubble in Home's edit mode. They're fractional offsets from the
/// container center (range roughly `-0.5 … 0.5`), so they survive iPad
/// rotation, split-view resize, and different iPad sizes. `nil` means
/// "use the auto slot layout in `HomeBubbleLayout`" — that's the
/// default for every bubble until the user moves it.
struct NoteBubble: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var courseId: String?
    var courseCode: String?
    var manualOffsetX: Double?
    var manualOffsetY: Double?

    init(
        id: String = UUID().uuidString,
        name: String,
        courseId: String? = nil,
        courseCode: String? = nil,
        manualOffsetX: Double? = nil,
        manualOffsetY: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.courseId = courseId
        self.courseCode = courseCode
        self.manualOffsetX = manualOffsetX
        self.manualOffsetY = manualOffsetY
    }
}

// MARK: - Page overlays (text + image stickers on top of the canvas)

/// Whether the overlay is a text box or an image. PencilKit can't host
/// either natively, so the editor renders a SwiftUI overlay layer above
/// the canvas with these items.
enum NotePageOverlayKind: String, Codable, Hashable {
    case text
    case image
    case shape
}

/// A draggable item placed on top of a note page. Coordinates are stored
/// in normalized [0…1] units against the page rect so they survive page
/// rotation, device rotation, and zoom without re-anchoring.
struct NotePageOverlay: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let kind: NotePageOverlayKind
    var page: Int                   // 1-based, matching `Note.currentPage`
    var normX: CGFloat              // top-left x, 0…1 of page width
    var normY: CGFloat              // top-left y, 0…1 of page height
    var normW: CGFloat              // width as fraction of page width
    var normH: CGFloat              // height as fraction of page height

    // .text fields
    var text: String?
    var fontSize: CGFloat?
    /// 6-digit hex (e.g. "1C1C1E") — kept as a string so it round-trips
    /// in JSON without dragging UIColor/Color into the model layer.
    var colorHex: String?

    // .image fields
    /// Filename relative to the note's image folder. The full path is
    /// resolved by `LocalNotesPersistence` so the model doesn't need to
    /// know about users / disk layout.
    var imageFilename: String?
    /// Clockwise rotation in degrees (image + shape overlays).
    var rotationDegrees: CGFloat = 0
    /// `NoteShapeType.rawValue` for `.shape` overlays.
    var shapeType: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, page, normX, normY, normW, normH
        case text, fontSize, colorHex, imageFilename, rotationDegrees, shapeType
    }

    init(
        id: String,
        kind: NotePageOverlayKind,
        page: Int,
        normX: CGFloat,
        normY: CGFloat,
        normW: CGFloat,
        normH: CGFloat,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        colorHex: String? = nil,
        imageFilename: String? = nil,
        rotationDegrees: CGFloat = 0,
        shapeType: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.page = page
        self.normX = normX
        self.normY = normY
        self.normW = normW
        self.normH = normH
        self.text = text
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.imageFilename = imageFilename
        self.rotationDegrees = rotationDegrees
        self.shapeType = shapeType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(NotePageOverlayKind.self, forKey: .kind)
        page = try c.decode(Int.self, forKey: .page)
        normX = try c.decode(CGFloat.self, forKey: .normX)
        normY = try c.decode(CGFloat.self, forKey: .normY)
        normW = try c.decode(CGFloat.self, forKey: .normW)
        normH = try c.decode(CGFloat.self, forKey: .normH)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        imageFilename = try c.decodeIfPresent(String.self, forKey: .imageFilename)
        rotationDegrees = (try c.decodeIfPresent(CGFloat.self, forKey: .rotationDegrees)) ?? 0
        shapeType = try c.decodeIfPresent(String.self, forKey: .shapeType)
    }

    func duplicate(offsetNorm: CGSize = CGSize(width: 0.03, height: 0.03)) -> NotePageOverlay {
        NotePageOverlay(
            id: UUID().uuidString,
            kind: kind,
            page: page,
            normX: min(1 - normW, normX + offsetNorm.width),
            normY: min(1 - normH, normY + offsetNorm.height),
            normW: normW,
            normH: normH,
            text: text,
            fontSize: fontSize,
            colorHex: colorHex,
            imageFilename: imageFilename,
            rotationDegrees: rotationDegrees,
            shapeType: shapeType
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(page, forKey: .page)
        try c.encode(normX, forKey: .normX)
        try c.encode(normY, forKey: .normY)
        try c.encode(normW, forKey: .normW)
        try c.encode(normH, forKey: .normH)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(fontSize, forKey: .fontSize)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(imageFilename, forKey: .imageFilename)
        if rotationDegrees != 0 {
            try c.encode(rotationDegrees, forKey: .rotationDegrees)
        }
        try c.encodeIfPresent(shapeType, forKey: .shapeType)
    }

    static func text(
        page: Int,
        text: String,
        fontSize: CGFloat = 18,
        colorHex: String = "1C1C1E",
        normRect: CGRect = CGRect(x: 0.2, y: 0.42, width: 0.6, height: 0.12)
    ) -> NotePageOverlay {
        NotePageOverlay(
            id: UUID().uuidString,
            kind: .text,
            page: page,
            normX: normRect.minX,
            normY: normRect.minY,
            normW: normRect.width,
            normH: normRect.height,
            text: text,
            fontSize: fontSize,
            colorHex: colorHex,
            imageFilename: nil
        )
    }

    static func image(
        page: Int,
        filename: String,
        normRect: CGRect = CGRect(x: 0.25, y: 0.35, width: 0.5, height: 0.32)
    ) -> NotePageOverlay {
        NotePageOverlay(
            id: UUID().uuidString,
            kind: .image,
            page: page,
            normX: normRect.minX,
            normY: normRect.minY,
            normW: normRect.width,
            normH: normRect.height,
            text: nil,
            fontSize: nil,
            colorHex: nil,
            imageFilename: filename
        )
    }

    static func shape(
        page: Int,
        shapeType: String,
        colorHex: String,
        normRect: CGRect = CGRect(x: 0.32, y: 0.38, width: 0.36, height: 0.36)
    ) -> NotePageOverlay {
        NotePageOverlay(
            id: UUID().uuidString,
            kind: .shape,
            page: page,
            normX: normRect.minX,
            normY: normRect.minY,
            normW: normRect.width,
            normH: normRect.height,
            colorHex: colorHex,
            shapeType: shapeType
        )
    }
}

/// Codable note record. Drawing bytes live separately on disk under
/// `Documents/notes/<id>/<pageIdx>.drawing` and are loaded lazily.
struct Note: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    /// The bubble the note belongs to. Single string, optional — JSX
    /// `note.subject` semantics (L23–L31). Empty / legacy reserved names
    /// are treated as `Untitled Bubble` at save time.
    var subject: String?
    /// Backend course linkage. New notes inherit these from their bubble.
    var courseId: String?
    var courseCode: String?
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
    /// Text + image stickers placed on top of the canvas. New in v2.1;
    /// older snapshots decode to `[]` thanks to the custom decoder below.
    var overlays: [NotePageOverlay] = []

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

    init(
        id: String,
        title: String,
        subject: String? = nil,
        courseId: String? = nil,
        courseCode: String? = nil,
        tag: String? = nil,
        sharedBy: String? = nil,
        pageCount: Int,
        createdAt: Date,
        updatedAt: Date,
        bookmarked: Bool = false,
        currentPage: Int = 1,
        pageSettings: [NotePageSetting] = [NotePageSetting()],
        overlays: [NotePageOverlay] = []
    ) {
        self.id = id
        self.title = title
        self.subject = subject
        self.courseId = courseId
        self.courseCode = courseCode
        self.tag = tag
        self.sharedBy = sharedBy
        self.pageCount = pageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bookmarked = bookmarked
        self.currentPage = currentPage
        self.pageSettings = pageSettings
        self.overlays = overlays
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subject, courseId, courseCode, tag, sharedBy, pageCount, createdAt, updatedAt,
             bookmarked, currentPage, pageSettings, overlays
    }

    /// Lenient decoder so notes persisted before `overlays` existed still
    /// load cleanly (they just come back with an empty array).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        courseId = try c.decodeIfPresent(String.self, forKey: .courseId)
        courseCode = try c.decodeIfPresent(String.self, forKey: .courseCode)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        sharedBy = try c.decodeIfPresent(String.self, forKey: .sharedBy)
        pageCount = try c.decode(Int.self, forKey: .pageCount)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        bookmarked = (try c.decodeIfPresent(Bool.self, forKey: .bookmarked)) ?? false
        currentPage = (try c.decodeIfPresent(Int.self, forKey: .currentPage)) ?? 1
        pageSettings = (try c.decodeIfPresent([NotePageSetting].self, forKey: .pageSettings))
            ?? Array(repeating: NotePageSetting(), count: max(1, pageCount))
        overlays = (try c.decodeIfPresent([NotePageOverlay].self, forKey: .overlays)) ?? []
    }
}

extension Note {
    /// Short label shown in the upper-right pill of library note cards
    /// (and any other place we need a one-glance "where does this note
    /// live" cue). Every note belongs to a bubble, so when one is set we
    /// surface its name — that's the source of truth for the note. Notes
    /// without a subject are shown as `Untitled Bubble`.
    var displayBadge: String? {
        if let trimmedSubject = subject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedSubject.isEmpty,
           !NotesStore.isLegacyOrphanSubject(trimmedSubject) {
            return trimmedSubject
        }
        return NotesStore.initialGuestBubbleName
    }
}

/// Persisted shape of the whole local store.
struct StoreSnapshot: Codable, Equatable {
    var bubbleNames: [String]
    var bubbles: [NoteBubble] = []
    var notes: [Note]
    /// Bumped by `LocalNotesPersistence` so we can migrate the JSON format
    /// later without nuking user data.
    var schemaVersion: Int

    /// v3 — adds structured bubble course metadata and note course fields.
    /// Older snapshots are loaded with the missing fields defaulted in
    /// `LocalNotesPersistence.loadStore`.
    static let currentSchemaVersion = 3
}

// MARK: - NotesStore

@MainActor
final class NotesStore: ObservableObject {

    // MARK: - Published state

    /// Bubble name list — equivalent to JSX `bubbleCategories` (L6912).
    /// Order is preserved so the home bubble field is stable across launches.
    @Published private(set) var bubbleNames: [String] = []
    @Published private(set) var bubbles: [NoteBubble] = []

    @Published private(set) var notes: [Note] = []

    /// Set when the user taps a bubble on Home. Read by `CourseSpaceView` on
    /// appear so the library opens pre-filtered. Mirrors JSX `activeSubject`
    /// (L6907 + `navigate(target, subject)` L6920–L6933).
    @Published var libraryFilter: String?

    /// True once `activate(userId:)` has resolved (snapshot loaded or
    /// confirmed empty). Views gate their content on this so we never
    /// flash a half-empty layout between sign-out and the next sign-in.
    @Published private(set) var isReady: Bool = false

    /// Whichever user the store is currently scoped to. `nil` between
    /// sign-out and the next `activate(userId:)`.
    @Published private(set) var activeUserId: String?

    // MARK: - Editor session state (open-note tabs)

    /// Ordered list of note IDs currently open in the editor's tab strip.
    /// Mirrors the JSX `openNotes` array (NotetakingPage L3533). In-memory
    /// only — sessions reset on sign-out and on app cold-launch.
    @Published private(set) var openNoteIds: [String] = []

    /// The tab the editor is currently focused on. `nil` when no editor
    /// session is active.
    @Published private(set) var activeOpenNoteId: String?

    // MARK: - Reserved names (match JSX L7002–L7004)

    /// Legacy virtual bucket labels — blocked as user-created bubble names
    /// and remapped to `initialGuestBubbleName` on load.
    nonisolated static let reservedBubbleNames: Set<String> = ["unnamed", "uncategorized"]

    /// Sentinel user id for Welcome → "Skip, set up later" browsing.
    nonisolated static let guestUserId = "guest"

    /// Default Home bubble. Every note without an explicit subject lands here.
    nonisolated static let initialGuestBubbleName = "Untitled Bubble"

    // MARK: - Dependencies

    private let persistence: LocalNotesPersistence

    // MARK: - Init

    /// Notes stay empty until `activate(userId:)` runs. `AppState.bootstrap`
    /// and `AppState.handleAuthResult` are responsible for that call.
    init(persistence: LocalNotesPersistence = .shared) {
        self.persistence = persistence
    }

    // MARK: - Per-user lifecycle

    /// Binds the store to `userId`. Loads the user's persisted bubble list
    /// and notes from disk (or starts empty for a brand-new account). Safe
    /// to call repeatedly with the same `userId` — that case is a no-op.
    func activate(userId: String) {
        if activeUserId == userId, isReady { return }
        // Clear first so previously-displayed notes from another user never
        // leak through even for a single frame while disk IO is in flight.
        bubbleNames = []
        bubbles = []
        notes = []
        libraryFilter = nil

        let snapshot = persistence.setActiveUser(userId)
        if let snapshot {
            bubbleNames = snapshot.bubbleNames
            bubbles = snapshot.bubbles.isEmpty
                ? snapshot.bubbleNames.map { NoteBubble(name: $0, courseCode: $0) }
                : snapshot.bubbles
            notes = snapshot.notes
            syncBubbleNamesFromBubbles()
            reconcileOrphanNotes()
        }
        activeUserId = userId
        isReady = true
    }

    /// Drops the store back to its pre-sign-in state. Files on disk stay
    /// in place under `Documents/users/<userId>/` so a returning user
    /// keeps their library.
    func deactivate() {
        persistence.clearActiveUser()
        bubbleNames = []
        bubbles = []
        notes = []
        libraryFilter = nil
        activeUserId = nil
        isReady = false
        clearOpenNotes()
    }

    // MARK: - Editor session lifecycle

    /// Adds `id` to the tab strip (if not already there) and marks it
    /// active. Tabs preserve insertion order so the JSX-style left-to-
    /// right strip stays stable across opens.
    func openNoteInEditor(_ id: String) {
        if !openNoteIds.contains(id) {
            openNoteIds.append(id)
        }
        activeOpenNoteId = id
    }

    /// Removes a tab. Returns the next note that should become active,
    /// or `nil` if that was the last tab (caller should pop the editor).
    @discardableResult
    func closeNoteTab(_ id: String) -> String? {
        guard let idx = openNoteIds.firstIndex(of: id) else {
            return activeOpenNoteId
        }
        openNoteIds.remove(at: idx)
        if openNoteIds.isEmpty {
            activeOpenNoteId = nil
            return nil
        }
        if activeOpenNoteId == id {
            // Prefer the neighbour to the left so the user's focus stays
            // close to where they were.
            let nextIdx = max(0, min(idx, openNoteIds.count - 1))
            activeOpenNoteId = openNoteIds[nextIdx]
        }
        return activeOpenNoteId
    }

    func setActiveOpenNote(_ id: String) {
        guard openNoteIds.contains(id) else { return }
        activeOpenNoteId = id
    }

    /// Creates a fresh draft and opens it in a new tab. Returns the new
    /// note so the caller (the editor's "+" button) can land on it.
    @discardableResult
    func openNewNoteTab(subject: String? = nil) -> Note {
        let note = createDraftNote(subject: subject)
        openNoteInEditor(note.id)
        return note
    }

    /// Clears every open tab. Called from `deactivate()` so a sign-out
    /// never leaves another user's note IDs in memory.
    func clearOpenNotes() {
        openNoteIds = []
        activeOpenNoteId = nil
    }

    private var snapshot: StoreSnapshot {
        StoreSnapshot(
            bubbleNames: bubbleNames,
            bubbles: bubbles,
            notes: notes,
            schemaVersion: StoreSnapshot.currentSchemaVersion
        )
    }

    private func saveDebounced() {
        persistence.scheduleSave(snapshot)
    }

    private func saveImmediately() {
        persistence.saveImmediately(snapshot)
    }

    /// Whether `userId` already has a persisted local library on disk.
    func hasPersistedSnapshot(forUserId userId: String) -> Bool {
        persistence.hasStore(for: userId)
    }

    /// Seeds the guest Home screen: one centred "Untitled Bubble", no notes.
    /// Used the first time someone taps Welcome → "Skip, set up later".
    func applyInitialGuestHome() {
        notes = []
        libraryFilter = nil
        clearOpenNotes()
        let bubble = NoteBubble(
            name: Self.initialGuestBubbleName,
            courseCode: Self.initialGuestBubbleName
        )
        bubbles = [bubble]
        bubbleNames = [Self.initialGuestBubbleName]
        saveImmediately()
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
        bubbles.append(NoteBubble(name: name, courseCode: name))
        syncBubbleNamesFromBubbles()
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

        bubbles = bubbles.map { bubble in
            guard bubble.name.caseInsensitiveCompare(currentName) == .orderedSame else { return bubble }
            var copy = bubble
            copy.name = nextName
            if copy.courseId == nil {
                copy.courseCode = nextName
            }
            return copy
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
        syncBubbleNamesFromBubbles()
        saveDebounced()
        return nil
    }

    /// Replaces the entire bubble list with `names`. Used by the
    /// post-onboarding course-setup step to seed Home in one shot —
    /// equivalent to the JSX `setBubbleCategories(nextBubbles)` call
    /// in `saveCourseList` (others/NoteWorks_UI 2/noteworks-library.jsx
    /// L9631). Trims, drops empties/reserved names, and de-duplicates
    /// case-insensitively while preserving the caller's order. Existing
    /// notes' `subject` strings are left untouched: course codes the
    /// user happened to already type as a subject keep working without
    /// any extra remap step.
    func replaceBubbleNames(_ names: [String]) {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let trimmed = NotesStore.normalizeBubbleName(raw)
            guard !trimmed.isEmpty,
                  !NotesStore.isReservedName(trimmed) else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        bubbles = result.map { name in
            bubble(named: name) ?? NoteBubble(name: name, courseCode: name)
        }
        if bubbles.isEmpty {
            bubbles = [
                NoteBubble(name: Self.initialGuestBubbleName, courseCode: Self.initialGuestBubbleName)
            ]
        }
        syncBubbleNamesFromBubbles()
        reconcileOrphanNotes()
        saveDebounced()
    }

    /// Removes a bubble and moves matching notes into `Untitled Bubble`.
    func deleteBubble(name: String) {
        guard name.caseInsensitiveCompare(Self.initialGuestBubbleName) != .orderedSame else { return }
        ensureUntitledBubbleListed()
        let fallback = Self.initialGuestBubbleName
        bubbles.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        syncBubbleNamesFromBubbles()
        for idx in notes.indices {
            if notes[idx].subject?.caseInsensitiveCompare(name) == .orderedSame {
                notes[idx].subject = fallback
                notes[idx].courseCode = notes[idx].courseCode ?? fallback
                notes[idx].updatedAt = Date()
            }
        }
        if libraryFilter?.caseInsensitiveCompare(name) == .orderedSame {
            libraryFilter = nil
        }
        saveDebounced()
    }

    /// Persists the user's manual position for a bubble (set during the
    /// Home edit-mode drag). Coordinates are fractional offsets from the
    /// container center; pass `nil`s via `clearBubbleManualOffset` to
    /// fall back to the auto slot layout.
    func setBubbleManualOffset(name: String, offsetX: Double, offsetY: Double) {
        guard let idx = bubbles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        bubbles[idx].manualOffsetX = offsetX
        bubbles[idx].manualOffsetY = offsetY
        saveDebounced()
    }

    /// Clears any manual position, returning the bubble to the auto
    /// slot it would have received from `HomeBubbleLayout`.
    func clearBubbleManualOffset(name: String) {
        guard let idx = bubbles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        guard bubbles[idx].manualOffsetX != nil || bubbles[idx].manualOffsetY != nil else { return }
        bubbles[idx].manualOffsetX = nil
        bubbles[idx].manualOffsetY = nil
        saveDebounced()
    }

    // MARK: - Note actions

    /// Mirrors JSX `createDraftNote` (L182–L194) — produces a fresh draft and
    /// inserts it at the top of the list. Returns the new note so callers can
    /// navigate straight into the editor.
    @discardableResult
    func createDraftNote(subject: String? = nil, title: String? = nil) -> Note {
        ensureUntitledBubbleListed()
        let now = Date()
        let resolvedSubject = Self.resolvedBubbleSubject(subject)
        let linkedBubble = bubble(named: resolvedSubject)
        let note = Note(
            id: UUID().uuidString,
            title: title ?? "Untitled Note",
            subject: resolvedSubject,
            courseId: linkedBubble?.courseId,
            courseCode: linkedBubble?.courseCode ?? resolvedSubject,
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
        case .clear:
            ensureUntitledBubbleListed()
            let fallback = Self.initialGuestBubbleName
            notes[idx].subject = fallback
            if let linkedBubble = bubble(named: fallback) {
                notes[idx].courseId = linkedBubble.courseId
                notes[idx].courseCode = linkedBubble.courseCode ?? fallback
            } else {
                notes[idx].courseCode = fallback
            }
        case .set(let value):
            let resolved = Self.resolvedBubbleSubject(value)
            notes[idx].subject = resolved
            if let linkedBubble = bubble(named: resolved) {
                notes[idx].courseId = linkedBubble.courseId
                notes[idx].courseCode = linkedBubble.courseCode ?? resolved
            }
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
        // Overlays: shift every page ≥ clamped+1 up by one, then clone
        // the source page's overlays into the new slot. New ids so the
        // copies are independently editable.
        for oIdx in notes[idx].overlays.indices where notes[idx].overlays[oIdx].page > clamped {
            notes[idx].overlays[oIdx].page += 1
        }
        let cloned = notes[idx].overlays
            .filter { $0.page == clamped }
            .map { src -> NotePageOverlay in
                var copy = src
                copy = src.duplicate(offsetNorm: .zero)
                copy.page = clamped + 1
                return copy
            }
        notes[idx].overlays.append(contentsOf: cloned)
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
        let deletedBackgroundImage = notes[idx].pageSettings[clamped - 1].backgroundImageFilename
        notes[idx].pageSettings.remove(at: clamped - 1)
        notes[idx].pageCount = notes[idx].pageSettings.count
        notes[idx].currentPage = min(clamped, notes[idx].pageSettings.count)
        notes[idx].updatedAt = Date()
        // Overlays: drop everything on the deleted page (and delete its
        // image files), then shift pages above it down by one.
        let doomed = notes[idx].overlays.filter { $0.page == clamped }
        notes[idx].overlays.removeAll { $0.page == clamped }
        for oIdx in notes[idx].overlays.indices where notes[idx].overlays[oIdx].page > clamped {
            notes[idx].overlays[oIdx].page -= 1
        }
        for overlay in doomed {
            if let filename = overlay.imageFilename {
                persistence.deleteOverlayImage(for: noteId, filename: filename)
            }
        }
        if let deletedBackgroundImage {
            persistence.deleteOverlayImage(for: noteId, filename: deletedBackgroundImage)
        }
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

    /// Sets an absolute rotation on one or more pages (Page Thumbnails select
    /// mode). Mirrors JSX `handleRotatePages`.
    func rotatePages(noteId: String, pages: [Int], to rotation: Int) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let selected = Set(pages)
        guard !selected.isEmpty else { return }
        let normalized = ((rotation % 360) + 360) % 360
        for pageIndex in notes[idx].pageSettings.indices where selected.contains(pageIndex + 1) {
            notes[idx].pageSettings[pageIndex].rotation = normalized
        }
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    /// Moves a page from one position to another (1-based). Mirrors JSX
    /// `handleReorderPages`.
    @discardableResult
    func reorderPages(noteId: String, fromPage: Int, toPage: Int) -> Int? {
        guard fromPage != toPage,
              fromPage >= 1, toPage >= 1,
              let idx = notes.firstIndex(where: { $0.id == noteId }) else { return nil }
        let total = notes[idx].pageSettings.count
        guard fromPage <= total, toPage <= total else { return nil }

        var order = Array(1...total)
        guard let fromIndex = order.firstIndex(of: fromPage),
              let toIndex = order.firstIndex(of: toPage) else { return nil }
        let moved = order.remove(at: fromIndex)
        order.insert(moved, at: toIndex)

        var oldToNewPage: [Int: Int] = [:]
        for (newIndex, oldPage) in order.enumerated() {
            oldToNewPage[oldPage] = newIndex + 1
        }

        let nextSettings = order.map { notes[idx].pageSettings[$0 - 1] }
        notes[idx].pageSettings = nextSettings
        notes[idx].pageCount = nextSettings.count
        notes[idx].currentPage = oldToNewPage[notes[idx].currentPage] ?? notes[idx].currentPage
        notes[idx].updatedAt = Date()

        var drawingMap: [Int: Int] = [:]
        for (newIndex, oldPage) in order.enumerated() {
            drawingMap[oldPage - 1] = newIndex
        }
        persistence.remapDrawings(for: noteId, oldZeroToNewZero: drawingMap)

        for overlayIndex in notes[idx].overlays.indices {
            let oldPage = notes[idx].overlays[overlayIndex].page
            if let mapped = oldToNewPage[oldPage] {
                notes[idx].overlays[overlayIndex].page = mapped
            }
        }

        saveDebounced()
        return notes[idx].currentPage
    }

    /// Deletes one or more pages from a note. If every page would be removed,
    /// leaves a single blank page (mirrors JSX `handleDeleteSelectedPages`).
    @discardableResult
    func deletePages(noteId: String, pages: [Int]) -> String? {
        let selected = Set(pages)
        guard !selected.isEmpty else { return nil }
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else {
            return "Note not found."
        }

        var oldToNewPage: [Int: Int] = [:]
        var keptSettings: [NotePageSetting] = []
        for (index, setting) in notes[idx].pageSettings.enumerated() {
            let oldPage = index + 1
            if selected.contains(oldPage) { continue }
            oldToNewPage[oldPage] = keptSettings.count + 1
            keptSettings.append(setting)
        }

        let allDeleted = keptSettings.isEmpty
        let nextSettings = allDeleted ? [NotePageSetting()] : keptSettings
        let previousCurrent = notes[idx].currentPage

        var drawingMap: [Int: Int] = [:]
        for (oldPage, newPage) in oldToNewPage {
            drawingMap[oldPage - 1] = newPage - 1
        }

        for (index, setting) in notes[idx].pageSettings.enumerated() where selected.contains(index + 1) {
            if let filename = setting.backgroundImageFilename {
                persistence.deleteOverlayImage(for: noteId, filename: filename)
            }
        }

        let doomedOverlays = notes[idx].overlays.filter { selected.contains($0.page) }
        notes[idx].overlays.removeAll { selected.contains($0.page) }
        for overlay in doomedOverlays {
            if let filename = overlay.imageFilename {
                persistence.deleteOverlayImage(for: noteId, filename: filename)
            }
        }
        for overlayIndex in notes[idx].overlays.indices {
            let oldPage = notes[idx].overlays[overlayIndex].page
            if let mapped = oldToNewPage[oldPage] {
                notes[idx].overlays[overlayIndex].page = mapped
            }
        }

        notes[idx].pageSettings = nextSettings
        notes[idx].pageCount = nextSettings.count
        if let mappedCurrent = oldToNewPage[previousCurrent] {
            notes[idx].currentPage = mappedCurrent
        } else if allDeleted {
            notes[idx].currentPage = 1
        } else {
            let deletedBefore = pages.filter { $0 < previousCurrent }.count
            notes[idx].currentPage = min(
                nextSettings.count,
                max(1, previousCurrent - deletedBefore)
            )
        }
        notes[idx].updatedAt = Date()

        persistence.remapDrawings(for: noteId, oldZeroToNewZero: drawingMap)
        saveDebounced()
        return nil
    }

    func setBackground(noteId: String, background: NotePageBackground) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let page = notes[idx].currentPage
        let clamped = max(1, min(page, notes[idx].pageSettings.count))
        notes[idx].pageSettings[clamped - 1].background = background
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    func setPageBackgroundImage(noteId: String, page: Int, filename: String, aspectHeightOverWidth: CGFloat) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let clamped = max(1, min(page, notes[idx].pageSettings.count))
        notes[idx].pageSettings[clamped - 1].backgroundImageFilename = filename
        notes[idx].pageSettings[clamped - 1].aspectHeightOverWidth = max(0.2, min(5.0, aspectHeightOverWidth))
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

    // MARK: - Page overlay IO (text + image stickers)

    /// Returns overlays attached to one page of one note (1-based page).
    func overlays(for noteId: String, page: Int) -> [NotePageOverlay] {
        guard let note = notes.first(where: { $0.id == noteId }) else { return [] }
        return note.overlays.filter { $0.page == page }
    }

    /// Appends a new overlay onto a note.
    func addOverlay(_ overlay: NotePageOverlay, to noteId: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[idx].overlays.append(overlay)
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    /// Replaces an existing overlay by id. No-op if the note/overlay
    /// doesn't exist (e.g. user closed the tab mid-drag).
    func updateOverlay(_ overlay: NotePageOverlay, in noteId: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }),
              let oidx = notes[idx].overlays.firstIndex(where: { $0.id == overlay.id })
        else { return }
        notes[idx].overlays[oidx] = overlay
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    /// Duplicates an overlay. Image overlays get a fresh copy of the PNG.
    @discardableResult
    func duplicateOverlay(_ overlay: NotePageOverlay, in noteId: String) -> NotePageOverlay? {
        var copy = overlay.duplicate()
        if overlay.kind == .image,
           let filename = overlay.imageFilename,
           let data = loadOverlayImageData(for: noteId, filename: filename) {
            let newFilename = "\(UUID().uuidString).png"
            saveOverlayImageData(data, for: noteId, filename: newFilename)
            copy.imageFilename = newFilename
        }
        addOverlay(copy, to: noteId)
        return copy
    }

    /// Removes an overlay by id. If the overlay was an image, deletes
    /// the backing PNG file too.
    func removeOverlay(id overlayId: String, from noteId: String) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let removed = notes[idx].overlays.first(where: { $0.id == overlayId })
        notes[idx].overlays.removeAll { $0.id == overlayId }
        notes[idx].updatedAt = Date()
        saveDebounced()
        if let filename = removed?.imageFilename {
            persistence.deleteOverlayImage(for: noteId, filename: filename)
        }
    }

    // MARK: - Overlay image data (delegate to persistence layer)

    func loadOverlayImageData(for noteId: String, filename: String) -> Data? {
        persistence.loadOverlayImage(for: noteId, filename: filename)
    }

    func saveOverlayImageData(_ data: Data, for noteId: String, filename: String) {
        persistence.saveOverlayImage(data, for: noteId, filename: filename)
    }

    // MARK: - Lookups for the UI

    /// Live note count for a bubble. Orphan notes (nil / legacy reserved
    /// names) roll up into `Untitled Bubble`.
    func noteCount(for bubbleName: String) -> Int {
        if bubbleName.caseInsensitiveCompare(Self.initialGuestBubbleName) == .orderedSame {
            return notes.filter { note in
                Self.resolvedBubbleSubject(note.subject) == Self.initialGuestBubbleName
            }.count
        }
        return notes.filter {
            $0.subject?.caseInsensitiveCompare(bubbleName) == .orderedSame
        }.count
    }

    // MARK: - Helpers

    /// Ensures the default `Untitled Bubble` exists when the store has no
    /// bubbles at all (guest home / brand-new account).
    func seedDefaultBubbleIfEmpty() {
        guard bubbles.isEmpty else { return }
        bubbles = [
            NoteBubble(name: Self.initialGuestBubbleName, courseCode: Self.initialGuestBubbleName)
        ]
        syncBubbleNamesFromBubbles()
    }

    /// Adds `Untitled Bubble` to the bubble list when notes need a home for
    /// orphan / default filing. Does not inject it onto course-only Home
    /// screens until a note actually lands there.
    func ensureUntitledBubbleListed() {
        if bubbles.isEmpty {
            seedDefaultBubbleIfEmpty()
            return
        }
        if !bubbles.contains(where: {
            $0.name.caseInsensitiveCompare(Self.initialGuestBubbleName) == .orderedSame
        }) {
            bubbles.append(
                NoteBubble(name: Self.initialGuestBubbleName, courseCode: Self.initialGuestBubbleName)
            )
            syncBubbleNamesFromBubbles()
        }
    }

    /// Rewrites legacy orphan subjects to `Untitled Bubble` after load.
    private func reconcileOrphanNotes() {
        let fallback = Self.initialGuestBubbleName
        var changed = false
        var needsUntitledBubble = false
        for idx in notes.indices {
            let resolved = Self.resolvedBubbleSubject(notes[idx].subject)
            if resolved.caseInsensitiveCompare(fallback) == .orderedSame {
                needsUntitledBubble = true
            }
            if notes[idx].subject?.caseInsensitiveCompare(resolved) != .orderedSame {
                notes[idx].subject = resolved
                notes[idx].courseCode = notes[idx].courseCode ?? fallback
                notes[idx].updatedAt = Date()
                changed = true
            }
        }
        if needsUntitledBubble {
            ensureUntitledBubbleListed()
        } else {
            seedDefaultBubbleIfEmpty()
        }
        if changed { saveDebounced() }
    }

    /// Maps nil, empty, or legacy virtual bucket names to the default bubble.
    nonisolated static func resolvedBubbleSubject(_ subject: String?) -> String {
        let trimmed = normalizeBubbleName(subject ?? "")
        if trimmed.isEmpty || isLegacyOrphanSubject(trimmed) {
            return initialGuestBubbleName
        }
        return trimmed
    }

    nonisolated static func isLegacyOrphanSubject(_ subject: String) -> Bool {
        isReservedName(subject)
    }

    private func bubbleNameTaken(_ name: String, excluding current: String? = nil) -> Bool {
        bubbleNames.contains { existing in
            if let current, existing.caseInsensitiveCompare(current) == .orderedSame {
                return false
            }
            return existing.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func bubble(named name: String?) -> NoteBubble? {
        guard let name else { return nil }
        return bubbles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func setCourseMetadata(forBubbleNamed name: String, courseId: String, courseCode: String?) {
        let normalized = NotesStore.normalizeBubbleName(name)
        guard !normalized.isEmpty else { return }
        if let idx = bubbles.firstIndex(where: { $0.name.caseInsensitiveCompare(normalized) == .orderedSame }) {
            bubbles[idx].courseId = courseId
            bubbles[idx].courseCode = courseCode ?? bubbles[idx].courseCode ?? normalized
        } else {
            bubbles.append(NoteBubble(name: normalized, courseId: courseId, courseCode: courseCode ?? normalized))
        }
        for idx in notes.indices where notes[idx].subject?.caseInsensitiveCompare(normalized) == .orderedSame {
            notes[idx].courseId = courseId
            notes[idx].courseCode = courseCode ?? notes[idx].courseCode ?? normalized
            notes[idx].updatedAt = Date()
        }
        syncBubbleNamesFromBubbles()
        saveDebounced()
    }

    func setCourseMetadata(forNoteId noteId: String, courseId: String, courseCode: String?) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[idx].courseId = courseId
        notes[idx].courseCode = courseCode ?? notes[idx].courseCode
        notes[idx].updatedAt = Date()
        saveDebounced()
    }

    private func syncBubbleNamesFromBubbles() {
        bubbleNames = bubbles.map(\.name)
    }

    nonisolated static func normalizeBubbleName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pure check against a constant set — safe to call from any actor
    /// context (e.g. `Note.displayBadge`, background validation), so it
    /// opts out of `NotesStore`'s `@MainActor` isolation.
    nonisolated static func isReservedName(_ name: String) -> Bool {
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
            seedNote(title: "Grammer Rules", subject: NotesStore.initialGuestBubbleName, tag: "Course", sharedBy: "Sam", pageCount: 11, createdAt: date(daysAgo: 13)),
            seedNote(title: "Perspective Drawing", subject: "Art", tag: nil, sharedBy: nil, pageCount: 6, createdAt: date(daysAgo: 15)),
            seedNote(title: "Physics Lab 3", subject: "Physics", tag: nil, sharedBy: nil, pageCount: 4, createdAt: date(daysAgo: 18)),
            seedNote(title: "Calc II Notes", subject: "Mathematics", tag: "Course", sharedBy: nil, pageCount: 12, createdAt: date(daysAgo: 21)),
            seedNote(title: "Calc III Review", subject: "Mathematics", tag: nil, sharedBy: nil, pageCount: 8, createdAt: date(daysAgo: 23)),
        ]
        let bubbleNames = ["Biology", "Art", "Physics", "Chemistry", "Mathematics"]

        return StoreSnapshot(
            bubbleNames: bubbleNames,
            bubbles: bubbleNames.map { NoteBubble(name: $0, courseCode: $0) },
            notes: notes,
            schemaVersion: StoreSnapshot.currentSchemaVersion
        )
    }
}

// MARK: - Preview helper

extension NotesStore {
    /// Activates a fixed "preview-user" so SwiftUI #Preview blocks see a
    /// fully-ready store with realistic content. Hydrates from the
    /// `firstRunSeed` in memory (without writing to disk) when the
    /// preview user has no persisted snapshot yet, so the canvas pages
    /// in the previews are always populated.
    @MainActor
    static func preview() -> NotesStore {
        let store = NotesStore()
        store.activate(userId: "preview-user")
        if store.notes.isEmpty && store.bubbleNames.isEmpty {
            let seed = NotesStore.firstRunSeed()
            store.bubbleNames = seed.bubbleNames
            store.bubbles = seed.bubbles
            store.notes = seed.notes
        }
        return store
    }
}
