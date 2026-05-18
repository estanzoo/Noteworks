//
//  NoteEditorViewModel.swift
//  Noteworks
//
//  Drives the canvas chrome, custom toolbar, and per-page drawing IO.
//
//  Per-page model: `currentPage` is 1-based, like the JSX. Switching pages
//  flushes the live `PKDrawing` to disk for the previous page, then loads
//  (or seeds) the new page's drawing. The Supabase PDF upload/download flow
//  is preserved unchanged — it is orthogonal to local persistence.
//

import Foundation
import PencilKit
import Combine
import SwiftUI
import UIKit

// MARK: - Tool state

/// Active editor tool. Mirrors the JSX `activeTool` enum (L2411). The
/// four PencilKit-backed tools (`pen` / `highlighter` / `eraser` /
/// `lasso`) actually drive the canvas; `shape` / `text` / `image` are
/// rendered in the toolbar so the chrome matches the JSX visually but
/// flash a "coming soon" status when tapped (no PencilKit primitive,
/// would require overlay layers we deferred for v1).
enum NoteEditorTool: String, Equatable {
    case pen
    case highlighter
    case eraser
    case lasso
    case shape
    case text
    case image

    /// True for tools that have a working UI in this build. `text` and
    /// `image` are implemented via the `NoteOverlayLayer` rendered above
    /// the PKCanvas (PencilKit can't host either natively). `shape` is
    /// still a stub for v1.
    var isImplemented: Bool {
        switch self {
        case .pen, .highlighter, .eraser, .lasso, .text, .image, .shape: return true
        }
    }

    /// Tools that drive PencilKit ink. While a non-drawing tool is
    /// active the editor disables `PKCanvasView` hit-testing so finger
    /// drags go to the overlay layer (text/image) instead of leaving
    /// stray strokes on the page.
    var canDraw: Bool {
        switch self {
        case .pen, .highlighter, .eraser, .lasso: return true
        case .text, .image, .shape: return false
        }
    }
}

/// Eraser sub-mode — JSX L2418. Object eraser deletes whole strokes,
/// regular eraser rubs out pixels along the path.
enum NoteEraserMode: String, Equatable {
    case regular
    case object
}

/// Shape primitive offered by the Shape tool dropdown. Mirrors
/// `shapeOptions` in noteworks-library.jsx — these are picked from the
/// tool panel but the actual canvas insertion is a v2 feature.
enum NoteShapeType: String, Equatable, CaseIterable, Identifiable {
    case rectangle
    case circle
    case arrow
    case line

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle:    return "Circle"
        case .arrow:     return "Arrow"
        case .line:      return "Line"
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle:    return "circle"
        case .arrow:     return "arrow.up.right"
        case .line:      return "minus"
        }
    }
}

/// Font family offered by the Text tool dropdown. Mirrors JSX
/// `fontOptions` (SF Pro / Georgia / Marker).
enum NoteTextFont: String, Equatable, CaseIterable, Identifiable {
    case sf
    case serif
    case marker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sf:     return "SF Pro"
        case .serif:  return "Georgia"
        case .marker: return "Marker"
        }
    }

    /// SwiftUI font matching this family at the requested size. Marker
    /// has no system equivalent on iOS; rounded reads as a friendly
    /// hand-drawn substitute.
    func displayFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        switch self {
        case .sf:     return .system(size: size, weight: weight, design: .default)
        case .serif:  return .system(size: size, weight: weight, design: .serif)
        case .marker: return .system(size: size, weight: weight, design: .rounded)
        }
    }
}

/// Brush "feel" exposed under the Pen tool. Maps to a PencilKit
/// `PKInkingTool.InkType` plus a label for the dropdown. We deliberately
/// expose four daily-writing brushes — Pen, Pencil, Fountain Pen,
/// Monoline — and leave the artistic brushes (watercolor, crayon) out for
/// now; those belong behind a separate Coloring tool when we add one.
enum NotePenBrush: String, Equatable, CaseIterable, Identifiable {
    case pen
    case pencil
    case fountainPen
    case monoline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen:         return "Pen"
        case .pencil:      return "Pencil"
        case .fountainPen: return "Fountain"
        case .monoline:    return "Monoline"
        }
    }

    /// SF Symbol that visually communicates the brush feel. All four are
    /// available from iOS 16; we don't depend on iOS 17 here so the
    /// monoline tile keeps rendering on older OSes (the underlying
    /// PencilKit type falls back to `.pen` there).
    var symbol: String {
        switch self {
        case .pen:         return "pencil.tip"
        case .pencil:      return "pencil"
        case .fountainPen: return "pencil.and.outline"
        case .monoline:    return "line.diagonal"
        }
    }

    /// PencilKit ink type. `.monoline` and `.fountainPen` only exist on
    /// iOS 17+; we degrade gracefully to `.pen` on earlier OSes so the
    /// brush selection survives but renders as a plain pen until the
    /// device updates.
    var pkInkType: PKInkingTool.InkType {
        switch self {
        case .pen:    return .pen
        case .pencil: return .pencil
        case .fountainPen:
            if #available(iOS 17.0, *) { return .fountainPen }
            return .pen
        case .monoline:
            if #available(iOS 17.0, *) { return .monoline }
            return .pen
        }
    }
}

// MARK: - AI Enhancements

/// State of a single AI enhancement job. Both Gap Detection and Smart
/// Organization share this shape; the view model holds one of each.
enum AIEnhancementJob: Equatable {
    case idle
    case running(progress: Double)
    case completed

