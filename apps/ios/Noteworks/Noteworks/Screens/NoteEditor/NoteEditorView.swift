//
//  NoteEditorView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI
import PencilKit

struct NoteEditorView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = NoteEditorViewModel()

    @State private var showShareSheet = false
    @State private var showUploadSuccess = false

    var noteId: String?

    var body: some View {
        ZStack {
            // Full-screen canvas
            PencilCanvasView(drawing: $viewModel.drawing)
                .ignoresSafeArea(edges: .bottom)

            // Overlay status indicators
            VStack {
                Spacer()
                statusOverlay
                    .padding(.bottom, 100)
            }
        }
        .navigationTitle(viewModel.noteTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .onAppear { viewModel.noteId = noteId }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(data: viewModel.exportPDFLocally(), filename: "\(viewModel.noteTitle).pdf")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Share as PDF (local export, no upload)
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }

            // Upload to cloud
            Button {
                Task { await uploadDrawing() }
            } label: {
                if viewModel.isUploading {
                    ProgressView()
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                }
            }
            .disabled(viewModel.isUploading || appState.accessToken == nil)
        }
    }

    // MARK: - Status overlay

    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isUploading {
            StatusBanner(icon: "icloud.and.arrow.up", text: "Uploading PDF…", style: .info)
        } else if showUploadSuccess {
            StatusBanner(icon: "checkmark.icloud", text: "Saved to cloud", style: .success)
        } else if let error = viewModel.uploadError {
            StatusBanner(icon: "exclamationmark.icloud", text: error, style: .error)
        }
    }

    // MARK: - Actions

    private func uploadDrawing() async {
        guard let token = appState.accessToken else { return }
        await viewModel.uploadDrawing(accessToken: token)

        if viewModel.uploadError == nil {
            showUploadSuccess = true
            try? await Task.sleep(for: .seconds(2))
            showUploadSuccess = false
        }
    }
}

// MARK: - Status Banner

private struct StatusBanner: View {
    let icon: String
    let text: String
    let style: Style

    enum Style {
        case info, success, error

        var tint: Color {
            switch self {
            case .info:    return .blue
            case .success: return .green
            case .error:   return .red
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(2)
                .font(.footnote)
        }
        .foregroundStyle(style.tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Share Sheet (UIActivityViewController wrapper)

private struct ShareSheet: UIViewControllerRepresentable {
    let data: Data
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        return UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NoteEditorView(noteId: "preview-note")
            .environmentObject(AppState())
    }
}
