//
//  NoteModels.swift
//  Noteworks
//
//  Created on 2026-03-18.
//

import Foundation

/// Matches the `notes` row returned by Edge Functions.
struct NoteResponse: Decodable {
    let id: String
    let userId: String
    let courseId: String
    let title: String
    let metadata: NotePdfMetadata?
    let createdAt: String
    let updatedAt: String
}

/// PDF metadata stored in `notes.metadata` JSONB column.
struct NotePdfMetadata: Codable {
    let pdfPath: String
    let pdfSizeBytes: Int
    let pdfFilename: String
    let pdfUploadedAt: String
}

/// Response from `get-note-pdf-url` Edge Function.
struct SignedPDFURLResponse: Decodable {
    let noteId: String
    let pdfFilename: String?
    let signedUrl: String
    let expiresIn: Int
}
