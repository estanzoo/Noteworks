//
//  PageInkSpace.swift
//  Noteworks
//
//  The coordinate contract for PencilKit ink on a note page, kept beside
//  the page geometry (`PDFStorageService.pdfLogicalPageSize`) it depends on.
//

import CoreGraphics
import PencilKit

/// Converts PencilKit ink between the coordinate spaces a note page uses.
///
/// Ink lives in three spaces:
///
/// - **Canonical** — `PDFStorageService.pdfLogicalPageSize` points
///   (`canonicalWidth` = 612 wide). Every persisted `PKDrawing`
///   (`NotesStore.saveDrawing` / `loadDrawing`) and every PDF / thumbnail
///   render is in this space, so a page round-trips identically in any
///   orientation or viewport. This mirrors how `NotePageOverlay` stores
///   width-independent (normalized) rects.
/// - **Display** — the on-screen logical page width the editor lays the page
///   out at (`NoteEditorView.pageSize`). `NoteEditorViewModel.displayDrawing`
///   is in this space; it is derived from canonical ink on load and
///   converted back on save / export.
/// - **Canvas** — display × the render supersample factor `S`
///   (`NoteEditorView.pageRenderSupersample`). `PencilCanvasView` scales the
///   display drawing by `S` and hosts the canvas at `S×` its bounds behind a
///   `1/S` view transform, so on screen it lines up with display space.
///
/// Only canonical ink may be written to disk or rendered to PDF.
enum PageInkSpace {
    /// Width of the canonical ink space (the PDF page width in points).
    static var canonicalWidth: CGFloat { PDFStorageService.pdfLogicalPageSize.width }

    /// Uniformly rescales `drawing` from a page `fromWidth` wide to one
    /// `toWidth` wide. Returns the input unchanged when either width is not
    /// positive or the factor is effectively 1.
    static func rescale(_ drawing: PKDrawing, fromWidth: CGFloat, toWidth: CGFloat) -> PKDrawing {
        guard let factor = scaleFactor(fromWidth: fromWidth, toWidth: toWidth) else { return drawing }
        return drawing.transformed(using: CGAffineTransform(scaleX: factor, y: factor))
    }

    /// The scale that maps a page `fromWidth` wide onto one `toWidth` wide,
    /// or `nil` when no transform is needed (non-positive width, or a factor
    /// within 0.0001 of 1).
    static func scaleFactor(fromWidth: CGFloat, toWidth: CGFloat) -> CGFloat? {
        guard fromWidth > 0, toWidth > 0 else { return nil }
        let factor = toWidth / fromWidth
        guard abs(factor - 1) > 0.0001 else { return nil }
        return factor
    }

    /// Maps display-space ink drawn on a page `displayWidth` wide into
    /// canonical space. A non-positive `displayWidth` means the drawing has
    /// not been scaled yet, so it is already canonical and returned as is.
    static func toCanonical(_ drawing: PKDrawing, fromDisplayWidth displayWidth: CGFloat) -> PKDrawing {
        rescale(drawing, fromWidth: displayWidth, toWidth: canonicalWidth)
    }

    /// Maps canonical ink onto a page `displayWidth` wide. A non-positive
    /// `displayWidth` (not laid out yet) returns the canonical drawing as is.
    static func fromCanonical(_ drawing: PKDrawing, toDisplayWidth displayWidth: CGFloat) -> PKDrawing {
        rescale(drawing, fromWidth: canonicalWidth, toWidth: displayWidth)
    }
}
