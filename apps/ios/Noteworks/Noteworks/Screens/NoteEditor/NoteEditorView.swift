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
import PhotosUI

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
    /// midX of each panel-bearing tool button in the shared
    /// "NoteEditorCoord" space. The tool-panel overlay reads this so the
    /// pen / eraser / highlighter dropdowns pop up directly under the
    /// icon that opened them, sitting above the page card.
    @State private var toolAnchors: [NoteEditorPanel: CGFloat] = [:]

    // MARK: - Overlay editor state

    /// Currently selected text/image overlay on the active page.
    @State private var selectedOverlayId: String? = nil
    /// Drives the text editor sheet. Holds either an existing overlay
    /// (edit mode) or `nil` for fresh insert.
    @State private var textEditorTarget: TextEditorTarget? = nil
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem? = nil

    var noteId: String?

    // MARK: - Helper types

    /// Identifier-bearing wrapper so SwiftUI can drive `.sheet(item:)`
    /// against both the "fresh insert" (nil overlay) and "edit existing"
    /// (existing overlay) cases.
    struct TextEditorTarget: Identifiable {
        let id: String
        let overlay: NotePageOverlay?
    }

    var body: some View {
        ZStack {
            // `.ignoresSafeArea()` mirrors every other screen using
            // `OnboardingBackground` (Home, Profile, Community). Without it
            // the status-bar and home-indicator regions show through as a
            // white band above the chrome and below the page footer.
            OnboardingBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                chromeCard
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                canvasArea
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
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
        .coordinateSpace(name: "NoteEditorCoord")
        .onPreferenceChange(ToolButtonAnchorKey.self) { anchors in
            toolAnchors = anchors
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Ensure the note we navigated in with is registered as an
            // open tab and is the focused tab. If the user later opens a
            // second note from CourseSpace while the editor is already
            // on-screen, `store.openNoteInEditor` will just add it to
            // `openNoteIds` and flip `activeOpenNoteId`.
            if let initialId = noteId {
                store.openNoteInEditor(initialId)
            }
            viewModel.attach(store: store, noteId: store.activeOpenNoteId ?? noteId)
        }
        .onChange(of: store.activeOpenNoteId) { _, newId in
            // Tab switch — flush the previous note's pending save first,
            // then load the freshly-active one.
            viewModel.switchActiveNote(newId)
            openPanel = nil
        }
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
        .sheet(item: $textEditorTarget) { target in
            TextOverlayEditorSheet(
                existing: target.overlay,
                onSave: { text, fontSize, hex in
                    if let existing = target.overlay {
                        viewModel.updateTextOverlay(
                            store: store,
                            overlay: existing,
                            newText: text,
                            newFontSize: fontSize,
                            newColorHex: hex
                        )
                    } else if let newId = viewModel.insertTextOverlay(
                        store: store,
                        text: text,
                        fontSize: fontSize,
                        colorHex: hex
                    ) {
                        selectedOverlayId = newId
                    }
                    textEditorTarget = nil
                },
                onCancel: {
                    textEditorTarget = nil
                }
            )
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoSelection,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoSelection) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhotoPicked(newItem) }
        }
        .onChange(of: viewModel.pendingTextInsertNonce) { _, _ in
            // Fresh-insert path. Editing existing overlays is driven from
            // the overlay layer's `onEditText` callback instead.
            textEditorTarget = TextEditorTarget(id: UUID().uuidString, overlay: nil)
        }
        .onChange(of: viewModel.pendingImagePickNonce) { _, _ in
            photoSelection = nil
            showPhotoPicker = true
        }
        .onChange(of: viewModel.currentPage) { _, _ in
            // Don't carry selection across pages — the selected id won't
            // resolve to anything on the new page and would just disable
            // PencilKit interaction for no reason.
            selectedOverlayId = nil
        }
    }

    // MARK: - Photo picker handling

    /// Loads the selected photo's bytes, downscales if necessary, and
    /// drops a fresh image overlay onto the current page.
    private func handlePhotoPicked(_ item: PhotosPickerItem) async {
        defer { photoSelection = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: raw) else {
                viewModel.flashStatus("Could not load that image")
                return
            }
            // Resize to fit within 1600 px on the longer edge so saved
            // image files stay sane. PNG preserves quality and avoids the
            // JPEG re-encoding artifacts on text-heavy screenshots.
            let downscaled = original.downscaled(toLongEdge: 1600)
            guard let data = downscaled.pngData() else {
                viewModel.flashStatus("Could not encode that image")
                return
            }
            await MainActor.run {
                if let newId = viewModel.insertImageOverlay(
                    store: store,
                    data: data,
                    pixelSize: downscaled.size
                ) {
                    selectedOverlayId = newId
                }
            }
        } catch {
            viewModel.flashStatus("Image load failed")
        }
    }

    // MARK: - Open-tab session helpers

    /// Resolves each open tab id to a `Note` for the tab bar to render.
    /// Filters out any id that the store doesn't know about so a deleted
    /// note can't ghost the bar.
    private var openTabNotes: [Note] {
        store.openNoteIds.compactMap { store.note(id: $0) }
    }

    /// Closes a tab. If it was the last one we pop back to Home; if it
    /// was the active tab the store automatically picks a neighbour and
    /// the editor reacts via `.onChange(of: store.activeOpenNoteId)`.
    private func handleCloseTab(_ id: String) {
        let next = store.closeNoteTab(id)
        openPanel = nil
        if next == nil {
            dismiss()
        }
    }

    /// Opens a fresh draft tab inheriting the current note's subject so
    /// the new note lands in the same bubble.
    private func handleNewTab() {
        _ = store.openNewNoteTab(subject: viewModel.subject)
        openPanel = nil
    }

    // MARK: - Chrome card (single glass surface)

    private var chromeCard: some View {
        VStack(spacing: 0) {
            // Tab strip — only rendered when more than one note is open
            // so a single-tab session keeps the chrome compact.
            if store.openNoteIds.count > 1 {
                NoteTabBar(
                    notes: openTabNotes,
                    activeId: store.activeOpenNoteId,
                    onSelect: { id in
                        store.setActiveOpenNote(id)
                        openPanel = nil
                    },
                    onClose: handleCloseTab,
                    onCreateNew: handleNewTab
                )
                .padding(.horizontal, 10)
                .padding(.top, 5)
                .padding(.bottom, 4)

                Rectangle()
                    .fill(NoteEditorTheme.chromeBorder.opacity(0.4))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
            }

            headerRow
                .padding(.horizontal, 10)
                .padding(.top, 5)
                .padding(.bottom, 5)

            Rectangle()
                .fill(NoteEditorTheme.chromeBorder.opacity(0.6))
                .frame(height: 1)
                .padding(.horizontal, 10)

            toolStripRow
                .padding(.horizontal, 10)
                .padding(.top, 5)
                .padding(.bottom, 5)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NoteEditorTheme.chromeFill)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        .overlay(alignment: .topTrailing) {
            moreDropdownOverlay
                .offset(x: -10, y: 44)
                .allowsHitTesting(openPanel == .more || openPanel == .background || openPanel == .rotate)
        }
    }

    /// AI Enhancements dropdown — anchored under the pill via the shared
    /// `NoteEditorCoord` space. Lives in the canvas area so it sits
    /// floating above the page card, just like the tool color panels.
    @ViewBuilder
    private func aiDropdownAnchoredOverlay(canvasWidth: CGFloat) -> some View {
        if openPanel == .ai {
            GeometryReader { canvasProxy in
                let canvasFrame = canvasProxy.frame(in: .named("NoteEditorCoord"))
                let panelWidth: CGFloat = 308
                let anchorX = toolAnchors[.ai] ?? canvasFrame.maxX
                let localCenter = anchorX - canvasFrame.minX
                let minLeading: CGFloat = 8
                let maxLeading = max(minLeading, canvasWidth - panelWidth - 8)
                let leading = min(max(localCenter - panelWidth / 2, minLeading), maxLeading)
                AIEnhancementsDropdown(viewModel: viewModel) {
                    openPanel = nil
                    viewModel.closeAIEnhancements()
                }
                .frame(width: panelWidth, alignment: .leading)
                .offset(x: leading, y: 8)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        } else {
            EmptyView()
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

            // AI Enhancements pill — opens the Gap Detection / Smart
            // Organization dropdown. The pill visually morphs to a
            // progress bar while a job is mid-run (mirrors jsx L2533).
            AIEnhancementsPill(viewModel: viewModel) {
                if openPanel == .ai {
                    openPanel = nil
                    viewModel.closeAIEnhancements()
                } else {
                    viewModel.openAIEnhancements()
                    openPanel = .ai
                }
            }
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named("NoteEditorCoord"))
                    Color.clear.preference(
                        key: ToolButtonAnchorKey.self,
                        value: [.ai: frame.midX]
                    )
                }
            )

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

    /// Horizontally-arranged title block: editable title next to a small
    /// subject / tag pill. Inlining the pill (instead of stacking it
    /// below the title) lets the header row collapse to a single
    /// icon-button-tall band, which is the single biggest contributor to
    /// chrome vertical space. The pill always shows something so the
    /// chrome doesn't look unbalanced — falls back to "Unnamed" when no
    /// subject and no tag are set.
    private var titleBlock: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            TextField("Untitled Note", text: $viewModel.noteTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button {
                showSubjectPicker = true
                openPanel = nil
            } label: {
                let label = subjectPillLabel()
                HStack(spacing: 3) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 8, weight: .semibold))
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.06 * 9)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
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
            ZStack(alignment: .top) {
                // The zoomable page lives inside its own UIScrollView so
                // the background pattern, PencilKit ink, and overlay
                // stickers all zoom + pan together. The scroll view
                // routes two-finger gestures to itself and lets
                // single-finger touches fall through to PencilKit, so
                // drawing while at any zoom level just works.
                ZoomablePageScrollView(contentSize: portraitSize) {
                    pageCard(portraitSize: portraitSize, rotation: rotation)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                // Floating color / eraser / AI dropdowns — kept OUTSIDE
                // the zoomable scroll view so they stay at native size
                // (and stay anchored to their toolbar buttons) regardless
                // of the page's current zoom level. The panel's leading
                // x is clamped to the canvas width minus the panel width
                // so it never gets pushed off screen.
                toolPanelAnchoredOverlay(canvasWidth: geometry.size.width)
                    .allowsHitTesting(
                        openPanel == .pen || openPanel == .highlighter || openPanel == .eraser
                    )

                aiDropdownAnchoredOverlay(canvasWidth: geometry.size.width)
                    .allowsHitTesting(openPanel == .ai)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if openPanel != nil { openPanel = nil }
            }
        }
    }

    /// The page card content — background, PencilKit canvas, and overlay
    /// stickers — extracted into its own builder so it can be hosted
    /// inside `ZoomablePageScrollView`. The card itself stays at
    /// `portraitSize`; the scroll view's `zoomScale` is what produces
    /// visible scale changes.
    @ViewBuilder
    private func pageCard(portraitSize: CGSize, rotation: Int) -> some View {
        ZStack {
            Color.white
            NotePageBackgroundView(background: viewModel.currentPageBackground)
            PencilCanvasView(
                drawing: $viewModel.drawing,
                tool: viewModel.pkTool,
                isDrawingEnabled: viewModel.activeTool.canDraw,
                onCanvasReady: { canvas in self.liveCanvas = canvas }
            )
            // Text + image stickers — rendered above PencilKit so they
            // sit on top of ink. The layer only intercepts touches when
            // an overlay is currently selected or the user is in
            // text/image mode, so drawing still goes through to
            // PencilKit by default.
            if let noteId = viewModel.noteId {
                NoteOverlayLayer(
                    overlays: viewModel.currentPageOverlays(store: store),
                    pageSize: portraitSize,
                    noteId: noteId,
                    selectedId: $selectedOverlayId,
                    onUpdate: { updated in
                        store.updateOverlay(updated, in: noteId)
                    },
                    onDelete: { overlay in
                        store.removeOverlay(id: overlay.id, from: noteId)
                    },
                    onEditText: { overlay in
                        textEditorTarget = TextEditorTarget(id: overlay.id, overlay: overlay)
                    },
                    imageDataProvider: { filename in
                        store.loadOverlayImageData(for: noteId, filename: filename)
                    }
                )
                .allowsHitTesting(
                    !viewModel.activeTool.canDraw || selectedOverlayId != nil
                )
            }
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

    /// Pen / highlighter / eraser dropdown rendered floating just below
    /// the chrome, centered on the trigger button's reported midX in the
    /// shared "NoteEditorCoord" space. We translate that global x into a
    /// leading offset inside the canvas frame and clamp so the 240-pt
    /// panel always stays fully visible.
    @ViewBuilder
    private func toolPanelAnchoredOverlay(canvasWidth: CGFloat) -> some View {
        if let panel = openPanel,
           panel == .pen || panel == .highlighter || panel == .eraser {
            GeometryReader { canvasProxy in
                let canvasFrame = canvasProxy.frame(in: .named("NoteEditorCoord"))
                let panelWidth: CGFloat = 248      // matches ChromeDropdownPanel width(240) + a little fudge
                let anchorX = toolAnchors[panel] ?? canvasFrame.midX
                let localCenter = anchorX - canvasFrame.minX
                let minLeading: CGFloat = 8
                let maxLeading = max(minLeading, canvasWidth - panelWidth - 8)
                let leading = min(max(localCenter - panelWidth / 2, minLeading), maxLeading)
                toolPanelOverlay
                    .frame(width: panelWidth, alignment: .leading)
                    .offset(x: leading, y: 8)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        } else {
            EmptyView()
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

// MARK: - UIImage downscale helper

private extension UIImage {
    /// Returns a copy resized so its longer edge is at most `limit` px.
    /// Returns `self` unchanged when the image is already small enough.
    func downscaled(toLongEdge limit: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > limit else { return self }
        let scale = limit / longEdge
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Preview

#Preview {
    let notesStore = NotesStore.preview()
    // Seed the preview with the first note's id (rather than a fake
    // "preview-note") so the editor actually has content to render.
    let seedId = notesStore.notes.first?.id ?? "preview-note"
    notesStore.openNoteInEditor(seedId)
    return NavigationStack {
        NoteEditorView(noteId: seedId)
            .environmentObject(AppState(notesStore: notesStore))
            .environmentObject(notesStore)
    }
}
