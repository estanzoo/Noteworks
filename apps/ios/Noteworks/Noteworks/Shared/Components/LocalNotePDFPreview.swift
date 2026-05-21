//
//  LocalNotePDFPreview.swift
//  Noteworks
//
//  Renders the first page of a local library note using the same PDF
//  rasterisation path and primary-tile chrome as Community post
//  attachments (`PostAttachmentPreviewPane.primaryTile`).
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
    var minHeight: CGFloat = 280

    @State private var pdfData: Data?
    @State private var failed = false

    private var displayLabel: String {
        let trimmed = (fileLabel ?? note.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    private var pdfFilenameLabel: String {
        let base = displayLabel
        return base.lowercased().hasSuffix(".pdf") ? base : "\(base).pdf"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.52))
            .overlay {
                previewContent
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
            )
            .shadow(
                color: Color(red: 73/255, green: 99/255, blue: 124/255).opacity(0.12),
                radius: 18,
                y: 8
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .task(id: taskKey) {
                await loadPreviewPDF()
            }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let pdfData, !pdfData.isEmpty {
            PDFFirstPageImage(
                data: pdfData,
                cacheKey: "local-note-\(note.id)-\(Int(note.updatedAt.timeIntervalSince1970))",
                fileLabel: pdfFilenameLabel,
                padding: 28,
                contentMode: .fit,
                showsLabel: true
            )
        } else if failed {
            PDFPlaceholderTile(label: pdfFilenameLabel)
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
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(NoteEditorTheme.accent)
                    Text("Loading preview…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoteEditorTheme.textMuted)
                }
            }
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
