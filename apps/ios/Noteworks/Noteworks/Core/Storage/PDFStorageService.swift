//
//  PDFStorageService.swift
//  Noteworks
//
//  Created on 2026-03-18.
//

import Foundation
import PencilKit
import UIKit

/// Handles PDF export from notes (all pages, full logical page size, backgrounds,
/// overlays, rotation) and upload/download via Supabase Edge Functions.
final class PDFStorageService {
    static let shared = PDFStorageService()
    private let api = APIClient.shared

    private init() {}

    // MARK: - Page geometry (matches `NoteEditorView.pageSize` aspect)

    /// Height ÷ width — same as the editor's `pageAspect` (1.4).
    private static let pageAspectHeightOverWidth: CGFloat = 1.4

    /// Fixed PDF page width in points (72 dpi). Height follows aspect ratio.
    private static let pdfPageWidthPoints: CGFloat = 612

    /// Logical page size used for every exported PDF page (portrait).
    static var pdfLogicalPageSize: CGSize {
        CGSize(
            width: pdfPageWidthPoints,
            height: pdfPageWidthPoints * pageAspectHeightOverWidth
        )
    }

    // MARK: - Export full note → PDF Data

    /// Renders every page of the note to a multi-page PDF. Each page uses
    /// `Self.pdfLogicalPageSize`, draws the page background pattern, PencilKit
    /// ink, then text/image overlays. Page rotation from `NotePageSetting`
    /// is applied around the page center so the export matches the editor.
    ///
    /// `livePage` + `liveDrawing` supply the in-memory canvas for the page
    /// the user is currently on (disk may lag behind debounced saves).
    @MainActor
    func exportNoteToPDF(
        note: Note,
        store: NotesStore,
        livePage: Int?,
        liveDrawing: PKDrawing?
    ) -> Data {
        let pageCount = max(1, note.pageSettings.count)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: Self.pdfLogicalPageSize))

        return renderer.pdfData { pdfContext in
            for pageIndex in 1...pageCount {
                let setting = (pageIndex <= note.pageSettings.count)
                    ? note.pageSettings[pageIndex - 1]
                    : NotePageSetting()
                let pageSize = Self.logicalPageSize(for: setting)

                pdfContext.beginPage(withBounds: CGRect(origin: .zero, size: pageSize), pageInfo: [:])
                let cg = pdfContext.cgContext

                let drawing: PKDrawing
                if pageIndex == livePage, let live = liveDrawing {
                    drawing = live
                } else {
                    drawing = store.loadDrawing(for: note.id, page: pageIndex) ?? PKDrawing()
                }

                Self.fillWhitePage(cg, size: pageSize)

                let rotation = CGFloat(setting.rotation % 360)
                cg.saveGState()
                let cx = pageSize.width * 0.5
                let cy = pageSize.height * 0.5
                cg.translateBy(x: cx, y: cy)
                cg.rotate(by: rotation * (.pi / 180))
                cg.translateBy(x: -cx, y: -cy)

                if let filename = setting.backgroundImageFilename,
                   let data = store.loadOverlayImageData(for: note.id, filename: filename),
                   let image = UIImage(data: data) {
                    image.draw(in: CGRect(origin: .zero, size: pageSize))
                }
                Self.drawBackground(setting.background, in: CGRect(origin: .zero, size: pageSize), context: cg)

                let inkScale: CGFloat = 3
                let inkImage = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: inkScale)
                inkImage.draw(in: CGRect(origin: .zero, size: pageSize))

                let overlays = store.overlays(for: note.id, page: pageIndex)
                for overlay in overlays {
                    Self.drawOverlay(
                        overlay,
                        pageSize: pageSize,
                        noteId: note.id,
                        store: store,
                        context: cg
                    )
                }

                cg.restoreGState()
            }
        }
    }

    /// Legacy single-drawing export (tight bounds or letter fallback). Kept for
    /// narrow tooling; prefer `exportNoteToPDF` for sharing.
    func exportDrawingToPDF(
        _ drawing: PKDrawing,
        pageSize: CGSize = CGSize(width: 612, height: 792)
    ) -> Data {
        let drawingBounds = drawing.bounds
        let bounds: CGRect
        if drawingBounds.isEmpty || drawingBounds.width < 10 || drawingBounds.height < 10 {
            bounds = CGRect(origin: .zero, size: pageSize)
        } else {
            let inset: CGFloat = 20
            bounds = drawingBounds.insetBy(dx: -inset, dy: -inset)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            let image = drawing.image(from: bounds, scale: UIScreen.main.scale)
            image.draw(in: bounds)
        }
    }

    // MARK: - Upload PDF to Supabase

    /// Exports the full note as PDF and uploads it to the `upload-note-pdf` Edge Function.
    @MainActor
    func uploadNotePDF(
        note: Note,
        store: NotesStore,
        livePage: Int?,
        liveDrawing: PKDrawing?,
        noteId: String,
        filename: String = "note.pdf",
        courseId: String? = nil,
        accessToken: String
    ) async throws -> NoteResponse {
        let pdfData = exportNoteToPDF(note: note, store: store, livePage: livePage, liveDrawing: liveDrawing)
        return try await uploadPDFData(pdfData, noteId: noteId, filename: filename, courseId: courseId, accessToken: accessToken)
    }

    /// Legacy: exports a single `PKDrawing` only.
    func uploadDrawing(
        _ drawing: PKDrawing,
        noteId: String,
        filename: String = "note.pdf",
        accessToken: String
    ) async throws -> NoteResponse {
        let pdfData = exportDrawingToPDF(drawing)
        return try await uploadPDFData(pdfData, noteId: noteId, filename: filename, accessToken: accessToken)
    }

    /// Uploads raw PDF data to the `upload-note-pdf` Edge Function.
    func uploadPDFData(
        _ pdfData: Data,
        noteId: String,
        filename: String = "upload.pdf",
        courseId: String? = nil,
        accessToken: String
    ) async throws -> NoteResponse {
        let url = SupabaseConfig.uploadNotePDFURL(noteId: noteId, filename: filename, courseId: courseId)
        return try await api.uploadPDF(url, pdfData: pdfData, accessToken: accessToken)
    }

    // MARK: - Get signed download URL

    /// Fetches a temporary signed URL for downloading a note's PDF.
    func getSignedURL(
        noteId: String,
        expiresIn: Int? = nil,
        accessToken: String
    ) async throws -> SignedPDFURLResponse {
        let url = SupabaseConfig.getNotePDFURL(noteId: noteId, expiresIn: expiresIn)
        return try await api.get(url, accessToken: accessToken)
    }

    // MARK: - Download PDF data

    /// Convenience: fetches the signed URL then downloads the PDF binary.
    func downloadPDF(
        noteId: String,
        accessToken: String
    ) async throws -> Data {
        let signed = try await getSignedURL(noteId: noteId, accessToken: accessToken)
        guard let downloadURL = URL(string: signed.signedUrl) else {
            throw APIError.badRequest("Invalid signed URL received from server")
        }
        return try await api.downloadData(from: downloadURL)
    }

    // MARK: - Private rendering helpers

    private static func fillWhitePage(_ cg: CGContext, size: CGSize) {
        cg.saveGState()
        cg.setFillColor(UIColor.white.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        cg.restoreGState()
    }

    private static func logicalPageSize(for setting: NotePageSetting) -> CGSize {
        let aspect = max(0.2, min(5.0, setting.aspectHeightOverWidth))
        return CGSize(width: pdfPageWidthPoints, height: pdfPageWidthPoints * aspect)
    }

    /// Mirrors `NotePageBackgroundView` (dots / single column / blank).
    private static func drawBackground(
        _ background: NotePageBackground,
        in rect: CGRect,
        context cg: CGContext
    ) {
        switch background {
        case .blank:
            break
        case .dots:
            drawDotGrid(in: rect, context: cg)
        case .singleColumn:
            drawSingleColumn(in: rect, context: cg)
        }
    }

    private static func drawDotGrid(in rect: CGRect, context cg: CGContext) {
        let spacing: CGFloat = 28
        let radius: CGFloat = 1
        cg.saveGState()
        cg.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
        var y: CGFloat = spacing
        while y < rect.height {
            var x: CGFloat = spacing
            while x < rect.width {
                let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                cg.addEllipse(in: dot)
                cg.fillPath()
                x += spacing
            }
            y += spacing
        }
        cg.restoreGState()
    }

    private static func drawSingleColumn(in rect: CGRect, context cg: CGContext) {
        let centerX = rect.width / 2
        let columnWidth = min(rect.width * 0.62, 720)
        let leftEdge = centerX - columnWidth / 2
        let rightEdge = centerX + columnWidth / 2
        let top: CGFloat = 24
        let bottom = rect.height - 24

        cg.saveGState()
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.10).cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [6, 6])
        cg.move(to: CGPoint(x: centerX, y: top))
        cg.addLine(to: CGPoint(x: centerX, y: bottom))
        cg.strokePath()

        cg.setLineDash(phase: 0, lengths: [])
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.06).cgColor)
        cg.move(to: CGPoint(x: leftEdge, y: top))
        cg.addLine(to: CGPoint(x: leftEdge, y: bottom))
        cg.strokePath()
        cg.move(to: CGPoint(x: rightEdge, y: top))
        cg.addLine(to: CGPoint(x: rightEdge, y: bottom))
        cg.strokePath()
        cg.restoreGState()
    }

    @MainActor
    private static func drawOverlay(
        _ overlay: NotePageOverlay,
        pageSize: CGSize,
        noteId: String,
        store: NotesStore,
        context cg: CGContext
    ) {
        let rect = CGRect(
            x: overlay.normX * pageSize.width,
            y: overlay.normY * pageSize.height,
            width: overlay.normW * pageSize.width,
            height: overlay.normH * pageSize.height
        )
        switch overlay.kind {
        case .text:
            let text = (overlay.text?.isEmpty == false) ? (overlay.text ?? "") : "Tap to edit"
            let font = UIFont.systemFont(ofSize: overlay.fontSize ?? 18, weight: .medium)
            let color = uiColorFromHex(overlay.colorHex) ?? UIColor.label
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            let inset = rect.insetBy(dx: 8, dy: 8)
            (text as NSString).draw(
                with: inset,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )
        case .image:
            guard let name = overlay.imageFilename,
                  let data = store.loadOverlayImageData(for: noteId, filename: name),
                  let image = UIImage(data: data) else { return }
            drawImageAspectFill(image, in: rect, cornerRadius: 6, context: cg)
        }
    }

    private static func drawImageAspectFill(
        _ image: UIImage,
        in rect: CGRect,
        cornerRadius: CGFloat,
        context cg: CGContext
    ) {
        cg.saveGState()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        path.addClip()
        let iw = image.size.width
        let ih = image.size.height
        guard iw > 0, ih > 0 else {
            cg.restoreGState()
            return
        }
        let scale = max(rect.width / iw, rect.height / ih)
        let tw = iw * scale
        let th = ih * scale
        let x = rect.midX - tw * 0.5
        let y = rect.midY - th * 0.5
        image.draw(in: CGRect(x: x, y: y, width: tw, height: th))
        cg.restoreGState()
    }

    private static func uiColorFromHex(_ hex: String?) -> UIColor? {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count == 6,
              let value = UInt64(raw, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}
