//
//  LocalNotePDFPreview.swift
//  Noteworks
//
//  Renders the first page of a local library note using the same PDF
//  rasterisation path as Community attachments (`PDFFirstPageImage`).
//

import SwiftUI
import PencilKit

struct LocalNotePDFPreview: View {
    @ObservedObject var store: NotesStore
    let note: Note
    /// When previewing the note currently open in the editor, pass the
    /// live page + drawing so ink that hasn't flushed to disk still shows.
    var livePage: Int? = nil
    var liveDrawing: PKDrawing? = nil
    var fileLabel: String? = nil
    var minHeight: CGFloat = 180
    var cornerRadius: CGFloat = 20
    var pdfPadding: CGFloat = 18

    @State private var pdfData: Data?
    @State private var failed = false

    private var displayLabel: String {
        let trimmed = (fileLabel ?? note.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    var body: some View {
        Group {
            if let pdfData, !pdfData.isEmpty {
                PDFFirstPageImage(
                    data: pdfData,
                    cacheKey: "local-note-\(note.id)-\(Int(note.updatedAt.timeIntervalSince1970))",
                    fileLabel: displayLabel,
                    padding: pdfPadding
                )
            } else if failed {
                PDFPlaceholderTile(label: displayLabel)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 226/255, green: 237/255, blue: 246/255).opacity(0.86),
                            Color.white.opacity(0.74),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ProgressView()
                        .tint(NoteEditorTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minHeight)
        .background(Color(red: 255/255, green: 253/255, blue: 241/255))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.72), lineWidth: 2)
        )
        .task(id: taskKey) {
            await loadPreviewPDF()
        }
    }

    private var taskKey: String {
        "\(note.id)-\(note.updatedAt.timeIntervalSince1970)-\(livePage ?? 0)-\(liveDrawing?.strokes.count ?? -1)"
    }

    @MainActor
    private func loadPreviewPDF() async {
        failed = false
        pdfData = nil

        let exported = PDFStorageService.shared.exportNoteToPDF(
            note: note,
            store: store,
            livePage: livePage,
            liveDrawing: liveDrawing,
            pageNumbers: [1]
        )

        if exported.isEmpty {
            failed = true
        } else {
            pdfData = exported
        }
    }
}