    var progress: Double {
        switch self {
        case .running(let value): return value
        case .completed: return 1.0
        case .idle: return 0.0
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

/// Sub-panel currently rendered inside the AI Enhancements dropdown.
/// Mirrors the `aiEnhancementPanel` string union in the reference JSX
/// (`root` / `task-status` / `smart-confirm` / `smart-organization`).
enum AIEnhancementPanel: Equatable {
    case root
    case taskStatus
    case smartConfirm
    case smartOrganization
}

enum GapDetectionMode: Equatable {
    case config
    case running
    case completed
}

enum GapDetectionConfigPanel: Equatable {
    case root
    case communityBrowser
    case preview
}

enum GapDetectionOutputMode: String, Equatable, CaseIterable, Identifiable {
    case newNote
    case appendPages

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newNote: return "Make it as a new note"
        case .appendPages: return "Attach to current note"
        }
    }
}

/// One swatch in the canvas color palette. Mirrors the JSX `palette`
/// (L2489) without the custom hex slot — that's tracked separately as
/// `customColor` so the user can pick anything.
struct NoteColorSwatch: Identifiable, Equatable {
    let id: String
    let label: String
    let color: Color
}

extension NoteColorSwatch {
    /// Full palette — black/graphite/red/blue/green for the pen, plus the
    /// bright pastel set the highlighter actually wants. The JSX names are
    /// preserved where they existed so existing status strings still line
    /// up; new entries fill the gaps you expect from a real notes app
    /// (black/red/blue were noticeably missing).
    static let palette: [NoteColorSwatch] = [
        NoteColorSwatch(id: "black",    label: "Black",    color: Color(red: 0x18/255, green: 0x18/255, blue: 0x1F/255)),
        NoteColorSwatch(id: "graphite", label: "Graphite", color: Color(red: 0x4D/255, green: 0x4D/255, blue: 0x52/255)),
        NoteColorSwatch(id: "charcoal", label: "Charcoal", color: Color(red: 0x6B/255, green: 0x74/255, blue: 0x81/255)),
        NoteColorSwatch(id: "red",      label: "Red",      color: Color(red: 0xE5/255, green: 0x3E/255, blue: 0x3E/255)),
        NoteColorSwatch(id: "blue",     label: "Blue",     color: Color(red: 0x3E/255, green: 0x7A/255, blue: 0xE5/255)),
        NoteColorSwatch(id: "green",    label: "Green",    color: Color(red: 0x2E/255, green: 0xA5/255, blue: 0x5B/255)),
        NoteColorSwatch(id: "yellow",   label: "Yellow",   color: Color(red: 0xFF/255, green: 0xF3/255, blue: 0x6D/255)),
        NoteColorSwatch(id: "lime",     label: "Lime",     color: Color(red: 0x6D/255, green: 0xEB/255, blue: 0x73/255)),
        NoteColorSwatch(id: "cyan",     label: "Cyan",     color: Color(red: 0x78/255, green: 0xE6/255, blue: 0xF1/255)),
        NoteColorSwatch(id: "pink",     label: "Pink",     color: Color(red: 0xF7/255, green: 0x95/255, blue: 0xC0/255)),
    ]

    /// Pen ink row in the tool dropdown — six swatches on one line,
    /// matching NoteWorks_UI 3.
    static let penInkPalette: [NoteColorSwatch] = [
        palette.first { $0.id == "graphite" }!,
        palette.first { $0.id == "charcoal" }!,
        palette.first { $0.id == "yellow"  }!,
        palette.first { $0.id == "lime"    }!,
        palette.first { $0.id == "cyan"    }!,
        palette.first { $0.id == "pink"    }!,
    ]

    /// Full pen palette for any code that still needs every writing color.
    static let penPalette: [NoteColorSwatch] = palette

    /// Highlighter palette — the four bright pastels from the original
    /// JSX set. Black/red as a highlighter looks bad, so we narrow the
    /// dropdown to colors that read well as a translucent marker.
    static let highlighterPalette: [NoteColorSwatch] = [
        palette.first { $0.id == "yellow" }!,
        palette.first { $0.id == "lime"   }!,
        palette.first { $0.id == "cyan"   }!,
        palette.first { $0.id == "pink"   }!,
    ]

    static func swatch(named id: String) -> NoteColorSwatch? {
        palette.first { $0.id == id }
    }
}

// MARK: - View model

@MainActor
final class NoteEditorViewModel: ObservableObject {

    // MARK: - Canvas state

    /// The drawing currently bound to the canvas. Bound to
    /// `PencilCanvasView` so PKCanvasView pushes strokes here and we push
    /// page swaps back into PKCanvasView.
    @Published var drawing = PKDrawing()
    @Published var noteTitle = "Untitled Note"
    @Published var subject: String?

    // MARK: - Page state

    /// 1-based page index, mirroring the JSX `currentPage`.
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 1
    @Published var currentPageBackground: NotePageBackground = .blank
    @Published var currentPageRotation: Int = 0
    @Published var currentPageBackgroundImageFilename: String?
    @Published var currentPageAspectHeightOverWidth: CGFloat = 1.4
    @Published var bookmarked: Bool = false

    // MARK: - Tool state

    @Published var activeTool: NoteEditorTool = .pen

    // Pen
    @Published var penBrush: NotePenBrush = .pen
    @Published var penSwatchId: String = "black"
    @Published var penCustomColor: Color = Color(red: 0x6E/255, green: 0x8B/255, blue: 0xFF/255)
    @Published var penUsesCustomColor: Bool = false
    /// Pen thickness in roughly-mm-feeling units. Range 2…12 (JSX L2417).
    @Published var penThickness: CGFloat = 6

    // Highlighter
    @Published var highlighterSwatchId: String = "yellow"
    @Published var highlighterCustomColor: Color = Color(red: 0xFF/255, green: 0xCD/255, blue: 0x4D/255)
    @Published var highlighterUsesCustomColor: Bool = false

    // Eraser
    @Published var eraserMode: NoteEraserMode = .regular
    /// Range 10…34 px (JSX L2419).
    @Published var eraserSize: CGFloat = 18
    /// First-tap arms the "Clear page" button red, second tap actually
    /// fires (mirrors JSX `clearPageArmed` L2454).
    @Published var clearPageArmed: Bool = false

    // Shape
    @Published var shapeType: NoteShapeType = .rectangle
    @Published var shapeSwatchId: String = "black"
    @Published var shapeCustomColor: Color = Color(red: 0x6E/255, green: 0x8B/255, blue: 0xFF/255)
    @Published var shapeUsesCustomColor: Bool = false

    // Text overlay defaults — picked from the Text tool dropdown and
    // applied to fresh text overlays inserted onto the canvas (the user
    // edits the actual string inline on the page, no popup sheet).
    @Published var textFont: NoteTextFont = .sf
    /// Default font size (14…44 pt) the editor sheet starts with.
    @Published var textSize: CGFloat = 20
    @Published var textSwatchId: String = "black"
    @Published var textCustomColor: Color = Color(red: 0x6E/255, green: 0x8B/255, blue: 0xFF/255)
    @Published var textUsesCustomColor: Bool = false

    // MARK: - AI Enhancements

