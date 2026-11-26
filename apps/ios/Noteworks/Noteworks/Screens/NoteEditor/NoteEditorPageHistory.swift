//
//  NoteEditorPageHistory.swift
//  Noteworks
//
//  Unified undo/redo for the active page: PencilKit strokes plus text,
//  image, and shape overlays. Each entry captures the full page snapshot
//  (drawing + overlays + image bytes) immediately before a mutation.
//

import Foundation
import PencilKit

/// One undoable step on the active editor page.
struct NoteEditorPageSnapshot: Equatable {
    var drawing: PKDrawing
    var overlays: [NotePageOverlay]
    /// PNG bytes keyed by `imageFilename` so undo can restore deleted images.
    var overlayImageData: [String: Data]
}

/// Stack-based undo/redo for `NoteEditorPageSnapshot`.
@MainActor
struct NoteEditorPageHistory {
    private var undoStack: [NoteEditorPageSnapshot] = []
    private var redoStack: [NoteEditorPageSnapshot] = []
    private let maxDepth = 100

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Applies `transform` to the drawing of every undo and redo snapshot.
    /// Snapshot drawings are in display space, so when the display width
    /// changes (rotation) they are rescaled by the same factor as the live
    /// drawing instead of being dropped. Overlays are width-independent
    /// and stay untouched.
    mutating func transformDrawings(_ transform: (PKDrawing) -> PKDrawing) {
        for index in undoStack.indices {
            undoStack[index].drawing = transform(undoStack[index].drawing)
        }
        for index in redoStack.indices {
            redoStack[index].drawing = transform(redoStack[index].drawing)
        }
    }

    /// Push `snapshot` (the state *before* a mutation) onto the undo stack.
    mutating func record(before snapshot: NoteEditorPageSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > maxDepth {
            undoStack.removeFirst(undoStack.count - maxDepth)
        }
        redoStack.removeAll()
    }

    mutating func popUndo(current: NoteEditorPageSnapshot) -> NoteEditorPageSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func popRedo(current: NoteEditorPageSnapshot) -> NoteEditorPageSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
