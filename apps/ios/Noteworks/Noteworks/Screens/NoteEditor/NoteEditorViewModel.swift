//
//  NoteEditorViewModel.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import Foundation
import PencilKit

@MainActor
class NoteEditorViewModel: ObservableObject {

    // MARK: - Canvas state

    @Published var drawing = PKDrawing()
    @Published var noteTitle = "Untitled Note"

    // MARK: - Upload state

    @Published var isUploading = false
    @Published var uploadError: String?
    @Published var lastUploadedAt: Date?

    // MARK: - Download state

    @Published var isDownloading = false
    @Published var downloadedPDFData: Data?
    @Published var downloadError: String?

    // MARK: - Dependencies

    private let pdfService = PDFStorageService.shared

    /// The note ID this editor is operating on.
    /// Must be set before calling upload/download.
    var noteId: String?

    // MARK: - Upload

    /// Exports the current drawing as PDF and uploads it to storage.
    func uploadDrawing(accessToken: String) async {
        guard let noteId else {
            uploadError = "No note ID set — save the note first."
            return
        }
        guard !drawing.bounds.isEmpty else {
            uploadError = "The canvas is empty. Draw something first."
            return
        }

        isUploading = true
        uploadError = nil

        do {
            let filename = "\(noteTitle).pdf"
            let response = try await pdfService.uploadDrawing(
                drawing,
                noteId: noteId,
                filename: filename,
                accessToken: accessToken
            )
            lastUploadedAt = ISO8601DateFormatter().date(from: response.updatedAt) ?? Date()
        } catch {
            uploadError = error.localizedDescription
        }

        isUploading = false
    }

    // MARK: - Download / view PDF

    /// Downloads the PDF attached to this note (if any).
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

    // MARK: - Local PDF export (without uploading)

    /// Returns raw PDF data from the current drawing, useful for sharing via UIActivityViewController.
    func exportPDFLocally() -> Data {
        pdfService.exportDrawingToPDF(drawing)
    }
}