    /// Two parallel jobs the user can trigger from the AI Enhancements
    /// dropdown — mirrors the JSX `activeGapIndicatorJob` /
    /// `smartOrganizationState` pair at noteworks-library.jsx L5117.
    @Published var gapJob: AIEnhancementJob = .idle
    @Published var smartJob: AIEnhancementJob = .idle
    @Published var aiEnhancementPanel: AIEnhancementPanel = .root
    @Published var aiEnhancementNotice: String = ""
    @Published var showGapDetectionPopup: Bool = false
    @Published var gapDetectionMode: GapDetectionMode = .config
    @Published var gapDetectionConfigPanel: GapDetectionConfigPanel = .root
    /// Panel to return to when leaving the peer-note preview (root vs community browser).
    @Published var gapPreviewReturnPanel: GapDetectionConfigPanel = .root
    @Published var gapOutputMode: GapDetectionOutputMode = .newNote
    @Published var gapSelectedOwnNoteId: String?
    @Published var gapOwnNotePickerOpen: Bool = false
    @Published var gapPreviewNoteId: String?
    @Published var selectedGapSourceIds: Set<String> = []
    @Published var gapClassMaterialNames: [String] = []
    @Published var gapMaterialNotice: String = ""
    @Published var gapDetectionError: String?
    @Published var gapDetectionResponse: GapDetectionResponse?
    @Published var gapResultNoteId: String?
    @Published var gapResultPage: Int?

    private var gapJobTask: Task<Void, Never>?
    private var smartJobTask: Task<Void, Never>?
    private let gapDetectionService: GapDetectionServiceProtocol
    private static let aiBusyMessage = "Another AI enhancement is already running. Please wait for it to finish first."

    // MARK: - Overlay-action signals

    /// One-shot trigger consumed by `NoteEditorView` to open the text
    /// editor sheet. Bumping the int re-fires the action even if the
    /// user taps the text button twice in a row.
    @Published var pendingTextInsertNonce: Int = 0
    /// One-shot trigger to open the photo picker.
    @Published var pendingImagePickNonce: Int = 0

    // MARK: - Status text

    /// Bottom-left status strip. Updates on every interaction (JSX
    /// `setStatusText`). Auto-clears to "Synced just now" after a short
    /// idle window so the strip never stays stale forever.
    @Published var statusText: String = "Synced just now"
    private var statusTextResetTask: Task<Void, Never>?

    /// One-shot pulse that drives the centered "New page" indicator
    /// overlay (mirrors the JSX `newPageFlash` / `.new-page-indicator`).
    /// Flips to `true` right after a new page is created and clears itself
    /// shortly after so the indicator fades back out.
    @Published var showNewPageFlash: Bool = false
    private var newPageFlashTask: Task<Void, Never>?

    // MARK: - Upload state (preserved from previous version)

    @Published var isUploading = false
    @Published var uploadError: String?
    @Published var lastUploadedAt: Date?

    @Published var isDownloading = false
    @Published var downloadedPDFData: Data?
    @Published var downloadError: String?

    // MARK: - Dependencies

    private let pdfService = PDFStorageService.shared

    /// The note ID this editor is operating on.
    var noteId: String?

    private weak var store: NotesStore?
    private var hasLoaded = false
    /// First drawing assignment after `attach` is the persisted one — we
    /// don't want to re-write what we just read.
    private var skipNextDrawingPersist = false
    private var saveDrawingTask: Task<Void, Never>?
    /// Generation counter incremented every time we deliberately swap the
    /// active page. The drawing-change handler checks the current
    /// generation against the value captured when it was scheduled and
    /// drops stale persists, so a fast page flip never writes one page's
    /// strokes onto the next page's file.
    private var drawingGeneration: Int = 0
    private var cancellables = Set<AnyCancellable>()
    /// Last pen / highlighter / lasso — used when leaving eraser via Apple Pencil double-tap.
    private var lastInkToolForPencil: NoteEditorTool = .pen
    /// Tool before the current one — matches Settings "switch to last used tool".
    private var previousToolForPencil: NoteEditorTool = .pen

    // MARK: - Derived

    var penColor: Color {
        if penUsesCustomColor { return penCustomColor }
        return NoteColorSwatch.swatch(named: penSwatchId)?.color
            ?? NoteColorSwatch.swatch(named: "black")?.color
            ?? .black
    }

    var penColorLabel: String {
        if penUsesCustomColor { return "Custom" }
        return NoteColorSwatch.swatch(named: penSwatchId)?.label ?? "Black"
    }

    /// Stroke width label shown in the pen dropdown (e.g. "0.6 mm").
    var penThicknessLabel: String {
        String(format: "%.1f mm", Double(penThickness) / 10)
    }

    var highlighterColor: Color {
        if highlighterUsesCustomColor { return highlighterCustomColor }
        return NoteColorSwatch.swatch(named: highlighterSwatchId)?.color
            ?? NoteColorSwatch.swatch(named: "yellow")?.color
            ?? .yellow
    }

    var highlighterColorLabel: String {
        if highlighterUsesCustomColor { return "Custom" }
        return NoteColorSwatch.swatch(named: highlighterSwatchId)?.label ?? "Yellow"
    }

    var shapeColor: Color {
        if shapeUsesCustomColor { return shapeCustomColor }
        return NoteColorSwatch.swatch(named: shapeSwatchId)?.color
            ?? NoteColorSwatch.swatch(named: "black")?.color
            ?? .black
    }

    var shapeColorLabel: String {
        if shapeUsesCustomColor { return "Custom" }
        return NoteColorSwatch.swatch(named: shapeSwatchId)?.label ?? "Black"
    }

    var textColor: Color {
        if textUsesCustomColor { return textCustomColor }
        return NoteColorSwatch.swatch(named: textSwatchId)?.color
            ?? NoteColorSwatch.swatch(named: "black")?.color
            ?? .black
    }

    var textColorLabel: String {
        if textUsesCustomColor { return "Custom" }
        return NoteColorSwatch.swatch(named: textSwatchId)?.label ?? "Black"
    }

    /// Tool object the canvas should use right now. Recomputed every time
    /// any tool config field changes; the view passes this into
    /// `PencilCanvasView` so the underlying `PKCanvasView.tool` updates.
    var pkTool: PKTool {
        switch activeTool {
        case .pen:
            return PKInkingTool(penBrush.pkInkType, color: UIColor(penColor), width: penThickness)
        case .highlighter:
            // Marker stroke widens as it's drawn — match the JSX feel by
            // doubling the pen thickness so it visibly highlights text.
            return PKInkingTool(.marker, color: UIColor(highlighterColor), width: penThickness * 2)
        case .eraser:
            // Object mode wipes whole strokes, vector mode erases by mask.
            // PKEraserTool maps these naturally: `.bitmap` for pixel-based
            // (regular) and `.vector` for stroke-based (object).
            return PKEraserTool(eraserMode == .object ? .vector : .bitmap, width: eraserSize)
        case .lasso:
            return PKLassoTool()
        case .shape, .text, .image:
            // Decorative tool buttons — their UI is wired but they don't
            // bind to a PencilKit primitive. Falling back to the pen so
            // the canvas keeps drawing while the user explores them.
            return PKInkingTool(penBrush.pkInkType, color: UIColor(penColor), width: penThickness)
        }
    }

