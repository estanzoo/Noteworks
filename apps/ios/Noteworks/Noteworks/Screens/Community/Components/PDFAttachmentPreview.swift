//
//  PDFAttachmentPreview.swift
//  Noteworks
//
//  Opens a note's PDF attachment in a `QLPreviewController`. The signed
//  URL from `get-note-pdf-url` is short-lived so we download the file
//  into a temporary location and hand QuickLook a local `fileURL` —
//  this also fixes the case where QL can't follow HTTPS redirects on
//  every device.
//

import SwiftUI
import QuickLook

struct PDFAttachmentPreview: View {
    let attachment: PostAttachment
    let accessToken: String
    let onDismiss: () -> Void

    @State private var state: LoadState = .loading
    @State private var localURL: URL?

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            switch state {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Loading \(attachment.pdfFilename ?? "PDF")…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            case .ready:
                if let url = localURL {
                    QuickLookPresenter(url: url, onDismiss: onDismiss)
                        .ignoresSafeArea()
                }
            case .failed(let message):
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: onDismiss) {
                        Text("Close")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CommunityTheme.accent)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 38)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: attachment.id) {
            await load()
        }
    }

    private func load() async {
        state = .loading
        do {
            let data = try await PDFStorageService.shared.downloadPDF(
                noteId: attachment.noteId,
                accessToken: accessToken
            )
            let url = try writeTemporary(data: data, suggestedName: attachment.pdfFilename ?? "\(attachment.noteId).pdf")
            self.localURL = url
            self.state = .ready
        } catch {
            let mapped = mapCommunityError(
                error,
                notFound: "This PDF is no longer available."
            )
            state = .failed(mapped.userMessage)
        }
    }

    private func writeTemporary(data: Data, suggestedName: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("community-pdfs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = suggestedName.hasSuffix(".pdf") ? suggestedName : "\(suggestedName).pdf"
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - QuickLook bridge

private struct QuickLookPresenter: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.delegate = context.coordinator
        preview.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismiss)
        )
        let nav = UINavigationController(rootViewController: preview)
        return nav
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: QuickLookPresenter
        init(_ parent: QuickLookPresenter) { self.parent = parent }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            parent.url as NSURL
        }

        @objc func dismiss() {
            parent.onDismiss()
        }
    }
}
