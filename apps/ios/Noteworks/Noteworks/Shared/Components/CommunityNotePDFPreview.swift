//
//  CommunityNotePDFPreview.swift
//  Noteworks
//
//  Renders the first page of a community note PDF attachment for Gap
//  Detection previews. Downloads bytes via `PDFStorageService`.
//

import SwiftUI

struct CommunityNotePDFPreview: View {
    let noteId: String
    let fileLabel: String
    let accessToken: String
    var minHeight: CGFloat = 280

    @State private var pdfData: Data?
    @State private var failed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.52))
            .overlay { previewContent }
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
            .task(id: noteId) {
                await loadPreviewPDF()
            }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let pdfData, !pdfData.isEmpty {
            PDFFirstPageImage(
                data: pdfData,
                cacheKey: "gap-community-\(noteId)",
                fileLabel: fileLabel,
                padding: 28,
                contentMode: .fit,
                showsLabel: true
            )
        } else if failed {
            PDFPlaceholderTile(label: fileLabel)
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
                    ProgressView().tint(NoteEditorTheme.accent)
                    Text("Loading preview…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoteEditorTheme.textMuted)
                }
            }
        }
    }

    @MainActor
    private func loadPreviewPDF() async {
        pdfData = nil
        failed = false
        guard !accessToken.isEmpty else {
            failed = true
            return
        }
        if let cached = GapCommunityPDFCache.data(for: noteId) {
            pdfData = cached
            return
        }
        do {
            let downloaded = try await PDFStorageService.shared.downloadPDF(
                noteId: noteId,
                accessToken: accessToken
            )
            GapCommunityPDFCache.store(downloaded, for: noteId)
            pdfData = downloaded
        } catch {
            failed = true
        }
    }
}

enum GapCommunityPDFCache {
    private static let cache = NSCache<NSString, NSData>()

    static func data(for noteId: String) -> Data? {
        cache.object(forKey: noteId as NSString) as Data?
    }

    static func store(_ data: Data, for noteId: String) {
        cache.setObject(data as NSData, forKey: noteId as NSString, cost: data.count)
    }
}
