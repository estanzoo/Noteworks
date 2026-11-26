//
//  InkTestSupport.swift
//  NoteworksTests
//
//  Shared helpers for the ink coordinate-space tests: stroke builders,
//  tolerant comparisons, and an isolated NotesStore on a temp directory.
//

import CoreGraphics
import Foundation
import PencilKit
import Testing
@testable import Noteworks

enum InkTest {
    /// Portrait and landscape on-screen page widths (iPad-like), both far
    /// from the 612pt canonical width.
    static let portraitWidth: CGFloat = 800
    static let landscapeWidth: CGFloat = 1100

    /// A pen stroke through `points`.
    static func stroke(_ points: [CGPoint]) -> PKStroke {
        let strokePoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date(timeIntervalSince1970: 0))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

    /// A diagonal stroke from `from` to `to`.
    static func drawing(from: CGPoint, to: CGPoint) -> PKDrawing {
        let steps = 8
        let points = (0...steps).map { step -> CGPoint in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
        return PKDrawing(strokes: [stroke(points)])
    }

    /// `drawing` with `extra` appended.
    static func appending(_ extra: PKDrawing, to drawing: PKDrawing) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes + extra.strokes)
    }

    /// Every stroke point in drawing coordinates (path points with the
    /// stroke transform applied). PencilKit rounds `PKDrawing.bounds` to
    /// whole points, so geometry is compared on these instead.
    static func points(_ drawing: PKDrawing) -> [CGPoint] {
        drawing.strokes.flatMap { stroke in
            stroke.path.map { $0.location.applying(stroke.transform) }
        }
    }

    /// True when `actual` has the same strokes as `original` with every
    /// point scaled about the origin by `factor` (within `tolerance` pt).
    static func matches(
        _ actual: PKDrawing,
        _ original: PKDrawing,
        scaledBy factor: CGFloat = 1,
        tolerance: CGFloat = 0.01
    ) -> Bool {
        guard actual.strokes.count == original.strokes.count else { return false }
        let a = points(actual)
        let b = points(original)
        guard a.count == b.count, !a.isEmpty else { return false }
        return zip(a, b).allSatisfy { p, q in
            abs(p.x - q.x * factor) <= tolerance && abs(p.y - q.y * factor) <= tolerance
        }
    }

    /// Waits past the view model's 250ms drawing-save debounce.
    static func waitForDebouncedSave() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

/// A `NotesStore` on its own temporary root (via the
/// `LocalNotesPersistence(rootURL:)` test seam), with one draft note.
/// The root is removed when the fixture is released.
@MainActor
final class InkStoreFixture {
    let rootURL: URL
    let persistence: LocalNotesPersistence
    let store: NotesStore
    let noteId: String

    init() {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteworksInkTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        persistence = LocalNotesPersistence(rootURL: rootURL)
        store = NotesStore(persistence: persistence)
        store.activate(userId: NotesStore.guestUserId)
        noteId = store.createDraftNote(title: "Ink test").id
    }

    deinit {
        persistence.waitForPendingWrites()
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Blocks until every queued drawing write has landed on disk.
    func flushWrites() {
        persistence.waitForPendingWrites()
    }

    /// The canonical drawing on disk for `page` (1-based), after any
    /// queued writes have finished.
    func storedDrawing(page: Int = 1) -> PKDrawing? {
        flushWrites()
        return store.loadDrawing(for: noteId, page: page)
    }

    /// Writes canonical ink for `page` straight to the store.
    func seed(_ drawing: PKDrawing, page: Int = 1) {
        store.saveDrawing(drawing, for: noteId, page: page)
        flushWrites()
    }

    /// A view model attached to the fixture note. When `width` is given it
    /// is reported before attach, as the view does on first layout. The
    /// drawing-change echo of the load assignment is consumed, as the
    /// view's `onChange(of: displayDrawing)` would.
    func makeViewModel(reportingWidth width: CGFloat? = nil) -> NoteEditorViewModel {
        let viewModel = NoteEditorViewModel()
        if let width { viewModel.setDisplayPageWidth(width) }
        viewModel.attach(store: store, noteId: noteId)
        viewModel.handleDrawingChange()
        return viewModel
    }
}

extension NoteEditorViewModel {
    /// Simulates a finished stroke: replaces the live drawing, records the
    /// undo step and schedules the debounced save, like the canvas
    /// delegate plus the view's `onChange` do.
    func simulateStroke(to newDrawing: PKDrawing, store: NotesStore) {
        let previous = displayDrawing
        displayDrawing = newDrawing
        handleLiveDrawingChange(from: previous, store: store)
        handleDrawingChange()
    }
}
