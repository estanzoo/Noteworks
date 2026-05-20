//
//  NoteEditorView.swift
//  Noteworks
//
//  Custom canvas chrome that mirrors the JSX `NotetakingPage` (L4138).
//
//  Layout (top to bottom):
//
//    1. Chrome card (single glass surface, two rows):
//        a. Header row: Back/Home/Search · Title-block · + / Bookmark /
//           Share (upload menu) / AI / More — aligned with NoteWorks_UI 2.
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
    @State private var showCommunityUpload = false
    @State private var showSubjectPicker = false
    @State private var openPanel: NoteEditorPanel? = nil
    /// Live `PKCanvasView` reference — used by the chrome's undo/redo
    /// buttons. Captured once via `onCanvasReady`.
    @State private var liveCanvas: PKCanvasView? = nil
    @State private var canUndoCanvas = false
    @State private var canRedoCanvas = false
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
    /// Largest full-editor height seen this session. When the title field
    /// focuses, the navigation host often shrinks the vertical proposal;
    /// pinning layout to this max (top-aligned) keeps the chrome and title
    /// under the status bar while the keyboard covers the bottom.
    @State private var editorStableMaxHeight: CGFloat = 0
    // MARK: - Overlay editor state

    /// Currently selected text/image overlay on the active page.
    @State private var selectedOverlayId: String? = nil
    /// Currently inline-editing text overlay (the one with focus + keyboard).
    @State private var editingOverlayId: String? = nil
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem? = nil

    var noteId: String?

    var body: some View {
        GeometryReader { outerGeo in
            let stableEditorH = max(outerGeo.size.height, editorStableMaxHeight)
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
                // Pin the chrome + canvas stack against keyboard-driven
                // shrink in the canvas; the outer `stableEditorH` frame
                // handles keeping the whole editor top-aligned.
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

                if viewModel.showGapDetectionPopup {
                    GapDetectionPopup(
                        viewModel: viewModel,
                        currentNote: currentEditorNote,
                        notes: store.notes,
                        accessToken: appState.accessToken ?? "",
                        onClose: { viewModel.closeGapDetectionPopup() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(450)
                }

                if showCommunityUpload {
                    PostEditorPopup(
                        isPresented: $showCommunityUpload,
                        accessToken: appState.accessToken ?? "",
                        initialAttachments: currentNotePlaceholderAttachments(),
                        initialTitle: sharePostTitle(),
                        initialBody: sharePostBody(),
                        initialCourseId: currentEditorNote?.courseId,
                        prepareInitialAttachments: {
                            await MainActor.run {
                                currentNoteShareAttachments()
                            }
                        },
                        onPublished: { _ in
                            viewModel.flashStatus("Uploaded to Community")
                        },
                        submit: { request in
                            let token = appState.accessToken ?? ""
                            guard !token.isEmpty else { throw CommunityError.unauthorized }
                            var created = try await CommunityService.shared.createPost(request, accessToken: token)
                            if let me = appState.profile {
                                created.author = PostAuthor(
                                    id: me.id,
                                    name: me.displayName,
                                    avatarUrl: me.avatarUrl,
                                    school: me.schoolAffiliation,
                                    major: me.major
                                )
                            }
                            return created
                        }
                    )
                    .transition(.opacity)
                    .zIndex(400)
                }
            }
            .frame(width: outerGeo.size.width, height: stableEditorH, alignment: .top)
            .coordinateSpace(name: "NoteEditorCoord")
            .onPreferenceChange(ToolButtonAnchorKey.self) { anchors in
                toolAnchors = anchors
            }
            .onChange(of: outerGeo.size.height) { _, h in
                editorStableMaxHeight = max(editorStableMaxHeight, h)
            }
            .onAppear {
                editorStableMaxHeight = max(editorStableMaxHeight, outerGeo.size.height)
            }
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
            selectedOverlayId = nil
            editingOverlayId = nil
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
            editorStableMaxHeight = 0
            selectedOverlayId = nil
            editingOverlayId = nil
        }
        .onChange(of: viewModel.drawing) { _, _ in
            viewModel.handleDrawingChange()
            canvasRevision &+= 1
            refreshCanvasUndoState()
        }
        .onChange(of: viewModel.noteTitle) { _, newValue in
            viewModel.handleTitleChange(newValue)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(
                data: viewModel.exportPDFLocally(store: store),
                filename: sharePDFFilename(title: viewModel.noteTitle)
            )
        }
        .sheet(isPresented: $showSubjectPicker) {
            BubblePickerSheet(
                currentSubject: viewModel.subject,
                onSelect: { newSubject in viewModel.setSubject(newSubject) }
            )
            .environmentObject(store)
            .presentationDetents([.medium, .large])
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
            // Drop a new empty text box on the canvas, pre-styled to the
            // panel's current font/size/color, and immediately put it
            // into inline edit mode so the keyboard appears and the user
            // can type without a separate sheet.
            if let newId = viewModel.insertTextOverlay(
                store: store,
                text: "",
                fontSize: viewModel.textSize,
                colorHex: viewModel.textColor.toHexString()
            ) {
                selectedOverlayId = newId
                editingOverlayId = newId
                openPanel = nil
            }
        }
        .onChange(of: viewModel.pendingImagePickNonce) { _, _ in
            photoSelection = nil
            showPhotoPicker = true
        }
        .onChange(of: viewModel.pendingShapeInsertNonce) { _, _ in
            if let newId = viewModel.insertShapeOverlay(store: store) {
                selectedOverlayId = newId
                editingOverlayId = nil
            }
        }
        .onChange(of: viewModel.currentPage) { _, _ in
            // Don't carry selection across pages — the selected id won't
            // resolve to anything on the new page and would just disable
            // PencilKit interaction for no reason.
            selectedOverlayId = nil
            editingOverlayId = nil
        }
    }

    /// Sanitized filename for PDF export / share sheet.
    private func sharePDFFilename(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Note" : trimmed
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = base.components(separatedBy: forbidden).joined(separator: "-")
        let capped = String(cleaned.prefix(120))
        let stem = capped.isEmpty ? "Note" : capped
        return stem.hasSuffix(".pdf") ? stem : "\(stem).pdf"
    }

    private func currentNotePlaceholderAttachments() -> [PendingPostAttachment] {
        guard let noteId = viewModel.noteId,
              store.note(id: noteId) != nil else {
            return []
        }
        return [
            PendingPostAttachment(
                id: noteId,
                filename: sharePDFFilename(title: viewModel.noteTitle),
                data: Data(),
                courseId: store.note(id: noteId)?.courseId,
                isLocked: true,
                status: .preparing
            )
        ]
    }

    private func currentNoteShareAttachments() -> [PendingPostAttachment] {
        guard let noteId = viewModel.noteId,
              store.note(id: noteId) != nil else {
            return []
        }
        return [
            PendingPostAttachment(
                id: noteId,
                filename: sharePDFFilename(title: viewModel.noteTitle),
                data: viewModel.exportPDFLocally(store: store),
                courseId: store.note(id: noteId)?.courseId,
                isLocked: true,
                status: .pending
            )
        ]
    }

    private func sharePostTitle() -> String {
        let trimmed = viewModel.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Note" : trimmed
    }

    private func sharePostBody() -> String {
        let title = sharePostTitle()
        return "Sharing my \(title) notes from Noteworks."
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

    private var currentEditorNote: Note? {
        guard let id = viewModel.noteId else { return nil }
        return store.note(id: id)
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
                            panelWidth: dropdownWidth(for: panel),
                            alignTrailing: panel == .more || panel == .background || panel == .rotate,
                            trailingInset: 16
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
        case .shape:
            ShapeDropdownPanel(viewModel: viewModel)
        case .text:
            TextDropdownPanel(viewModel: viewModel)
        case .bookmark:
            EmptyView()
        case .share:
            ShareUploadDropdown(
                onUploadToCommunity: {
                    openPanel = nil
                    guard appState.accessToken != nil else {
                        viewModel.flashStatus("Sign in to upload to Community")
                        return
                    }
                    showCommunityUpload = true
                    viewModel.flashStatus("Upload to Community")
                },
                onUploadToOtherApps: {
                    openPanel = nil
                    showShareSheet = true
                    viewModel.flashStatus("Preparing PDF for sharing")
                }
            )
        }
    }

    /// Width hint per dropdown so the clamping logic in
    /// `DropdownAnchorModifier` knows when a panel would spill off the
    /// trailing edge of the screen and needs to be nudged inward.
    private func dropdownWidth(for panel: NoteEditorPanel) -> CGFloat {
        switch panel {
        case .ai:                        return 308
        case .more:                    return 240
        case .background:              return 232
        case .rotate:                  return 200
        case .pen:                       return 308
        case .highlighter:               return 304
        case .eraser:                    return 300
        case .shape:                     return 304
        case .text:                      return 324
        case .bookmark:                   return 0
        case .share:                      return 272
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

            NoteTabBar(
                notes: openTabNotes,
                activeId: store.activeOpenNoteId,
                onSelect: { id in
                    store.setActiveOpenNote(id)
                    openPanel = nil
                },
                onClose: handleCloseTab,
                onCreateNew: handleNewTab,
                onRename: { id, title in
                    if id == viewModel.noteId {
                        viewModel.noteTitle = title
                    } else {
                        store.updateNote(id: id, title: title)
                    }
                }
            )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)

            // Right cluster — bookmark, share (upload menu), AI, more
            ChromeIconButton(
                symbol: viewModel.bookmarked ? "bookmark.fill" : "bookmark",
                isActive: viewModel.bookmarked,
                tint: viewModel.bookmarked ? NoteEditorTheme.accent : NoteEditorTheme.textPrimary
            ) {
                viewModel.toggleBookmark()
            }

            ChromeIconButton(
                symbol: "square.and.arrow.up",
                isActive: openPanel == .share
            ) {
                if openPanel == .share {
                    openPanel = nil
                    viewModel.flashStatus("Share menu closed")
                } else {
                    openPanel = .share
                    viewModel.flashStatus("Choose where to share")
                }
            }
            .background(anchorReporter(for: .share))

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
            canUndo: canUndoCanvas,
            canRedo: canRedoCanvas,
            onUndo: handleCanvasUndo,
            onRedo: handleCanvasRedo
        )
        .id(canvasRevision)
    }

    private func refreshCanvasUndoState() {
        canUndoCanvas = liveCanvas?.undoManager?.canUndo ?? false
        canRedoCanvas = liveCanvas?.undoManager?.canRedo ?? false
    }

    private func handleCanvasUndo() {
        guard let canvas = liveCanvas else { return }
        canvas.undoManager?.undo()
        // Keep the view model in sync if PencilKit did not emit
        // `canvasViewDrawingDidChange` for this undo step (defensive).
        if viewModel.drawing != canvas.drawing {
            viewModel.drawing = canvas.drawing
        }
        refreshCanvasUndoState()
        canvasRevision &+= 1
        viewModel.flashStatus("Undo")
    }

    private func handleCanvasRedo() {
        guard let canvas = liveCanvas else { return }
        canvas.undoManager?.redo()
        if viewModel.drawing != canvas.drawing {
            viewModel.drawing = canvas.drawing
        }
        refreshCanvasUndoState()
        canvasRevision &+= 1
        viewModel.flashStatus("Redo")
    }

    // MARK: - Canvas area

    private static let pageHorizontalInset: CGFloat = 16
    /// Reserved space above and below the page when fitting at zoom 1.
    private static let pageVerticalInset: CGFloat = 32

    private var canvasArea: some View {
        GeometryReader { geometry in
            let rotation = viewModel.currentPageRotation
            let basisSize = geometry.size
            // Whole page visible at zoom 1; pinch in to zoom and pan around.
            let logicalPageSize = pageSize(in: basisSize, rotation: rotation)
            let scrollContentSize = rotatedPageBounds(for: logicalPageSize, rotation: rotation)
            canvasPageStack(
                geometry: geometry,
                logicalPageSize: logicalPageSize,
                scrollContentSize: scrollContentSize,
                rotation: rotation
            )
        }
    }

    @ViewBuilder
    private func canvasPageStack(
        geometry: GeometryProxy,
        logicalPageSize: CGSize,
        scrollContentSize: CGSize,
        rotation: Int
    ) -> some View {
        let pageStack = ZStack {
            ZoomablePageScrollView(
                contentSize: scrollContentSize,
                maxScale: 8.0,
                nextSwipeCreatesPage: viewModel.currentPage >= viewModel.totalPages,
                atFirstPage: viewModel.currentPage <= 1,
                blocksPageGestures: selectedOverlayId != nil,
                contentStamp: pageContentStamp,
                onSwipeNext: { viewModel.goToNextPage() },
                onSwipePrevious: { viewModel.goToPreviousPage() }
            ) {
                pageCard(logicalPageSize: logicalPageSize, rotation: rotation)
            }
            .id("\(viewModel.noteId ?? "new")-\(viewModel.currentPage)")
            .frame(width: geometry.size.width, height: geometry.size.height)

            if viewModel.showNewPageFlash {
                NewPageFlashIndicator()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                    .transition(
                        .scale(scale: 0.86)
                            .combined(with: .opacity)
                    )
            }
        }
        .animation(
            .spring(response: 0.32, dampingFraction: 0.78),
            value: viewModel.showNewPageFlash
        )

        // IMPORTANT: do not branch on `openPanel` here. Wrapping
        // `pageStack` in a different view tree (e.g. adding
        // `.contentShape` + `.onTapGesture`) when a panel opens gives
        // SwiftUI two distinct structural identities; toggling between
        // them tears down + rebuilds the `ZoomablePageScrollView`,
        // which re-runs `makeUIView` and remounts the `PKCanvasView`
        // for a frame — that's the canvas / stroke "flash" the user
        // sees when tapping Share or any tool icon. Tap-outside-to-
        // close is already handled by the full-bleed scrim in
        // `dropdownsLayer`, so we can render the same `pageStack`
        // unconditionally and keep the canvas stable.
        pageStack
    }

    /// Bumps when persisted page/overlay data changes — not during live drag.
    private var pageContentStamp: Int {
        var stamp = canvasRevision
        stamp = stamp &* 31 &+ (viewModel.noteId?.hashValue ?? 0)
        stamp = stamp &* 31 &+ viewModel.currentPage
        stamp = stamp &* 31 &+ viewModel.currentPageRotation
        stamp = stamp &* 31 &+ (viewModel.activeTool.canDraw ? 1 : 0)
        stamp = stamp &* 31 &+ viewModel.currentPageBackground.hashValue
        stamp = stamp &* 31 &+ overlayStoreStamp
        stamp = stamp &* 31 &+ (selectedOverlayId?.hashValue ?? 0)
        stamp = stamp &* 31 &+ (editingOverlayId?.hashValue ?? 0)
        stamp = stamp &* 31 &+ (viewModel.activeTool.rawValue.hashValue)
        return stamp
    }

    private var overlayStoreStamp: Int {
        let overlays = viewModel.currentPageOverlays(store: store)
        var stamp = overlays.count
        for overlay in overlays {
            stamp = stamp &* 31 &+ overlay.id.hashValue
            stamp = stamp &* 31 &+ Int(overlay.normX * 10_000)
            stamp = stamp &* 31 &+ Int(overlay.normY * 10_000)
            stamp = stamp &* 31 &+ Int(overlay.normW * 10_000)
            stamp = stamp &* 31 &+ Int(overlay.normH * 10_000)
            stamp = stamp &* 31 &+ Int(overlay.rotationDegrees * 100)
            stamp = stamp &* 31 &+ (overlay.shapeType?.hashValue ?? 0)
        }
        return stamp
    }

    /// Page card: background → stickers → ink on top (pen draws over images/text).
    @ViewBuilder
    private func pageCard(logicalPageSize: CGSize, rotation: Int) -> some View {
        pageCardChrome(logicalPageSize: logicalPageSize, rotation: rotation) {
            ZStack {
                Color.white
                NotePageBackgroundView(
                    background: viewModel.currentPageBackground,
                    imageData: currentPageBackgroundImageData()
                )
                if let noteId = viewModel.noteId {
                    NoteOverlayLayer(
                        overlays: viewModel.currentPageOverlays(store: store),
                        pageSize: logicalPageSize,
                        noteId: noteId,
                        selectedId: $selectedOverlayId,
                        editingId: $editingOverlayId,
                        onUpdate: { updated in
                            store.updateOverlay(updated, in: noteId)
                        },
                        onDelete: { overlay in
                            store.removeOverlay(id: overlay.id, from: noteId)
                        },
                        onDuplicate: { overlay in
                            if let copy = store.duplicateOverlay(overlay, in: noteId) {
                                selectedOverlayId = copy.id
                                viewModel.flashStatus("Duplicated")
                            }
                        },
                        onSelectLasso: {
                            viewModel.activeTool = .lasso
                            selectedOverlayId = nil
                            viewModel.flashStatus("Lasso selected")
                        },
                        onCropImage: { _ in
                            viewModel.flashStatus("Crop coming soon")
                        },
                        imageDataProvider: { filename in
                            store.loadOverlayImageData(for: noteId, filename: filename)
                        }
                    )
                }
                PencilCanvasView(
                    drawing: $viewModel.drawing,
                    tool: viewModel.pkTool,
                    drawingPolicy: .pencilOnly,
                    isDrawingEnabled: viewModel.activeTool.canDraw,
                    passesFingerTouchesThrough: viewModel.activeTool.passesFingerToOverlays,
                    onCanvasReady: { canvas in
                        self.liveCanvas = canvas
                        refreshCanvasUndoState()
                    },
                    onPencilDoubleTap: { interaction in
                        viewModel.handlePencilDoubleTap(interaction: interaction)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func pageCardChrome<Inner: View>(
        logicalPageSize: CGSize,
        rotation: Int,
        @ViewBuilder content: () -> Inner
    ) -> some View {
        let displayBounds = rotatedPageBounds(for: logicalPageSize, rotation: rotation)
        content()
            .frame(width: logicalPageSize.width, height: logicalPageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
            .rotationEffect(.degrees(Double(rotation)))
            .frame(width: displayBounds.width, height: displayBounds.height)
    }

    /// Axis-aligned bounding box of the page card after rotation.
    private func rotatedPageBounds(for logicalSize: CGSize, rotation: Int) -> CGSize {
        let isSideways = rotation == 90 || rotation == 270
        if isSideways {
            return CGSize(width: logicalSize.height, height: logicalSize.width)
        }
        return logicalSize
    }

    /// Logical page size — fits entirely inside the viewport at zoom 1
    /// (with small horizontal and vertical margins). Zooming in enables
    /// pan/scroll around the enlarged page.
    private func pageSize(in available: CGSize, rotation: Int) -> CGSize {
        let pageAspect = max(0.2, min(5.0, viewModel.currentPageAspectHeightOverWidth))
        let usableW = max(1, available.width - Self.pageHorizontalInset * 2)
        let usableH = max(1, available.height - Self.pageVerticalInset * 2)
        let isSideways = rotation == 90 || rotation == 270

        // Fit the whole page inside the viewport minus margins so there is
        // visible space above and below the page card at the default zoom.
        let maxLogicalH: CGFloat
        if isSideways {
            maxLogicalH = min(usableW, usableH * pageAspect)
        } else {
            maxLogicalH = min(usableH, usableW * pageAspect)
        }
        return CGSize(width: maxLogicalH / pageAspect, height: maxLogicalH)
    }

    private func currentPageBackgroundImageData() -> Data? {
        guard let noteId = viewModel.noteId,
              let filename = viewModel.currentPageBackgroundImageFilename else {
            return nil
        }
        return store.loadOverlayImageData(for: noteId, filename: filename)
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

// MARK: - New page flash indicator

/// Centered "New page" pill that pops into view for a beat right after a
/// new page is created via swipe (or via the toolbar + button). Mirrors
/// the JSX `.new-page-indicator` card in `noteworks-library.jsx`: glass
/// material, accent stroke + glow, uppercase label next to a doc-plus
/// glyph. The indicator never blocks input — the editor passes
/// `.allowsHitTesting(false)` from the canvas overlay.
private struct NewPageFlashIndicator: View {
    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                Text("New page")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(NoteEditorTheme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(NoteEditorTheme.accent.opacity(0.32), lineWidth: 1.5)
            )
            .shadow(color: NoteEditorTheme.accent.opacity(0.22), radius: 18, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityLabel("New page added")
    }
}

// MARK: - Dropdown anchor positioning

/// Positions a dropdown directly underneath its trigger button, using
/// the button frame published via `ToolButtonAnchorKey`.
///
/// Horizontal: centered on the button's midX by default, or trailing-
/// aligned when `alignTrailing` is set (ellipsis menu). Clamped
/// `trailingInset` pts from the screen edge so right-anchored panels
/// leave a visible margin.
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
    /// When `true`, align the panel's trailing edge to the trigger's
    /// trailing edge (for header buttons on the right, e.g. ellipsis).
    var alignTrailing: Bool = false
    /// Extra inset from the screen's trailing edge (defaults to 8).
    var trailingInset: CGFloat = 8

    func body(content: Content) -> some View {
        let anchorFrame = anchor ?? CGRect(x: rootFrame.midX, y: rootFrame.minY + 60, width: 0, height: 0)
        let minLeading: CGFloat = 8
        let maxLeading = max(minLeading, rootFrame.width - panelWidth - trailingInset)
        let preferredLeading: CGFloat
        if alignTrailing {
            preferredLeading = anchorFrame.maxX - rootFrame.minX - panelWidth
        } else {
            preferredLeading = anchorFrame.midX - rootFrame.minX - panelWidth / 2
        }
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
        let unique = "\(UUID().uuidString.prefix(8))-\(filename)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(unique)
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