    // MARK: - Init

    init(gapDetectionService: GapDetectionServiceProtocol = GapDetectionService.shared) {
        self.gapDetectionService = gapDetectionService
        // The eraser dropdown auto-disarms its "Clear page" button when the
        // tool changes — wire that here so the view doesn't have to.
        $activeTool
            .removeDuplicates()
            .sink { [weak self] tool in
                if tool != .eraser { self?.clearPageArmed = false }
            }
            .store(in: &cancellables)
    }

    // MARK: - Local store wiring

    /// Loads metadata + first-page drawing from the store. Idempotent
    /// (later calls with the same `noteId` are no-ops) so SwiftUI's
    /// `.onAppear` retriggering during navigation does not reset the
    /// canvas. Use `switchActiveNote(_:)` to flip to a different note
    /// inside the same editor session (e.g. tab switch); that path
    /// flushes any pending save first.
    func attach(store: NotesStore, noteId: String?) {
        self.store = store
        if hasLoaded && self.noteId == noteId { return }
        loadNote(noteId)
    }

    /// Switch the editor to a different open tab. Flushes any pending
    /// debounced save for the previous note first so the user's last
    /// stroke can't bleed into the freshly-loaded one.
    func switchActiveNote(_ newNoteId: String?) {
        guard newNoteId != noteId else { return }
        if newNoteId == gapResultNoteId, gapJob.isRunning || gapJob.isCompleted {
            loadNote(newNoteId)
            return
        }
        if hasLoaded { flushPendingSave() }
        // Reset AI panel state — jobs are scoped to a single note.
        gapJobTask?.cancel()
        smartJobTask?.cancel()
        gapJob = .idle
        smartJob = .idle
        aiEnhancementPanel = .root
        aiEnhancementNotice = ""
        loadNote(newNoteId)
    }

    private func loadNote(_ newNoteId: String?) {
        guard let store else { return }
        self.noteId = newNoteId
        hasLoaded = false

        guard let id = newNoteId, let note = store.note(id: id) else {
            // No note id — likely a fresh draft pushed without store wiring,
            // or we're in a SwiftUI preview.
            hasLoaded = true
            return
        }

        noteTitle = note.title
        subject = note.subject
        bookmarked = note.bookmarked
        totalPages = max(1, note.pageSettings.count)
        currentPage = max(1, min(note.currentPage, totalPages))

        applyPageSetting(note.pageSettings[currentPage - 1])

        loadDrawing(for: currentPage)
        hasLoaded = true
        flashStatus("Synced just now")
    }

    private func loadDrawing(for page: Int) {
        guard let id = noteId, let store else { return }
        let saved = store.loadDrawing(for: id, page: page) ?? PKDrawing()
        drawingGeneration += 1
        skipNextDrawingPersist = true
        drawing = saved
    }

