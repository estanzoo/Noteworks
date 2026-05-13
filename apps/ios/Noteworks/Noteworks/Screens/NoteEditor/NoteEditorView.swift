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
    /// Full frame of each panel-bearing trigger in the shared
    /// "NoteEditorCoord" space (pen / eraser / highlighter buttons in
    /// the tool strip, AI pill in the header row, ellipsis button in
    /// the header row). The dropdown layer reads `midX` for horizontal
    /// centering and `maxY` to anchor the panel directly under whichever
    /// button opened it — so the AI dropdown is just under the AI pill
    /// instead of below the entire chrome.
    @State private var toolAnchors: [NoteEditorPanel: CGRect] = [:]

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
                    // Chrome hugs the screen edges (just a couple of pts
                    // so the rounded corners don't kiss the bezel) to
                    // match the GoodNotes-style "full-bleed" feel the
                    // user is asking for.
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                canvasArea
                    .padding(.horizontal, 0)
                    .padding(.bottom, 0)
            }
            // Push the bottom of the editor past the home-indicator /
            // bottom safe area so the page card actually reaches the
            // edge of the screen — without this, a thin gradient strip
            // peeks through under the page (the "downside is still not
            // full screen" the user is reporting). The chrome stays in
            // its safe spot at the top because we don't ignore safe
            // areas there.
            .ignoresSafeArea(.container, edges: .bottom)
            // Critical: pin the editor layout regardless of keyboard.
            // Without this, focusing the title field shrinks the canvas
            // to make room for the keyboard, the page rescales mid-edit,
            // and the user sees the whole UI jump. The title field
            // lives at the very top of the chrome so the keyboard never
            // actually obscures it — we just want the layout to stay
            // put while the keyboard overlays.
            .ignoresSafeArea(.keyboard, edges: .bottom)

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
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // Floating dropdowns layer — drawn ABOVE the chrome and
            // canvas so they're never clipped behind the page card.
            // Each panel positions itself directly under whichever
            // button opened it (the three-dots menu under the
            // ellipsis, the AI panel under the AI pill, the pen /
            // highlighter / eraser panels under their respective tool
            // icons), using the frames published via
            // `ToolButtonAnchorKey`.
            dropdownsLayer
                .ignoresSafeArea(.keyboard, edges: .bottom)
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
            // Tell MainTabView to retract its floating Home/Library/
            // Community pill so it doesn't squat over the bottom of the
            // page card while the user is writing.
            withAnimation(.easeInOut(duration: 0.22)) {
                appState.isImmersiveEditing = true
            }
        }
        .onDisappear {
            withAnimation(.easeInOut(duration: 0.22)) {
                appState.isImmersiveEditing = false
            }
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
    }

    // MARK: - Floating dropdowns

    /// Single layer that hosts every chrome dropdown — the AI pill panel,
    /// the more-options menu (and its background / rotate sub-panels),
    /// and the pen / highlighter / eraser color panels. Stacking them
    /// here (above both the chrome card AND the canvas) is what fixes
    /// the "dropdown disappears behind the note" bug: previously the
    /// three-dots menu was an overlay on the chrome card, but its
    /// vertical extent spilled into the canvas area below, and the
    /// canvas (a later sibling in the VStack) drew on top of it.
    @ViewBuilder
    private var dropdownsLayer: some View {
        GeometryReader { rootProxy in
            let rootFrame = rootProxy.frame(in: .named("NoteEditorCoord"))
            ZStack(alignment: .topLeading) {
                if openPanel != nil {
                    // Invisible scrim — catches taps outside the
                    // dropdown so the user can dismiss the panel by
                    // tapping the page. The canvas's own
                    // `onTapGesture` sits underneath this layer and
                    // can't receive taps while the layer is shown,
                    // so the scrim is what wires up "tap outside to
                    // close".
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { openPanel = nil }
                }
                if let panel = openPanel {
                    dropdownView(for: panel)
                        .modifier(DropdownAnchorModifier(
                            anchor: toolAnchors[panel],
                            rootFrame: rootFrame,
                            panelWidth: dropdownWidth(for: panel)
                        ))
                        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                }
            }
            .frame(width: rootFrame.width, height: rootFrame.height, alignment: .topLeading)
        }
        .allowsHitTesting(openPanel != nil)
    }

    @ViewBuilder
    private func dropdownView(for panel: NoteEditorPanel) -> some View {
        switch panel {
        case .ai:
            AIEnhancementsDropdown(viewModel: viewModel) {
                openPanel = nil
                viewModel.closeAIEnhancements()
            }
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
        case .pen:
            PenDropdownPanel(viewModel: viewModel)
        case .highlighter:
            HighlighterDropdownPanel(viewModel: viewModel)
        case .eraser:
            EraserDropdownPanel(viewModel: viewModel)
        case .bookmark, .share:
            EmptyView()
        }
    }

    /// Width hint per dropdown so the clamping logic in
    /// `DropdownAnchorModifier` knows when a panel would spill off the
    /// trailing edge of the screen and needs to be nudged inward.
    private func dropdownWidth(for panel: NoteEditorPanel) -> CGFloat {
        switch panel {
        case .ai:                        return 308
        case .more, .background, .rotate: return 220
        case .pen, .highlighter, .eraser: return 248
        case .bookmark, .share:           return 0
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
            .background(anchorReporter(for: .ai))

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
            // Anchor the ellipsis button so the three-dots dropdown drops
            // straight down from it (instead of from the corner of the
            // entire chrome card). We forward the same frame to .more,
            // .background, and .rotate so each sub-panel stays glued to
            // the same trigger as the user navigates between them.
            .background(anchorReporter(for: .more))
            .background(anchorReporter(for: .background))
            .background(anchorReporter(for: .rotate))
        }
    }

    /// Background helper that publishes a button's frame (in the shared
    /// "NoteEditorCoord" space) under the given panel key, so the
    /// `dropdownsLayer` knows where to anchor that panel's dropdown.
    private func anchorReporter(for panel: NoteEditorPanel) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("NoteEditorCoord"))
            Color.clear.preference(
                key: ToolButtonAnchorKey.self,
                value: [panel: frame]
            )
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

    // MARK: - Canvas area

    private var canvasArea: some View {
        GeometryReader { geometry in
            let rotation = viewModel.currentPageRotation
            // Logical page size — what the page "is". At zoom 1 the
            // whole page fits inside `geometry.size` so the user sees
            // the entire page on first render. Pinching in via the
            // outer `ZoomablePageScrollView` scales the page beyond
            // the viewport and two-finger pan navigates the detail —
            // exactly the GoodNotes flow.
            let logicalPageSize = pageSize(in: geometry.size, rotation: rotation)
            ZoomablePageScrollView(contentSize: logicalPageSize, maxScale: 3.0) {
                pageCard(logicalPageSize: logicalPageSize, rotation: rotation)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                if openPanel != nil { openPanel = nil }
            }
        }
    }

    /// The page card — background pattern + PencilKit canvas + overlay
    /// stickers, all sized to `logicalPageSize`. The outer
    /// `ZoomablePageScrollView` handles pinch + pan over the whole
    /// card, so background/canvas/overlays scale together in lockstep
    /// (no need for per-layer `scaleEffect` math).
    @ViewBuilder
    private func pageCard(logicalPageSize: CGSize, rotation: Int) -> some View {
        ZStack {
            Color.white
            NotePageBackgroundView(background: viewModel.currentPageBackground)
            PencilCanvasView(
                drawing: $viewModel.drawing,
                tool: viewModel.pkTool,
                isDrawingEnabled: viewModel.activeTool.canDraw,
                onCanvasReady: { canvas in self.liveCanvas = canvas }
            )
            if let noteId = viewModel.noteId {
                NoteOverlayLayer(
                    overlays: viewModel.currentPageOverlays(store: store),
                    pageSize: logicalPageSize,
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
        .frame(width: logicalPageSize.width, height: logicalPageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        .rotationEffect(.degrees(Double(rotation)))
    }

    /// Logical page size — the page is portrait (1 : 1.4) and fits
    /// ENTIRELY inside the visible viewport at zoom 1. Zooming in via
    /// `PKCanvasView`'s native pinch scales the content beyond the
    /// viewport, and two-finger pan moves around the zoomed detail —
    /// same flow as GoodNotes. The starting view at zoom 1 always
    /// shows the whole page, which is what the user explicitly asked
    /// for ("when it zoom in, it should still start like what it is
    /// before").
    ///
    /// We fit by height so the page fills the entire vertical canvas
    /// area; the resulting width is then derived from the aspect
    /// ratio and may leave horizontal margin on landscape iPad
    /// (unavoidable: a portrait page can't fill a landscape screen
    /// without stretching or scrolling, and stretching changes the
    /// aspect).
    private func pageSize(in available: CGSize, rotation: Int) -> CGSize {
        let isSideways = rotation == 90 || rotation == 270
        let pageAspect: CGFloat = 1.4
        let usableW = max(1, available.width)
        let usableH = max(1, available.height)
        if isSideways {
            // Rotated → after the parent's rotationEffect the page
            // presents landscape on screen. Fit by visible height
            // so the rotated bounding box doesn't spill horizontally.
            let maxW = min(usableW, usableH * pageAspect)
            let height = maxW / pageAspect
            return CGSize(width: height * pageAspect, height: height)
        } else {
            // Portrait. Fit-to-height so the whole page is visible at
            // zoom 1, then clamp by width in case the canvas is very
            // tall and narrow (e.g. iPhone portrait) — that case
            // shrinks the page so its width still fits the screen.
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

// MARK: - Dropdown anchor positioning

/// Positions a dropdown directly underneath its trigger button, using
/// the button frame published via `ToolButtonAnchorKey`.
///
/// Horizontal: centered on the button's midX, then clamped 8 pts in
/// from either side of the root frame so a panel anchored to a button
/// near the trailing edge (e.g. the ellipsis or AI pill) doesn't spill
/// off screen.
///
/// Vertical: anchored to the button's `maxY` plus a small 6-pt gap so
/// the panel reads as "dropped down from" the button rather than
/// "below the chrome". When no anchor is known yet (first render
/// before preferences flow up), we fall back to the top of the root
/// frame so the panel still has somewhere to land.
private struct DropdownAnchorModifier: ViewModifier {
    let anchor: CGRect?
    let rootFrame: CGRect
    let panelWidth: CGFloat

    func body(content: Content) -> some View {
        let anchorFrame = anchor ?? CGRect(x: rootFrame.midX, y: rootFrame.minY + 60, width: 0, height: 0)
        let minLeading: CGFloat = 8
        let maxLeading = max(minLeading, rootFrame.width - panelWidth - 8)
        let preferredLeading = anchorFrame.midX - rootFrame.minX - panelWidth / 2
        let leading = min(max(preferredLeading, minLeading), maxLeading)
        let top = anchorFrame.maxY - rootFrame.minY + 6
        return content
            .frame(width: panelWidth, alignment: .leading)
            .offset(x: leading, y: top)
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
