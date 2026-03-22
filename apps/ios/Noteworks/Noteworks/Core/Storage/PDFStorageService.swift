//
//  PDFStorageService.swift
//  Noteworks
//
//  Created on 2026-03-18.
//

import Foundation
import PencilKit
import UIKit

/// Handles PDF export from PencilKit drawings and upload/download via Supabase Edge Functions.
final class PDFStorageService {
    static let shared = PDFStorageService()
    private let api = APIClient.shared

    private init() {}

    // MARK: - Export PencilKit drawing → PDF Data

    /// Renders a PKDrawing to a single-page PDF.
    /// Uses the drawing's own bounds (with padding) so the output tightly wraps the content,
    /// or falls back to the provided `pageSize` for an empty/small drawing.
    func exportDrawingToPDF(
        _ drawing: PKDrawing,
        pageSize: CGSize = CGSize(width: 612, height: 792) // US Letter at 72 dpi
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

    /// Exports the drawing as PDF and uploads it to the `upload-note-pdf` Edge Function.
    /// Returns the updated `NoteResponse` from the server.
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
        accessToken: String
    ) async throws -> NoteResponse {
        let url = SupabaseConfig.uploadNotePDFURL(noteId: noteId, filename: filename)
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
}
