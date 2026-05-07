//
//  NoteEditorView.swift
//  Noteworks
//
//  Custom canvas chrome that mirrors the JSX `NotetakingPage` (L4138).
//
//  Layout (top to bottom):
//
//    1. Chrome card (single glass surface, two rows):
//        a. Header row: Back/Home/Search · Title-block · Bookmark/Share/
//           Gap-detection/More.
//           Title block stacks the editable title on top of a subject /
//           tag pill (matching JSX L3548–L3556).
//        b. 1px divider.
//        c. Tool strip row: undo/redo · seven-tool cluster (centered) ·
//           reserved right gutter.
//    2. Canvas area: page background pattern + PKCanvasView (rotated
//       together via `pageRotation`), with the page footer floating
//       beneath the page card.
//    3. Status strip (bottom-left), permanent.
//
//  Dropdowns from the chrome and tool strip are anchored beneath their
//  trigger via `.overlay(alignment: .topTrailing)` so they always sit
//  directly under the row that opened them.
//

import SwiftUI
import PencilKit

struct NoteEditorView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NotesStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NoteEditorViewModel()

    @State private var showShareSheet = false
    @State private var showSubjectPicker = false
    @State private var openPanel: NoteEditorPanel? = nil
    /// Live `PKCanvasView` reference — used by the chrome's undo/redo
    /// buttons. Captured once via `onCanvasReady`.
    @State private var liveCanvas: PKCanvasView? = nil
    /// Counter that ticks every time the canvas reports a change so undo /
    /// redo enabled-state in the chrome stays in sync.
    @State private var canvasRevision: Int = 0

    var noteId: String?

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                chromeCard
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 12)

                canvasArea
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    statusStrip
                    Spacer()
                    NotePageFooter(viewModel: viewModel)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { viewModel.attach(store: store, noteId: noteId) }
        .onChange(of: viewModel.drawing) { _, _ in
            viewModel.handleDrawingChange()
            canvasRevision &+= 1
        }
        .onChange(of: viewModel.noteTitle) { _, newValue in
            viewModel.handleTitleChange(newValue)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(data: viewModel.exportPDFLocally(), filename: "\(viewModel.noteTitle).pdf")
        }
        .sheet(isPresented: $showSubjectPicker) {
            BubblePickerSheet(
                currentSubject: viewModel.subject,
                onSelect: { newSubject in viewModel.setSubject(newSubject) }
            )
            .environmentObject(store)
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Chrome card (single glass surface)

    private var chromeCard: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)

            Rectangle()
                .fill(NoteEditorTheme.chromeBorder.opacity(0.6))
                .frame(height: 1)
                .padding(.horizontal, 12)

            toolStripRow
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(NoteEditorTheme.chromeFill)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        .overlay(alignment: .topTrailing) {
            moreDropdownOverlay
                .offset(x: -12, y: 56)
                .allowsHitTesting(openPanel == .more || openPanel == .background || openPanel == .rotate)
        }
        .overlay(alignment: .top) {
            toolPanelOverlay
                .offset(y: 100)
                .allowsHitTesting(openPanel == .pen || openPanel == .highlighter || openPanel == .eraser)
        }
    }

    // MARK: - Header row (chrome top half)

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            // Left cluster
            ChromeIconButton(symbol: "chevron.left") { dismiss() }
            ChromeIconButton(symbol: "house") { dismiss() }
            Divider().frame(height: 22).padding(.horizontal, 2)
            ChromeIconButton(symbol: "magnifyingglass") {
                viewModel.flashStatus("Search inside notes — coming soon")
            }
            .opacity(0.55)

            // Center title block — TITLE on top, SUBJECT/TAG pill below.
            // Matches JSX `note-app-title-shell` (L3548).
            titleBlock
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)

            // Right cluster
            ChromeIconButton(
                symbol: viewModel.bookmarked ? "bookmark.fill" : "bookmark",
                isActive: viewModel.bookmarked,
                tint: viewModel.bookmarked ? NoteEditorTheme.accent : NoteEditorTheme.textPrimary
            ) {
                viewModel.toggleBookmark()
            }

            ChromeIconButton(symbol: "square.and.arrow.up") {
                showShareSheet = true
                openPanel = nil
            }

            // Gap-detection pill — visual only for v1 (mirrors JSX L3630).
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                Text("Gap Detection")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(NoteEditorTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(NoteEditorTheme.accent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(NoteEditorTheme.accent.opacity(0.35), lineWidth: 1))
            .onTapGesture {
                viewModel.flashStatus("Gap Detection · coming soon")
            }

            ChromeIconButton(
                symbol: "ellipsis",
                isActive: openPanel == .more || openPanel == .background || openPanel == .rotate
            ) {
                if openPanel == .more || openPanel == .background || openPanel == .rotate {
                    openPanel = nil
                } else {
                    openPanel = .more
                }
            }
        }
    }

    /// Vertical title block: editable title above a subject / tag pill.
    /// Tapping the pill opens the bubble picker (mirrors JSX subject pill
    /// behaviour). The pill always shows something so the chrome doesn't
    /// look unbalanced — falls back to "Unnamed" when no subject and no
    /// tag are set.
    private var titleBlock: some View {
        VStack(spacing: 2) {
            TextField("Untitled Note", text: $viewModel.noteTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .lineLimit(1)

            Button {
                showSubjectPicker = true
                openPanel = nil
            } label: {
                let label = subjectPillLabel()
                HStack(spacing: 4) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 9, weight: .semibold))
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.06 * 10)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func subjectPillLabel() -> String {
        if let subject = viewModel.subject, !subject.isEmpty { return subject }
        return "Unnamed"
    }

    // MARK: - Tool strip row (chrome bottom half)

    private var toolStripRow: some View {
        NoteEditorToolStrip(
            viewModel: viewModel,
            openPanel: $openPanel,
            undoManager: liveCanvas?.undoManager
        )
        .id(canvasRevision)
    }

    // MARK: - Dropdown overlays

    @ViewBuilder
    private var moreDropdownOverlay: some View {
        switch openPanel {
        case .more:
            MoreOptionsDropdown(
                viewModel: viewModel,
                openBackgroundPanel: { openPanel = .background },
                openRotatePanel: { openPanel = .rotate },
                dismiss: { openPanel = nil }
            )
        case .background:
            BackgroundDropdown(viewModel: viewModel) { openPanel = nil }
        case .rotate:
            RotateDropdown(viewModel: viewModel) { openPanel = nil }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var toolPanelOverlay: some View {
        switch openPanel {
        case .pen:
            PenDropdownPanel(viewModel: viewModel)
        case .highlighter:
            HighlighterDropdownPanel(viewModel: viewModel)
        case .eraser:
            EraserDropdownPanel(viewModel: viewModel)
        default:
            EmptyView()
        }
    }

    // MARK: - Canvas area

    private var canvasArea: some View {
        GeometryReader { geometry in
            let rotation = viewModel.currentPageRotation
            let portraitSize = pageSize(in: geometry.size, rotation: rotation)
            ZStack {
                ZStack {
                    Color.white
                    NotePageBackgroundView(background: viewModel.currentPageBackground)
                    PencilCanvasView(
                        drawing: $viewModel.drawing,
                        tool: viewModel.pkTool,
                        onCanvasReady: { canvas in self.liveCanvas = canvas }
                    )
                }
                .frame(width: portraitSize.width, height: portraitSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
                .rotationEffect(.degrees(Double(rotation)))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if openPanel != nil { openPanel = nil }
            }
        }
    }

    /// Sizes the page card to fill almost all of the available editor
    /// space, keeping a soft margin so the rounded corners and shadow
    /// breathe. The page is portrait (1:1.4 aspect); rotation only
    /// affects how it presents — the underlying canvas stays portrait.
    private func pageSize(in available: CGSize, rotation: Int) -> CGSize {
        let isSideways = rotation == 90 || rotation == 270
        // Reserve room for the bottom status / page-footer strip.
        let bottomReserve: CGFloat = 44
        let usableH = max(0, available.height - bottomReserve)
        let usableW = available.width
        let pageAspect: CGFloat = 1.4
        if isSideways {
            // Visible orientation is landscape-on-screen → fit longer
            // edge horizontally.
            let maxW = min(usableW, usableH * pageAspect)
            let height = maxW / pageAspect
            return CGSize(width: height * pageAspect, height: height)
        } else {
            let maxH = min(usableH, usableW * pageAspect)
            return CGSize(width: maxH / pageAspect, height: maxH)
        }
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(NoteEditorTheme.accent)
                .frame(width: 6, height: 6)
            Text(viewModel.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(NoteEditorTheme.chromeFill)
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
        .animation(.easeInOut(duration: 0.18), value: viewModel.statusText)
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
            .environmentObject(NotesStore())
    }
}