    /// Called from the view's `onChange(of: viewModel.drawing)`. Debounces
    /// 250ms so a flurry of strokes coalesces into one disk write. Captures
    /// the current page + generation so a late-firing save never writes to
    /// the wrong page after a flip.
    func handleDrawingChange() {
        guard hasLoaded, let id = noteId, let store else { return }
        if skipNextDrawingPersist {
            skipNextDrawingPersist = false
            return
        }
        let snapshot = drawing
        let pageAtSchedule = currentPage
        let generationAtSchedule = drawingGeneration
        saveDrawingTask?.cancel()
        saveDrawingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                guard self.drawingGeneration == generationAtSchedule else { return }
                store.saveDrawing(snapshot, for: id, page: pageAtSchedule)
                self.flashStatus("Synced just now")
            }
        }
    }

    /// Persist title edits made in the chrome `TextField`.
    func handleTitleChange(_ newTitle: String) {
        guard hasLoaded, let id = noteId, let store else { return }
        store.updateNote(id: id, title: newTitle)
    }

    /// Move the note between bubbles (or to the Unnamed bucket when nil).
    func setSubject(_ newSubject: String?) {
        subject = newSubject
        guard hasLoaded, let id = noteId, let store else { return }
        if let newSubject {
            store.updateNote(id: id, subject: .set(newSubject))
        } else {
            store.updateNote(id: id, subject: .clear)
        }
    }

    // MARK: - Page navigation

    /// Switches the editor to a different page. Flushes the current
    /// drawing immediately first (cancels the debounce) so swiping rapidly
    /// can never lose strokes.
    func goToPage(_ page: Int) {
        guard hasLoaded, let id = noteId, let store else { return }
        let clamped = max(1, min(page, totalPages))
        if clamped == currentPage { return }
        flushPendingSave()

        currentPage = clamped
        store.setCurrentPage(noteId: id, page: clamped)
        if let setting = store.note(id: id)?.pageSettings[clamped - 1] {
            applyPageSetting(setting)
        }
        loadDrawing(for: clamped)
        flashStatus("Page \(clamped) of \(totalPages)")
    }

    func goToNextPage() {
        if currentPage >= totalPages {
            addPage()
        } else {
            goToPage(currentPage + 1)
        }
    }

    func goToPreviousPage() {
        if currentPage <= 1 {
            flashStatus("Already on the first page")
            return
        }
        goToPage(currentPage - 1)
    }

    func addPage() {
        guard hasLoaded, let id = noteId, let store else { return }
        flushPendingSave()
        if let landed = store.addPage(noteId: id) {
            totalPages = store.note(id: id)?.pageSettings.count ?? totalPages + 1
            currentPage = landed
            if let setting = store.note(id: id)?.pageSettings[landed - 1] {
                applyPageSetting(setting)
            } else {
                applyPageSetting(NotePageSetting())
            }
            loadDrawing(for: landed)
            flashStatus("Page \(landed) added")
            triggerNewPageFlash()
        }
    }

    /// Pops the centered "New page" indicator for ~900 ms, matching the
    /// `flashNewPageIndicator` helper in the JSX reference.
    private func triggerNewPageFlash() {
        showNewPageFlash = true
        newPageFlashTask?.cancel()
        newPageFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !Task.isCancelled {
                self.showNewPageFlash = false
            }
        }
    }

    func copyCurrentPage() {
        guard hasLoaded, let id = noteId, let store else { return }
        flushPendingSave()
        if let landed = store.copyCurrentPage(noteId: id) {
            totalPages = store.note(id: id)?.pageSettings.count ?? totalPages + 1
            currentPage = landed
            if let setting = store.note(id: id)?.pageSettings[landed - 1] {
                applyPageSetting(setting)
            }
            loadDrawing(for: landed)
            flashStatus("Page \(landed) copied")
        }
    }

    func deleteCurrentPage() {
        guard hasLoaded, let id = noteId, let store else { return }
        flushPendingSave()
        if let error = store.deleteCurrentPage(noteId: id) {
            flashStatus(error)
            return
        }
        let deleted = currentPage
        if let updated = store.note(id: id) {
            totalPages = updated.pageSettings.count
            currentPage = updated.currentPage
            let setting = updated.pageSettings[currentPage - 1]
            applyPageSetting(setting)
        }
        loadDrawing(for: currentPage)
        flashStatus("Page \(deleted) deleted")
    }

    func rotateCurrentPage(to rotation: Int) {
        guard hasLoaded, let id = noteId, let store else { return }
        store.rotateCurrentPage(noteId: id, to: rotation)
        currentPageRotation = ((rotation % 360) + 360) % 360
        flashStatus("Page rotated \(rotation)°")
    }

    func setBackground(_ background: NotePageBackground) {
        guard hasLoaded, let id = noteId, let store else { return }
        store.setBackground(noteId: id, background: background)
        currentPageBackground = background
        flashStatus("\(background.label) applied")
    }

    private func applyPageSetting(_ setting: NotePageSetting) {
        currentPageBackground = setting.background
        currentPageRotation = setting.rotation
        currentPageBackgroundImageFilename = setting.backgroundImageFilename
        currentPageAspectHeightOverWidth = max(0.2, min(5.0, setting.aspectHeightOverWidth))
    }

    /// Two-tap clear: first call arms it, second call wipes the drawing.
    func handleClearPage() {
        if !clearPageArmed {
            clearPageArmed = true
            flashStatus("Tap clear page again to confirm")
            return
        }
        guard hasLoaded, let id = noteId, let store else { return }
        clearPageArmed = false
        drawingGeneration += 1
        skipNextDrawingPersist = true
        drawing = PKDrawing()
        store.clearCurrentPage(noteId: id)
        flashStatus("Page cleared")
    }

    // MARK: - Bookmark

    func toggleBookmark() {
        guard hasLoaded, let id = noteId, let store else { return }
        bookmarked.toggle()
        store.setBookmarked(noteId: id, value: bookmarked)
        flashStatus(bookmarked ? "Page bookmarked" : "Bookmark removed")
    }

    // MARK: - Tool actions

    private func assignActiveToolTracksPencil(_ newTool: NoteEditorTool) {
        let old = activeTool
        guard old != newTool else { return }
        previousToolForPencil = old
        if newTool == .pen || newTool == .highlighter || newTool == .lasso {
            lastInkToolForPencil = newTool
        }
        activeTool = newTool
    }

    /// Apple Pencil double-tap — respects Settings → Apple Pencil (eraser / last tool / ignore).
    func handlePencilDoubleTap(interaction _: UIPencilInteraction) {
        let action = UIPencilInteraction.preferredTapAction
        switch action {
        case .ignore:
            return
        case .switchEraser:
            if activeTool == .eraser {
                assignActiveToolTracksPencil(lastInkToolForPencil)
            } else {
                assignActiveToolTracksPencil(.eraser)
            }
            flashStatus(toolReadyStatus(for: activeTool))
        case .switchPrevious:
            if previousToolForPencil == activeTool {
                if activeTool == .eraser {
                    assignActiveToolTracksPencil(lastInkToolForPencil)
                } else {
                    assignActiveToolTracksPencil(.eraser)
                }
            } else {
                assignActiveToolTracksPencil(previousToolForPencil)
            }
            flashStatus(toolReadyStatus(for: activeTool))
        case .showColorPalette, .showInkAttributes, .showContextualPalette, .runSystemShortcut:
            if activeTool == .eraser {
                assignActiveToolTracksPencil(lastInkToolForPencil)
            } else {
                assignActiveToolTracksPencil(.eraser)
            }
            flashStatus(toolReadyStatus(for: activeTool))
        @unknown default:
            if activeTool == .eraser {
                assignActiveToolTracksPencil(lastInkToolForPencil)
            } else {
                assignActiveToolTracksPencil(.eraser)
            }
            flashStatus(toolReadyStatus(for: activeTool))
        }
    }

    /// Tap-to-toggle behaviour from the JSX (`handleConfigurableToolPress`
    /// L3047): tapping the active tool's button opens its dropdown,
    /// tapping a different tool just switches to it. The view owns the
    /// "open menu" state — this method only updates `activeTool` and
    /// status.
    ///
    /// Shape / text / image are decorative for v1 — tapping them shows a
    /// "coming soon" status without actually swapping the canvas tool.
    func selectTool(_ tool: NoteEditorTool) {
        guard tool.isImplemented else {
            flashStatus("\(tool.rawValue.capitalized) tool · coming soon")
            return
        }
        if activeTool != tool {
            assignActiveToolTracksPencil(tool)
        }
        // Image tool is one-shot: every activate reopens the picker so
        // the user can add multiple photos without re-arming. Text has
        // a panel now, so its sheet trigger lives behind `triggerTextInsert()`
        // (fired by an "Insert text" button inside the panel).
        switch tool {
        case .image:
            pendingImagePickNonce &+= 1
        default:
            break
        }
        flashStatus(toolReadyStatus(for: tool))
    }

    /// Called from the Text dropdown panel — bumps the nonce so
    /// `NoteEditorView` opens the text editor sheet with the panel's
    /// current font/size/color defaults.
    func triggerTextInsert() {
        if activeTool != .text {
            assignActiveToolTracksPencil(.text)
        }
        pendingTextInsertNonce &+= 1
        flashStatus("Insert text")
    }

    func selectPenSwatch(_ id: String) {
        penUsesCustomColor = false
        penSwatchId = id
        assignActiveToolTracksPencil(.pen)
        flashStatus(penStatus())
    }

    func selectPenBrush(_ brush: NotePenBrush) {
        penBrush = brush
        assignActiveToolTracksPencil(.pen)
        flashStatus(penStatus())
    }

    func setPenCustomColor(_ color: Color) {
        penCustomColor = color
        penUsesCustomColor = true
        assignActiveToolTracksPencil(.pen)
        flashStatus(penStatus())
    }

    func selectHighlighterSwatch(_ id: String) {
        highlighterUsesCustomColor = false
        highlighterSwatchId = id
        assignActiveToolTracksPencil(.highlighter)
        flashStatus(highlighterStatus())
    }

    func setHighlighterCustomColor(_ color: Color) {
        highlighterCustomColor = color
        highlighterUsesCustomColor = true
        assignActiveToolTracksPencil(.highlighter)
        flashStatus(highlighterStatus())
    }

    func setPenThickness(_ value: CGFloat) {
        penThickness = max(2, min(12, value))
        assignActiveToolTracksPencil(.pen)
        flashStatus(penStatus())
    }

    func setEraserMode(_ mode: NoteEraserMode) {
        eraserMode = mode
        assignActiveToolTracksPencil(.eraser)
        flashStatus(eraserStatus())
    }

    func setEraserSize(_ value: CGFloat) {
        eraserSize = max(10, min(34, value))
        assignActiveToolTracksPencil(.eraser)
        flashStatus(eraserStatus())
    }

    // MARK: Shape

    func selectShapeType(_ type: NoteShapeType) {
        shapeType = type
        assignActiveToolTracksPencil(.shape)
        flashStatus(shapeStatus())
    }

    func selectShapeSwatch(_ id: String) {
        shapeUsesCustomColor = false
        shapeSwatchId = id
        assignActiveToolTracksPencil(.shape)
        flashStatus(shapeStatus())
    }

    func setShapeCustomColor(_ color: Color) {
        shapeCustomColor = color
        shapeUsesCustomColor = true
        assignActiveToolTracksPencil(.shape)
        flashStatus(shapeStatus())
    }

    // MARK: Text

    func selectTextFont(_ font: NoteTextFont) {
        textFont = font
        assignActiveToolTracksPencil(.text)
        flashStatus(textStatus())
    }

    func setTextSize(_ value: CGFloat) {
        textSize = max(14, min(44, value))
        assignActiveToolTracksPencil(.text)
        flashStatus(textStatus())
    }

    func selectTextSwatch(_ id: String) {
        textUsesCustomColor = false
        textSwatchId = id
        assignActiveToolTracksPencil(.text)
        flashStatus(textStatus())
    }

    func setTextCustomColor(_ color: Color) {
        textCustomColor = color
        textUsesCustomColor = true
        assignActiveToolTracksPencil(.text)
        flashStatus(textStatus())
    }

    // MARK: - Status helpers

    private func toolReadyStatus(for tool: NoteEditorTool) -> String {
        switch tool {
        case .pen: return penStatus()
        case .highlighter: return highlighterStatus()
        case .eraser: return eraserStatus()
        case .lasso: return "Lasso ready"
        case .shape: return shapeStatus()
        case .text: return textStatus()
        case .image: return "Pick an image to insert"
        }
    }

    private func shapeStatus() -> String {
        "\(shapeColorLabel) \(shapeType.label.lowercased()) ready"
    }

    private func textStatus() -> String {
        "\(textFont.label) \(Int(textSize)) pt · \(textColorLabel)"
    }

    private func penStatus() -> String {
        let mm = String(format: "%.1f", Double(penThickness) / 10)
        return "\(penColorLabel) \(penBrush.label.lowercased()) · \(mm) mm ready"
    }

    private func highlighterStatus() -> String {
        "\(highlighterColorLabel) marker ready"
    }

    private func eraserStatus() -> String {
        let label = eraserMode == .object ? "Object" : "Regular"
        return "\(label) eraser · \(Int(eraserSize))px ready"
    }

    func flashStatus(_ text: String) {
        statusText = text
        statusTextResetTask?.cancel()
        statusTextResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled {
                self.statusText = "Synced just now"
            }
        }
    }

    // MARK: - AI Enhancements (UI-only v1)

    /// Opens the dropdown. If a job is already running, jump straight to
    /// the running progress panel; otherwise show the two-option root.
    func openAIEnhancements() {
        aiEnhancementNotice = ""
        if smartJob.isRunning {
            aiEnhancementPanel = .smartOrganization
        } else if gapJob.isRunning {
            aiEnhancementPanel = .taskStatus
        } else {
            aiEnhancementPanel = .root
        }
        flashStatus("Choose an AI enhancement")
    }

    func closeAIEnhancements() {
        aiEnhancementPanel = .root
        aiEnhancementNotice = ""
    }

    func selectAIEnhancementPanel(_ panel: AIEnhancementPanel) {
        aiEnhancementPanel = panel
        aiEnhancementNotice = ""
    }

    /// Starts Gap Detection. Refuses if Smart Organization is mid-run.
    func startGapDetection() {
        if smartJob.isRunning {
            aiEnhancementNotice = Self.aiBusyMessage
            aiEnhancementPanel = .taskStatus
            flashStatus("Smart Organization is already running")
            return
        }
        if gapJob.isRunning {
            aiEnhancementPanel = .taskStatus
            showGapDetectionPopup = true
            gapDetectionMode = .running
            return
        }
        if gapJob.isCompleted {
            showGapDetectionPopup = true
            gapDetectionMode = .completed
            return
        }
        showGapDetectionConfigurator()
    }

    func showGapDetectionConfigurator() {
        if smartJob.isRunning {
            aiEnhancementNotice = Self.aiBusyMessage
            aiEnhancementPanel = .taskStatus
            flashStatus("Smart Organization is already running")
            return
        }
        showGapDetectionPopup = true
        gapDetectionMode = .config
        gapDetectionConfigPanel = .root
        gapPreviewReturnPanel = .root
        gapOwnNotePickerOpen = false
        gapPreviewNoteId = nil
        gapDetectionError = nil
        flashStatus("Configure Gap Detection")
    }

    func closeGapDetectionPopup() {
        showGapDetectionPopup = false
        gapDetectionConfigPanel = .root
        gapPreviewReturnPanel = .root
        gapPreviewNoteId = nil
        if !gapJob.isRunning {
            gapDetectionError = nil
        }
    }

    /// Opens the peer-note preview, remembering whether we came from root or the community browser.
    func pushGapPreview(noteId: String) {
        gapPreviewReturnPanel = gapDetectionConfigPanel
        gapPreviewNoteId = noteId
        gapDetectionConfigPanel = .preview
    }

    /// Returns from preview to the panel that opened it.
    func popGapPreview() {
        gapDetectionConfigPanel = gapPreviewReturnPanel
        gapPreviewNoteId = nil
    }

    func minimizeGapDetectionPopup() {
        showGapDetectionPopup = false
        openAIEnhancements()
    }

    func confirmGapDetectionRun(accessToken: String) async {
        if smartJob.isRunning {
            aiEnhancementNotice = Self.aiBusyMessage
            aiEnhancementPanel = .taskStatus
            flashStatus("Smart Organization is already running")
            return
        }
        guard let store else {
            gapDetectionError = "The note store is not ready yet."
            flashStatus("Gap Detection unavailable")
            return
        }
        guard let sourceNote = gapSourceNote(in: store) else {
            gapDetectionError = "Choose a source note first."
            flashStatus("Choose a source note")
            return
        }
        guard let comparisonNote = gapComparisonNote(in: store) else {
            gapDetectionError = "Choose at least one peer note to compare."
            flashStatus("Choose a comparison note")
            return
        }

        aiEnhancementNotice = ""
        gapDetectionError = nil
        gapDetectionResponse = nil
        gapResultNoteId = nil
        gapResultPage = nil
        showGapDetectionPopup = true
        gapDetectionMode = .running
        aiEnhancementPanel = .taskStatus
        gapJobTask?.cancel()
        setJob(.gap, to: .running(progress: 0.05))
        flashStatus("Exporting PDFs")

        gapJobTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runGapDetection(
                sourceNote: sourceNote,
                comparisonNote: comparisonNote,
                accessToken: accessToken,
                store: store
            )
        }
    }

    /// Smart Organization always shows the confirmation step first
    /// (matches the JSX flow).
    func requestSmartOrganization() {
        if gapJob.isRunning {
            aiEnhancementNotice = Self.aiBusyMessage
            aiEnhancementPanel = .taskStatus
            flashStatus("Gap Detection is already running")
            return
        }
        if smartJob.isRunning || smartJob.isCompleted {
            aiEnhancementPanel = .smartOrganization
            return
        }
        aiEnhancementPanel = .smartConfirm
        aiEnhancementNotice = ""
    }

    func confirmSmartOrganization() {
        if gapJob.isRunning {
            aiEnhancementNotice = Self.aiBusyMessage
            aiEnhancementPanel = .taskStatus
            flashStatus("Gap Detection is already running")
            return
        }
        aiEnhancementPanel = .smartOrganization
        aiEnhancementNotice = ""
        flashStatus("Smart Organization started")
        runFakeJob(.smart, statusName: "Smart Organization")
    }

    func dismissSmartOrganization() {
        smartJob = .idle
        aiEnhancementPanel = .root
        aiEnhancementNotice = ""
        flashStatus("Smart Organization dismissed")
    }

    func acknowledgeGapJobResult() {
        gapJob = .idle
        gapDetectionMode = .config
        showGapDetectionPopup = false
        aiEnhancementPanel = .root
        aiEnhancementNotice = ""
    }

    func toggleGapClassMaterialPlaceholder() {
        if gapClassMaterialNames.count >= 5 {
            gapMaterialNotice = "You can attach up to five class materials."
            return
        }
        let next = "Class material \(gapClassMaterialNames.count + 1).pdf"
        gapClassMaterialNames.append(next)
        gapMaterialNotice = ""
    }

    private func runGapDetection(
        sourceNote: Note,
        comparisonNote: Note,
        accessToken: String,
        store: NotesStore
    ) async {
        do {
            setJob(.gap, to: .running(progress: 0.16))
            flashStatus("Preparing comparison")

            let sourcePDF = exportPDFData(for: sourceNote, store: store)
            let comparisonPDF = exportPDFData(for: comparisonNote, store: store)

            try validateGapPDF(sourcePDF, label: "Current note")
            try validateGapPDF(comparisonPDF, label: "Comparison note")

            setJob(.gap, to: .running(progress: 0.34))
            flashStatus("Sending PDFs to Gemini")

            let request = GapDetectionRequest(
                sourcePDFBase64: sourcePDF.base64EncodedString(),
                comparisonPDFBase64: comparisonPDF.base64EncodedString(),
                sourceFilename: safePDFFilename(sourceNote.title, fallback: "current-note.pdf"),
                comparisonFilename: safePDFFilename(comparisonNote.title, fallback: "comparison-note.pdf"),
                sourceTitle: displayTitle(sourceNote),
                comparisonTitle: displayTitle(comparisonNote),
                courseContext: sourceNote.subject ?? comparisonNote.subject
            )
            let response = try await gapDetectionService.compare(request, accessToken: accessToken)
            gapDetectionResponse = response

            setJob(.gap, to: .running(progress: 0.74))
            flashStatus("Rendering summary")

            let rendered = try GapSummaryRenderer.render(response)

            setJob(.gap, to: .running(progress: 0.90))
            flashStatus("Inserting summary")

            insertGapSummary(rendered, store: store)

            setJob(.gap, to: .completed)
            gapDetectionMode = .completed
            showGapDetectionPopup = true
            flashStatus("Gap Detection complete")
            try? await Task.sleep(nanoseconds: 850_000_000)
            if !Task.isCancelled {
                acknowledgeGapJobResult()
                flashStatus("Gap summary inserted")
            }
        } catch {
            setJob(.gap, to: .idle)
            gapDetectionMode = .config
            showGapDetectionPopup = true
            gapDetectionError = error.localizedDescription
            aiEnhancementNotice = error.localizedDescription
            flashStatus("Gap Detection failed")
        }
    }

    private func exportPDFData(for note: Note, store: NotesStore) -> Data {
        pdfService.exportNoteToPDF(
            note: note,
            store: store,
            livePage: note.id == noteId ? currentPage : nil,
            liveDrawing: note.id == noteId ? drawing : nil
        )
    }

    private func validateGapPDF(_ data: Data, label: String) throws {
        let maxBytes = 16 * 1024 * 1024
        guard !data.isEmpty else {
            throw APIError.badRequest("\(label) exported as an empty PDF.")
        }
        guard data.count <= maxBytes else {
            throw APIError.badRequest("\(label) is larger than 16 MB. Try a shorter note first.")
        }
    }

    private func insertGapSummary(_ rendered: GapSummaryRenderResult, store: NotesStore) {
        switch gapOutputMode {
        case .appendPages:
            guard let id = noteId else { return }
            flushPendingSave()
            let page = store.addPage(noteId: id) ?? totalPages
            totalPages = store.note(id: id)?.pageSettings.count ?? max(totalPages, page)
            currentPage = page
            if let setting = store.note(id: id)?.pageSettings[page - 1] {
                applyPageSetting(setting)
            }
            loadDrawing(for: page)
            saveGapImage(rendered, to: id, page: page, store: store)
            if let setting = store.note(id: id)?.pageSettings[page - 1] {
                applyPageSetting(setting)
            }
            gapResultNoteId = id
            gapResultPage = page

        case .newNote:
            let generated = store.createDraftNote(
                subject: subject,
                title: "Gap Detection - \(noteTitle)"
            )
            saveGapImage(rendered, to: generated.id, page: 1, store: store)
            gapResultNoteId = generated.id
            gapResultPage = 1
            store.openNoteInEditor(generated.id)
            switchActiveNote(generated.id)
        }
    }

    private func saveGapImage(
        _ rendered: GapSummaryRenderResult,
        to noteId: String,
        page: Int,
        store: NotesStore
    ) {
        let filename = "\(UUID().uuidString)-gap-summary.png"
        store.saveOverlayImageData(rendered.data, for: noteId, filename: filename)
        store.setPageBackgroundImage(
            noteId: noteId,
            page: page,
            filename: filename,
            aspectHeightOverWidth: rendered.pixelSize.height / max(1, rendered.pixelSize.width)
        )
    }

    private func gapSourceNote(in store: NotesStore) -> Note? {
        if let id = gapSelectedOwnNoteId, let note = store.note(id: id) {
            return note
        }
        guard let noteId else { return nil }
        return store.note(id: noteId)
    }

    private func gapComparisonNote(in store: NotesStore) -> Note? {
        let currentSourceId = gapSelectedOwnNoteId ?? noteId
        return selectedGapSourceIds
            .sorted()
            .compactMap { store.note(id: $0) }
            .first { $0.id != currentSourceId }
    }

    private func displayTitle(_ note: Note) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    private func safePDFFilename(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback.replacingOccurrences(of: ".pdf", with: "") : trimmed
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = base.components(separatedBy: forbidden).joined(separator: "-")
        let stem = String(cleaned.prefix(120))
        return stem.lowercased().hasSuffix(".pdf") ? stem : "\(stem).pdf"
    }

    private enum AIJobSlot { case gap, smart }

    /// Drives one of the two AI job slots through a short progress loop
    /// so the UI exercises running → completed without a real backend.
    private func runFakeJob(_ slot: AIJobSlot, statusName: String) {
        setJob(slot, to: .running(progress: 0))
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            for tick in 1...20 {
                try? await Task.sleep(nanoseconds: 280_000_000)
                if Task.isCancelled { return }
                let progress = Double(tick) / 20.0
                self.setJob(slot, to: .running(progress: progress))
            }
            if Task.isCancelled { return }
            self.setJob(slot, to: .completed)
            if slot == .gap {
                self.gapDetectionMode = .completed
                self.showGapDetectionPopup = true
            }
            self.flashStatus("\(statusName) complete")
        }
        switch slot {
        case .gap:
            gapJobTask?.cancel()
            gapJobTask = task
        case .smart:
            smartJobTask?.cancel()
            smartJobTask = task
        }
    }

    private func setJob(_ slot: AIJobSlot, to job: AIEnhancementJob) {
        switch slot {
        case .gap:   gapJob = job
        case .smart: smartJob = job
        }
    }

    // MARK: - Overlay helpers

    /// Convenience pass-through for the overlay layer — returns the
    /// store's overlays filtered to the active note + page. Returning
    /// `[]` when there's no active note keeps preview rendering simple.
    func currentPageOverlays(store: NotesStore) -> [NotePageOverlay] {
        guard let noteId else { return [] }
        return store.overlays(for: noteId, page: currentPage)
    }

    /// Inserts a fresh text overlay centered on the current page. Caller
    /// passes the typed string + style picked in the editor sheet.
    func insertTextOverlay(store: NotesStore, text: String, fontSize: CGFloat, colorHex: String) -> String? {
        guard let noteId else { return nil }
        let overlay = NotePageOverlay.text(
            page: currentPage,
            text: text,
            fontSize: fontSize,
            colorHex: colorHex
        )
        store.addOverlay(overlay, to: noteId)
        flashStatus("Text added")
        return overlay.id
    }

    /// Replaces an existing text overlay's content/style.
    func updateTextOverlay(
        store: NotesStore,
        overlay: NotePageOverlay,
        newText: String,
        newFontSize: CGFloat,
        newColorHex: String
    ) {
        guard let noteId else { return }
        var updated = overlay
        updated.text = newText
        updated.fontSize = newFontSize
        updated.colorHex = newColorHex
        store.updateOverlay(updated, in: noteId)
        flashStatus("Text updated")
    }

    /// Persists raw image data + appends an `.image` overlay sized to fit
    /// half the page width while preserving aspect.
    func insertImageOverlay(store: NotesStore, data: Data, pixelSize: CGSize) -> String? {
        guard let noteId else { return nil }
        let filename = "\(UUID().uuidString).png"
        store.saveOverlayImageData(data, for: noteId, filename: filename)
        let aspect: CGFloat = pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 1.0
        // Default to 50% of the page width; clamp the resulting height
        // to 70% of the page so a portrait photo doesn't fill the canvas.
        let normW: CGFloat = 0.5
        let normH = min(0.7, normW / max(0.0001, aspect) * (1.4))   // page aspect is 1:1.4 portrait
        let normRect = CGRect(x: 0.25, y: 0.3, width: normW, height: max(0.12, normH))
        let overlay = NotePageOverlay.image(
            page: currentPage,
            filename: filename,
            normRect: normRect
        )
        store.addOverlay(overlay, to: noteId)
        flashStatus("Image added")
        return overlay.id
    }

    // MARK: - Internal helpers

    private func flushPendingSave() {
        saveDrawingTask?.cancel()
        saveDrawingTask = nil
        guard hasLoaded, let id = noteId, let store else { return }
        store.saveDrawing(drawing, for: id, page: currentPage)
    }

    // MARK: - Upload

    @MainActor
    func uploadDrawing(accessToken: String) async {
        guard let noteId else {
            uploadError = "No note ID set — save the note first."
            return
        }
        guard let store, let note = store.note(id: noteId) else {
            uploadError = "Note not found."
            return
        }

        isUploading = true
        uploadError = nil

        do {
            let filename = "\(noteTitle).pdf"
            let response = try await pdfService.uploadNotePDF(
                note: note,
                store: store,
                livePage: currentPage,
                liveDrawing: drawing,
                noteId: noteId,
                filename: filename,
                courseId: note.courseId,
                accessToken: accessToken
            )
            lastUploadedAt = response.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            flashStatus("Saved to cloud")
        } catch {
            uploadError = error.localizedDescription
        }

        isUploading = false
    }

    func downloadPDF(accessToken: String) async {
        guard let noteId else {
            downloadError = "No note ID set."
            return
        }

        isDownloading = true
        downloadError = nil

        do {
            downloadedPDFData = try await pdfService.downloadPDF(
                noteId: noteId,
                accessToken: accessToken
            )
        } catch {
            downloadError = error.localizedDescription
        }

        isDownloading = false
    }

    @MainActor
    func exportPDFLocally(store: NotesStore) -> Data {
        guard let id = noteId, let note = store.note(id: id) else {
            return pdfService.exportDrawingToPDF(drawing)
        }
        return pdfService.exportNoteToPDF(
            note: note,
            store: store,
            livePage: currentPage,
            liveDrawing: drawing
        )
    }
}
