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

/// Which corner the UIKit pan recognizer landed on. Used by
/// `NoteEditorView` to decide whether a manipulation pan should move
/// the whole overlay or resize it anchored at the opposite corner.
enum OverlayResizeCorner {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

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
    /// Page snapshot captured at the start of a move/resize gesture.
    @State private var overlayMutationSnapshot: NoteEditorPageSnapshot? = nil
    /// Page snapshot captured when inline text editing begins.
    @State private var textEditSnapshot: NoteEditorPageSnapshot? = nil
    /// Full frame of each panel-bearing trigger in the shared
    /// "NoteEditorCoord" space (pen / eraser / highlighter buttons in
    /// the tool strip, AI pill in the header row, ellipsis button in
    /// the header row). The dropdown layer reads `midX` for horizontal
    /// centering and `maxY` to anchor the panel directly under whichever
    /// button opened it — so the AI dropdown is just under the AI pill
    /// instead of below the entire chrome.
    @State private var toolAnchors: [NoteEditorPanel: CGRect] = [:]
    /// Editor viewport height captured while the keyboard is hidden. When
    /// the title field focuses, the navigation host shrinks the vertical
    /// proposal; pinning the stack to this height (top-aligned) keeps the
    /// chrome and title under the status bar while the keyboard covers the
    /// bottom. Crucially this is ONLY updated while `isKeyboardVisible` is
    /// false — so a transient over-tall layout sample during the navigation
    /// push can never latch and push the bottom status strip / page footer
    /// off-screen (the intermittent "Synced / Page X of Y disappear and the
    /// page sticks to the bottom with no space" bug).
    @State private var keyboardHiddenHeight: CGFloat = 0
    /// True between keyboard show/hide. The height pin only applies while
    /// the keyboard is up; with it down the stack tracks the live viewport
    /// height exactly, so it can't be stretched past the screen edge.
    @State private var isKeyboardVisible: Bool = false
    /// Latest `GeometryReader` height for the visible editor viewport.
    /// Used to re-sync the keyboard-hidden height when modal overlays open
    /// so the pinned layout state cannot drift after backgrounding.
    @State private var editorViewportHeight: CGFloat = 0
    /// Ticks once after a note has loaded and the navigation push has had
    /// a runloop turn to settle its frames. The value is folded into the
    /// inner `canvasArea` `.id` so the page-card `GeometryReader` is
    /// re-emitted against the *settled* layout proposal, fixing the
    /// intermittent "page renders tiny / squeezed when opening a note
    /// from the library" race (the first geometry sample sometimes
    /// arrives mid-animation with a smaller height). The rebuild is
    /// invisible (it happens before the first paint stabilises) and
    /// does not touch the outer editor chrome / gesture wiring, so
    /// pinch-zoom on the scroll view is unaffected.
    @State private var canvasLayoutSettleNonce: Int = 0
    @State private var tutorialAnchors: [TutorialTarget: CGRect] = [:]
    /// Current zoom factor reported by `ZoomablePageScrollView`. 1.0 = fit.
    /// Zoom is now applied as a native UIScrollView transform on the page
    /// (image-style — the whole page scales as one rasterised layer, nothing
    /// re-renders), so the page card is ALWAYS laid out at its base size and
    /// this value does NOT drive layout. It is kept only so the editor can
    /// command a reset to fit (e.g. on page change) through the binding.
    @State private var canvasZoom: CGFloat = 1.0
    // MARK: - Overlay editor state

    /// Currently selected text/image overlay on the active page.
    @State private var selectedOverlayId: String? = nil
    /// Currently inline-editing text overlay (the one with focus + keyboard).
    @State private var editingOverlayId: String? = nil
    @State private var showPhotoPicker = false
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var showPageThumbnails = false
    @State private var showSelectedPagesShare = false
    @State private var selectedPagesShareData = Data()
    @State private var isOverlayDragging = false

    /// Snapshot of the overlay being moved / resized by the UIKit pan
    /// recognizer in `ZoomablePageScrollView`. Captured at `.began`
    /// so the running translation can be applied to a stable starting
    /// rect (rather than the live, already-updated overlay) on every
    /// `.changed` event.
    @State private var manipulationOverlayId: String? = nil
    @State private var manipulationStartRect: CGRect = .zero
    @State private var manipulationCorner: OverlayResizeCorner? = nil

    /// True while an image / text / shape overlay is selected or being
    /// inline-edited, or actively dragged.
    private var hasOverlaySelection: Bool {
        selectedOverlayId != nil || editingOverlayId != nil || isOverlayDragging
    }

    private var allowsOverlayManipulation: Bool {
        viewModel.activeTool.allowsOverlayManipulation
    }

    /// True when the selected overlay on the current page is an image.
    private var isImageOverlaySelected: Bool {
        selectedImageOverlay != nil
    }

    /// Selected image on the active page, if any.
    private var selectedImageOverlay: NotePageOverlay? {
        guard let selectedId = selectedOverlayId else { return nil }
        return viewModel.currentPageOverlays(store: store)
            .first(where: { $0.id == selectedId && $0.kind == .image })
    }

    /// While an image is selected it renders above PencilKit ink; deselect
    /// returns it to the sticker layer below strokes.
    private var suppressedUnderInkOverlayIds: Set<String> {
        guard let overlay = selectedImageOverlay else { return [] }
        return [overlay.id]
    }

    /// Pencil drags move the selected sticker instead of inking.
    private var passesPencilToOverlays: Bool {
        viewModel.activeTool.passesPencilToOverlays && hasOverlaySelection
    }

    var noteId: String?
    var isTutorialPresentation: Bool = false

    private var isActiveTutorial: Bool {
        isTutorialPresentation
            && appState.tutorialCoordinator.isActive
            && !appState.tutorialCoordinator.showSkipConfirm
    }

    /// AI dropdown steps: dim + spotlight under the open panel (not full-screen frosted blur).
    private var isAITutorialDropdownStep: Bool {
        guard isActiveTutorial else { return false }
        guard let stepId = appState.tutorialCoordinator.currentStepId else { return false }
        return stepId == "ai-gap" || stepId == "ai-smart"
    }

    private var isAITutorialButtonStep: Bool {
        guard isActiveTutorial else { return false }
        return appState.tutorialCoordinator.currentStepId == "ai"
    }

    var body: some View {
        GeometryReader { outerGeo in
            // Only inflate past the live viewport while the keyboard is up
            // (to hold the chrome/title above it). With the keyboard down we
            // track the live height verbatim, so a stale or transient taller
            // sample can never push the bottom status strip / page footer
            // below the screen edge.
            let stableEditorH = isKeyboardVisible
                ? max(outerGeo.size.height, keyboardHiddenHeight)
                : outerGeo.size.height
            ZStack(alignment: .top) {
                ZStack {
                Group {
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
                }
                .allowsHitTesting(!isActiveTutorial)

                // Floating dropdowns layer — drawn ABOVE the chrome and
                // canvas so they're never clipped behind the page card.
                // Each panel positions itself directly under whichever
                // button opened it (the three-dots menu under the
                // ellipsis, the AI panel under the AI pill, the pen /
                // highlighter / eraser panels under their respective tool
                // icons), using the frames published via
                // `ToolButtonAnchorKey`.
                if isActiveTutorial && (isAITutorialButtonStep || isAITutorialDropdownStep) {
                    TutorialOverlayView(
                        coordinator: appState.tutorialCoordinator,
                        firstName: appState.tutorialCoordinator.firstName(from: appState.profile),
                        targetFrames: tutorialAnchors,
                        showsBackdrop: true,
                        showsCoachCard: false,
                        blocksBackgroundInteraction: false
                    )
                    .allowsHitTesting(false)
                    .zIndex(400)
                }

                dropdownsLayer
                    .allowsHitTesting(!isActiveTutorial)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .zIndex(410)

                if isActiveTutorial {
                    TutorialOverlayView(
                        coordinator: appState.tutorialCoordinator,
                        firstName: appState.tutorialCoordinator.firstName(from: appState.profile),
                        targetFrames: tutorialAnchors,
                        showsBackdrop: false,
                        showsCoachCard: true
                    )
                    .zIndex(430)
                }

                if showPageThumbnails {
                    PageThumbnailsModal(
                        viewModel: viewModel,
                        store: store,
                        onClose: {
                            showPageThumbnails = false
                            viewModel.flashStatus("Page thumbnails closed")
                        },
                        onSharePages: { pages in
                            selectedPagesShareData = viewModel.exportSelectedPagesPDF(store: store, pages: pages)
                            showSelectedPagesShare = true
                            viewModel.flashStatus("Preparing selected pages PDF")
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(420)
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

                if viewModel.showGapDetectionPopup {
                    GapDetectionPopup(
                        viewModel: viewModel,
                        creditsStore: appState.creditsStore,
                        currentNote: currentEditorNote,
                        accessToken: appState.accessToken ?? "",
                        currentUserId: appState.currentUser?.id,
                        onClose: { viewModel.closeGapDetectionPopup() }
                    )
                    .frame(width: outerGeo.size.width, height: outerGeo.size.height)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(450)
                }

                if viewModel.showSmartOrganizationPopup {
                    SmartOrganizationPopup(
                        viewModel: viewModel,
                        creditsStore: appState.creditsStore,
                        noteTitle: currentEditorNote?.title.isEmpty == false
                            ? (currentEditorNote?.title ?? "this note")
                            : "this note",
                        accessToken: appState.accessToken ?? "",
                        onClose: { viewModel.closeSmartOrganizationPopup() }
                    )
                    .frame(width: outerGeo.size.width, height: outerGeo.size.height)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(460)
                }

                if viewModel.showAISummaryHistory {
                    AISummaryHistoryPopup(
                        entries: viewModel.aiSummaryHistory(for: currentEditorNote?.id),
                        onSelect: { viewModel.openAISummaryEntry($0) },
                        onClose: { viewModel.closeAISummaryHistory() }
                    )
                    .frame(width: outerGeo.size.width, height: outerGeo.size.height)
                    .transition(.opacity)
                    .zIndex(470)
                }

                HStack {
                    Spacer()
                    VStack {
                        if let entry = viewModel.activeGapSummary {
                            GapSummarySidePanel(entry: entry) {
                                viewModel.closeGapSummary()
                            }
                            .padding(.top, 156)
                            .padding(.trailing, 24)
                        } else if let entry = viewModel.activeSmartSummary {
                            SmartSummarySidePanel(entry: entry) {
                                viewModel.closeSmartSummary()
                            }
                            .padding(.top, 156)
                            .padding(.trailing, 24)
                        }
                        Spacer()
                    }
                }
                .frame(width: outerGeo.size.width, height: outerGeo.size.height, alignment: .topTrailing)
                .allowsHitTesting(viewModel.activeGapSummary != nil || viewModel.activeSmartSummary != nil)
                .zIndex(440)
            }
            .frame(width: outerGeo.size.width, height: outerGeo.size.height, alignment: .top)
            .coordinateSpace(name: "NoteEditorCoord")
            .onPreferenceChange(ToolButtonAnchorKey.self) { anchors in
                toolAnchors = anchors
            }
            .onChange(of: outerGeo.size.height) { _, h in
                editorViewportHeight = h
                // Snapshot the full height only when the keyboard isn't the
                // reason the viewport is its current size.
                if !isKeyboardVisible {
                    keyboardHiddenHeight = h
                }
            }
            .onChange(of: outerGeo.size.width) { _, _ in
                // Rotation flips width. Re-snapshot against the new viewport
                // so the editor stack resizes to the new orientation instead
                // of being stretched to the previous one's height.
                editorViewportHeight = outerGeo.size.height
                if !isKeyboardVisible {
                    keyboardHiddenHeight = outerGeo.size.height
                }
            }
            .onAppear {
                editorViewportHeight = outerGeo.size.height
                if !isKeyboardVisible {
                    keyboardHiddenHeight = outerGeo.size.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )) { _ in
                isKeyboardVisible = false
            }
            .onChange(of: viewModel.showGapDetectionPopup) { _, isShowing in
                guard isShowing, editorViewportHeight > 0, !isKeyboardVisible else { return }
                keyboardHiddenHeight = editorViewportHeight
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
            if !isTutorialPresentation, let initialId = noteId {
                store.openNoteInEditor(initialId)
            }
            let attachedNoteId = isTutorialPresentation ? nil : (store.activeOpenNoteId ?? noteId)
            viewModel.attach(store: store, noteId: attachedNoteId, creditsStore: appState.creditsStore)
            selectedOverlayId = nil
            editingOverlayId = nil
            // Tell MainTabView to retract its floating Home/Library/
            // Community pill so it doesn't squat over the bottom of the
            // page card while the user is writing.
            withAnimation(.easeInOut(duration: 0.22)) {
                appState.isImmersiveEditing = true
            }
            // After the navigation push + initial `attach` settle, bump
            // the canvas layout nonce so the inner page-card
            // `GeometryReader` re-emits against the final frame. Fixes
            // the "page renders tiny / squeezed on first open" race.
            DispatchQueue.main.async {
                canvasLayoutSettleNonce &+= 1
            }
            syncTutorialNoteEditorState()
            DispatchQueue.main.async {
                syncTutorialNoteEditorState()
            }
        }
        .onDisappear {
            withAnimation(.easeInOut(duration: 0.22)) {
                appState.isImmersiveEditing = false
            }
        }
        .onChange(of: appState.tutorialCoordinator.currentStepId) { _, _ in
            syncTutorialNoteEditorState()
        }
        .onChange(of: appState.tutorialCoordinator.stepIndex) { _, _ in
            syncTutorialNoteEditorState()
        }
        .onChange(of: appState.tutorialCoordinator.isActive) { _, _ in
            syncTutorialNoteEditorState()
        }
        .onChange(of: appState.tutorialCoordinator.tutorialAIPanelOpen) { _, shouldOpen in
            guard isTutorialPresentation else { return }
            if shouldOpen {
                syncTutorialNoteEditorState()
            } else if appState.tutorialCoordinator.isActive {
                openPanel = nil
                viewModel.closeAIEnhancements()
            }
        }
        .onChange(of: store.activeOpenNoteId) { _, newId in
            // Tab switch — flush the previous note's pending save first,
            // then load the freshly-active one.
            viewModel.switchActiveNote(newId)
            openPanel = nil
            if !isKeyboardVisible {
                keyboardHiddenHeight = editorViewportHeight
            }
            selectedOverlayId = nil
            editingOverlayId = nil
            // Re-fit the page card against the (possibly different)
            // aspect ratio of the freshly-active note.
            DispatchQueue.main.async {
                canvasLayoutSettleNonce &+= 1
            }
        }
        .onChange(of: viewModel.drawing) { _, _ in
            viewModel.handleDrawingChange()
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
        .sheet(isPresented: $showSelectedPagesShare) {
            ShareSheet(
                data: selectedPagesShareData,
                filename: sharePDFFilename(title: "\(viewModel.noteTitle) selected pages")
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
                if let overlay = viewModel.currentPageOverlays(store: store)
                    .first(where: { $0.id == newId }) {
                    enterSelectMode(for: overlay)
                }
            }
        }
        .onChange(of: editingOverlayId) { oldValue, newValue in
            if newValue != nil {
                textEditSnapshot = viewModel.makePageSnapshot(store: store)
            } else if oldValue != nil, let before = textEditSnapshot {
                viewModel.recordPageMutation(before: before, store: store)
                textEditSnapshot = nil
                if let selectedId = selectedOverlayId,
                   let overlay = viewModel.currentPageOverlays(store: store)
                    .first(where: { $0.id == selectedId }) {
                    enterSelectMode(for: overlay)
                }
            }
        }
        .onChange(of: viewModel.currentPage) { _, _ in
            // Don't carry selection across pages — the selected id won't
            // resolve to anything on the new page and would just disable
            // PencilKit interaction for no reason.
            selectedOverlayId = nil
            editingOverlayId = nil
            // Return to fit zoom on page changes so the new page is
            // visible end-to-end instead of opening mid-zoom.
            canvasZoom = 1.0
        }
        .onChange(of: viewModel.activeTool) { _, newTool in
            if !newTool.allowsOverlayManipulation {
                selectedOverlayId = nil
                editingOverlayId = nil
            }
        }
        .overlay {
            if isTutorialPresentation, appState.tutorialCoordinator.isActive {
                TutorialSkipConfirmPopup(coordinator: appState.tutorialCoordinator)
            }
        }
        .onPreferenceChange(TutorialAnchorKey.self) { tutorialAnchors = $0 }
    }

    /// Sanitized filename for PDF export / share sheet.
    private func syncTutorialNoteEditorState() {
        guard isTutorialPresentation, appState.tutorialCoordinator.isActive else { return }
        guard let stepId = appState.tutorialCoordinator.currentStepId else { return }

        viewModel.showGapDetectionPopup = false
        viewModel.showSmartOrganizationPopup = false

        switch stepId {
        case "ai-gap", "ai-smart":
            viewModel.aiEnhancementPanel = .root
            viewModel.openAIEnhancements()
            openPanel = .ai
        case "ai":
            viewModel.aiEnhancementPanel = .root
            viewModel.closeAIEnhancements()
            openPanel = nil
        default:
            break
        }
    }

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
                    if let overlay = viewModel.currentPageOverlays(store: store)
                        .first(where: { $0.id == newId }) {
                        enterSelectMode(for: overlay)
                    }
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
            AIEnhancementsDropdown(
                viewModel: viewModel,
                creditsStore: appState.creditsStore,
                noteId: viewModel.noteId
            ) {
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
                },
                onReorder: { fromId, toId in
                    store.reorderOpenNoteTab(from: fromId, to: toId)
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
            .tutorialAnchor(.noteAIButton)
            .tutorialHighlight(.noteAIButton, activeTarget: appState.tutorialCoordinator.activeTarget)

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
    /// chrome doesn't look unbalanced — falls back to Untitled Bubble when
    /// no subject is set.
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
        NotesStore.resolvedBubbleSubject(viewModel.subject)
    }

    // MARK: - Tool strip row (chrome bottom half)

    private var toolStripRow: some View {
        NoteEditorToolStrip(
            viewModel: viewModel,
            openPanel: $openPanel,
            canUndo: viewModel.canUndoPageEdit,
            canRedo: viewModel.canRedoPageEdit,
            onUndo: handleEditorUndo,
            onRedo: handleEditorRedo,
            onOpenThumbnails: {
                openPanel = nil
                showPageThumbnails = true
                viewModel.flashStatus("Page thumbnails opened")
            }
        )
    }

    private func handleEditorUndo() {
        guard viewModel.undoPageEdit(store: store, canvas: liveCanvas) else { return }
        selectedOverlayId = nil
        editingOverlayId = nil
        viewModel.flashStatus("Undo")
    }

    private func handleEditorRedo() {
        guard viewModel.redoPageEdit(store: store, canvas: liveCanvas) else { return }
        selectedOverlayId = nil
        editingOverlayId = nil
        viewModel.flashStatus("Redo")
    }

    /// Commits an overlay move/resize/pinch gesture as one undo step.
    private func commitOverlayMutationIfNeeded() {
        guard let before = overlayMutationSnapshot else { return }
        viewModel.recordPageMutation(before: before, store: store)
        overlayMutationSnapshot = nil
    }

    /// Switches to select mode so Apple Pencil can move / resize the sticker.
    private func enterSelectMode(for overlay: NotePageOverlay) {
        guard overlay.kind.supportsSelectMode else { return }
        viewModel.selectTool(.imageSelect)
    }

    // MARK: - Canvas area

    /// Clears overlay selection / inline edit so the canvas returns to
    /// the same interaction mode as on first open (page pinch-zoom live,
    /// no selection chrome, page-swipe enabled).
    private func deselectOverlays() {
        guard hasOverlaySelection else { return }
        editingOverlayId = nil
        selectedOverlayId = nil
        if viewModel.activeTool == .imageSelect {
            viewModel.selectTool(.pen)
        }
    }

    /// Selected image/shape sticker used for toolbar hit-testing.
    private func selectedAdjustToolbarOverlay(pageSize: CGSize) -> NotePageOverlay? {
        guard let selectedId = selectedOverlayId else { return nil }
        guard let overlay = viewModel.currentPageOverlays(store: store)
            .first(where: { $0.id == selectedId }),
              overlay.kind == .image || overlay.kind == .shape
        else { return nil }
        return overlay
    }

    /// Base-coordinate rect of the floating adjust toolbar (if any).
    private func overlayAdjustToolbarRect(pageSize: CGSize) -> CGRect? {
        guard let overlay = selectedAdjustToolbarOverlay(pageSize: pageSize) else { return nil }
        return ImageOverlayAdjustToolbarMetrics.frame(
            above: overlayRect(for: overlay, in: pageSize)
        )
    }

    /// Base-coordinate rect of the selected image overlay, if any.
    private func selectedImageOverlayRect(pageSize: CGSize) -> CGRect? {
        guard isImageOverlaySelected,
              let selectedId = selectedOverlayId,
              let overlay = viewModel.currentPageOverlays(store: store)
            .first(where: { $0.id == selectedId && $0.kind == .image })
        else { return nil }
        return overlayRect(for: overlay, in: pageSize)
    }

    /// Base-coordinate rects where sticker drag must not steal touches
    /// (floating image/shape adjust toolbar above the selection).
    private func overlayToolbarExclusionRects(pageSize: CGSize) -> [CGRect] {
        guard let rect = overlayAdjustToolbarRect(pageSize: pageSize) else { return [] }
        return [rect]
    }

    /// UIKit toolbar tap → duplicate / delete / etc.
    private func handleOverlayAdjustToolbarTap(
        _ button: ImageOverlayAdjustToolbarButton,
        pageSize: CGSize
    ) {
        guard let noteId = viewModel.noteId,
              let overlay = selectedAdjustToolbarOverlay(pageSize: pageSize)
        else { return }

        switch button {
        case .crop:
            viewModel.flashStatus("Crop coming soon")
        case .lasso:
            viewModel.selectTool(.lasso)
            selectedOverlayId = nil
        case .cut:
            deleteOverlay(overlay, noteId: noteId)
        case .duplicate:
            duplicateOverlay(overlay, noteId: noteId, pageSize: pageSize)
        case .delete:
            deleteOverlay(overlay, noteId: noteId)
        case .more:
            break
        }
    }

    /// Removes the overlay and clears selection chrome.
    private func deleteOverlay(_ overlay: NotePageOverlay, noteId: String) {
        let before = viewModel.makePageSnapshot(store: store)
        if editingOverlayId == overlay.id { editingOverlayId = nil }
        if selectedOverlayId == overlay.id { selectedOverlayId = nil }
        store.removeOverlay(id: overlay.id, from: noteId)
        if let before {
            viewModel.recordPageMutation(before: before, store: store)
        }
        manipulationOverlayId = nil
        manipulationCorner = nil
        isOverlayDragging = false
        if viewModel.activeTool == .imageSelect {
            viewModel.selectTool(.pen)
        }
    }

    /// Duplicates the overlay with a down-right offset; the copy is
    /// appended so it draws in front of the original.
    private func duplicateOverlay(
        _ overlay: NotePageOverlay,
        noteId: String,
        pageSize: CGSize
    ) {
        let before = viewModel.makePageSnapshot(store: store)
        guard let copy = store.duplicateOverlay(
            overlay,
            in: noteId,
            pageSize: pageSize,
            offsetPoints: CGSize(width: 24, height: 24)
        ) else { return }
        if let before {
            viewModel.recordPageMutation(before: before, store: store)
        }
        selectedOverlayId = copy.id
        editingOverlayId = nil
        enterSelectMode(for: copy)
        viewModel.flashStatus("Duplicated")
    }

    /// Single-finger drag on the page while an overlay is selected.
    /// Decides whether the touch landed on a corner handle (resize) or
    /// inside the overlay body (move), then applies the running
    /// translation to the overlay's normalized rect on every frame.
    /// All coords are in BASE (unzoomed) page coordinates and line up
    /// with `pageSize` (the unzoomed logical page size).
    ///
    /// This handler is the UIKit counterpart to what used to be a
    /// SwiftUI `DragGesture` inside `NoteOverlayLayer`. The SwiftUI
    /// gesture lost the gesture race against the outer scroll view's
    /// pan recognizer (the page panned instead of the sticker
    /// moving), so manipulation is now driven entirely by the
    /// scroll-view-level `UIPanGestureRecognizer` and routed back
    /// here.
    private func handleOverlayManipulation(
        phase: OverlayManipulationPhase,
        start: CGPoint,
        translation: CGSize,
        pageSize: CGSize
    ) {
        guard let noteId = viewModel.noteId else { return }
        let overlays = viewModel.currentPageOverlays(store: store)

        switch phase {
        case .began:
            overlayMutationSnapshot = viewModel.makePageSnapshot(store: store)
            // Find the selected overlay; if no selection yet, pick the
            // top-most overlay under the touch and select it. This
            // lets the user grab and drag in one motion without a
            // separate tap-to-select step.
            let activeId: String?
            if let selId = selectedOverlayId,
               overlays.contains(where: { $0.id == selId }) {
                activeId = selId
            } else {
                activeId = topMostOverlay(at: start, in: overlays, pageSize: pageSize)?.id
            }
            guard let id = activeId,
                  let overlay = overlays.first(where: { $0.id == id }) else {
                manipulationOverlayId = nil
                return
            }

            let rect = overlayRect(for: overlay, in: pageSize)
            // Decide between resize (start inside a corner-handle hit
            // zone, ~22 pt around each corner) and move (start
            // anywhere else inside the body). The hit zone slightly
            // overlaps the body but matches what the user sees as
            // "blue circle".
            let corner = cornerHit(at: start, rect: rect)

            // If the touch is OUTSIDE the body AND not on a handle,
            // treat as a deselect tap (handled by canvasTap) — don't
            // start a manipulation.
            if corner == nil && !rect.contains(start) {
                manipulationOverlayId = nil
                return
            }

            if selectedOverlayId != id { selectedOverlayId = id }
            editingOverlayId = nil
            enterSelectMode(for: overlay)
            manipulationOverlayId = id
            manipulationStartRect = rect
            manipulationCorner = corner
            isOverlayDragging = true

        case .changed:
            guard let id = manipulationOverlayId,
                  let overlay = overlays.first(where: { $0.id == id }) else { return }
            let updated = applyTranslation(
                translation,
                to: overlay,
                startRect: manipulationStartRect,
                corner: manipulationCorner,
                pageSize: pageSize
            )
            store.updateOverlay(updated, in: noteId)

        case .ended:
            guard let id = manipulationOverlayId,
                  let overlay = overlays.first(where: { $0.id == id }) else {
                isOverlayDragging = false
                return
            }
            let updated = applyTranslation(
                translation,
                to: overlay,
                startRect: manipulationStartRect,
                corner: manipulationCorner,
                pageSize: pageSize
            )
            store.updateOverlay(updated, in: noteId)
            commitOverlayMutationIfNeeded()
            manipulationOverlayId = nil
            manipulationCorner = nil
            isOverlayDragging = false

        case .cancelled:
            overlayMutationSnapshot = nil
            manipulationOverlayId = nil
            manipulationCorner = nil
            isOverlayDragging = false
        }
    }

    /// Two-finger pinch on a selected image — center-anchored resize
    /// with aspect ratio preserved.
    private func handleOverlayPinchResize(
        phase: OverlayManipulationPhase,
        scale: CGFloat,
        pageSize: CGSize
    ) {
        guard let noteId = viewModel.noteId else { return }
        let overlays = viewModel.currentPageOverlays(store: store)

        switch phase {
        case .began:
            overlayMutationSnapshot = viewModel.makePageSnapshot(store: store)
            guard let selectedId = selectedOverlayId,
                  let overlay = overlays.first(where: { $0.id == selectedId && $0.kind == .image })
            else { return }
            manipulationOverlayId = selectedId
            manipulationStartRect = overlayRect(for: overlay, in: pageSize)
            manipulationCorner = nil
            isOverlayDragging = true

        case .changed:
            guard let id = manipulationOverlayId,
                  let overlay = overlays.first(where: { $0.id == id }) else { return }
            let updated = applyPinchScale(
                scale,
                to: overlay,
                startRect: manipulationStartRect,
                pageSize: pageSize
            )
            store.updateOverlay(updated, in: noteId)

        case .ended:
            guard let id = manipulationOverlayId,
                  let overlay = overlays.first(where: { $0.id == id }) else {
                isOverlayDragging = false
                return
            }
            let updated = applyPinchScale(
                scale,
                to: overlay,
                startRect: manipulationStartRect,
                pageSize: pageSize
            )
            store.updateOverlay(updated, in: noteId)
            commitOverlayMutationIfNeeded()
            manipulationOverlayId = nil
            isOverlayDragging = false

        case .cancelled:
            overlayMutationSnapshot = nil
            manipulationOverlayId = nil
            isOverlayDragging = false
        }
    }

    /// Top-most overlay containing `point`, searched in reverse
    /// (last-added wins) so the sticker the user visually grabbed
    /// is the one returned.
    private func topMostOverlay(
        at point: CGPoint,
        in overlays: [NotePageOverlay],
        pageSize: CGSize
    ) -> NotePageOverlay? {
        for overlay in overlays.reversed() {
            if overlayRect(for: overlay, in: pageSize).contains(point) {
                return overlay
            }
        }
        return nil
    }

    private func overlayRect(for overlay: NotePageOverlay, in pageSize: CGSize) -> CGRect {
        CGRect(
            x: overlay.normX * pageSize.width,
            y: overlay.normY * pageSize.height,
            width: overlay.normW * pageSize.width,
            height: overlay.normH * pageSize.height
        )
    }

    /// Returns which corner-handle hit zone the touch landed in, or
    /// `nil` for "no handle" (i.e. body move). Hit zone is a 36 pt
    /// square centered on each corner — matching the visible handle
    /// area in `NoteOverlayLayer.fourCornerHandles`.
    private func cornerHit(at point: CGPoint, rect: CGRect) -> OverlayResizeCorner? {
        let radius: CGFloat = 22
        let corners: [(OverlayResizeCorner, CGPoint)] = [
            (.topLeading, CGPoint(x: rect.minX, y: rect.minY)),
            (.topTrailing, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeading, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomTrailing, CGPoint(x: rect.maxX, y: rect.maxY))
        ]
        for (corner, center) in corners {
            let dx = point.x - center.x
            let dy = point.y - center.y
            if dx * dx + dy * dy <= radius * radius {
                return corner
            }
        }
        return nil
    }

    /// Applies the running pan translation to either move or resize
    /// the overlay (depending on whether a corner was hit at `.began`).
    /// Image overlays preserve aspect ratio during resize.
    private func applyTranslation(
        _ translation: CGSize,
        to overlay: NotePageOverlay,
        startRect: CGRect,
        corner: OverlayResizeCorner?,
        pageSize: CGSize
    ) -> NotePageOverlay {
        guard pageSize.width > 0, pageSize.height > 0 else { return overlay }
        var rect = startRect
        let minDim: CGFloat = 40

        if let corner {
            switch corner {
            case .topLeading:
                rect.origin.x += translation.width
                rect.origin.y += translation.height
                rect.size.width -= translation.width
                rect.size.height -= translation.height
            case .topTrailing:
                rect.origin.y += translation.height
                rect.size.width += translation.width
                rect.size.height -= translation.height
            case .bottomLeading:
                rect.origin.x += translation.width
                rect.size.width -= translation.width
                rect.size.height += translation.height
            case .bottomTrailing:
                rect.size.width += translation.width
                rect.size.height += translation.height
            }
            rect.size.width = max(minDim, rect.size.width)
            rect.size.height = max(minDim, rect.size.height)

            // Preserve aspect ratio for image overlays so a corner
            // drag doesn't squash the photo.
            if overlay.kind == .image, startRect.width > 0, startRect.height > 0 {
                let aspect = startRect.width / startRect.height
                let prefersWidth = abs(translation.width) >= abs(translation.height)
                let newW: CGFloat
                let newH: CGFloat
                if prefersWidth {
                    newW = rect.size.width
                    newH = newW / aspect
                } else {
                    newH = rect.size.height
                    newW = newH * aspect
                }
                switch corner {
                case .topLeading:
                    rect.origin.x = startRect.maxX - newW
                    rect.origin.y = startRect.maxY - newH
                case .topTrailing:
                    rect.origin.y = startRect.maxY - newH
                case .bottomLeading:
                    rect.origin.x = startRect.maxX - newW
                case .bottomTrailing:
                    break
                }
                rect.size = CGSize(width: newW, height: newH)
            }
        } else {
            rect.origin.x += translation.width
            rect.origin.y += translation.height
        }

        rect.origin.x = max(0, min(pageSize.width - rect.size.width, rect.origin.x))
        rect.origin.y = max(0, min(pageSize.height - rect.size.height, rect.origin.y))

        var updated = overlay
        updated.normX = rect.origin.x / pageSize.width
        updated.normY = rect.origin.y / pageSize.height
        updated.normW = rect.size.width / pageSize.width
        updated.normH = rect.size.height / pageSize.height
        return updated
    }

    /// Center-anchored pinch resize for image overlays.
    private func applyPinchScale(
        _ scale: CGFloat,
        to overlay: NotePageOverlay,
        startRect: CGRect,
        pageSize: CGSize
    ) -> NotePageOverlay {
        guard pageSize.width > 0, pageSize.height > 0 else { return overlay }
        let minDim: CGFloat = 40
        let clampedScale = max(
            minDim / max(startRect.width, 0.0001),
            max(minDim / max(startRect.height, 0.0001), scale)
        )
        let newW = startRect.width * clampedScale
        let newH = startRect.height * clampedScale
        let center = CGPoint(x: startRect.midX, y: startRect.midY)
        var rect = CGRect(
            x: center.x - newW * 0.5,
            y: center.y - newH * 0.5,
            width: newW,
            height: newH
        )
        rect.origin.x = max(0, min(pageSize.width - rect.size.width, rect.origin.x))
        rect.origin.y = max(0, min(pageSize.height - rect.size.height, rect.origin.y))

        var updated = overlay
        updated.normX = rect.origin.x / pageSize.width
        updated.normY = rect.origin.y / pageSize.height
        updated.normW = rect.size.width / pageSize.width
        updated.normH = rect.size.height / pageSize.height
        return updated
    }

    /// Single-finger tap on the page (handled by the outer scroll view so
    /// overlay bodies stay non-interactive and pinch always works).
    private func handlePageFingerTap(at point: CGPoint?, pageSize: CGSize) {
        guard let point else {
            deselectOverlays()
            return
        }

        // Taps on the floating adjust toolbar are handled by its
        // buttons — don't treat them as "tap off to deselect".
        for rect in overlayToolbarExclusionRects(pageSize: pageSize) where rect.contains(point) {
            return
        }

        let overlays = viewModel.currentPageOverlays(store: store)
        for overlay in overlays.reversed() {
            let rect = CGRect(
                x: overlay.normX * pageSize.width,
                y: overlay.normY * pageSize.height,
                width: overlay.normW * pageSize.width,
                height: overlay.normH * pageSize.height
            )
            guard rect.contains(point) else { continue }

            if selectedOverlayId == overlay.id {
                switch overlay.kind {
                case .image, .shape:
                    deselectOverlays()
                case .text:
                    editingOverlayId = overlay.id
                }
            } else {
                selectedOverlayId = overlay.id
                editingOverlayId = nil
                enterSelectMode(for: overlay)
            }
            return
        }
        deselectOverlays()
    }

    private static let pageHorizontalInset: CGFloat = 16
    /// Reserved space above and below the page when fitting at zoom 1.
    private static let pageVerticalInset: CGFloat = 32

    /// Fixed ink supersample factor. The canvas is rendered at this many
    /// times its display resolution so handwriting stays crisp when the page
    /// is zoomed in (the page scales photo-style, no per-zoom re-render).
    /// PencilKit rasterises lazily in tiles, so the cost scales with inked
    /// area, not the full supersampled page.
    ///
    /// Held at 4 (was 5): the drift is governed by the canvas's `1/factor`
    /// transform — at `1/4 = 0.25` PencilKit's live (wet) ink preview stays
    /// put, but at `1/5 = 0.2` (and smaller) it drifts mid-stroke and snaps
    /// back on lift, worse on larger canvases (portrait). 4 keeps the
    /// transform in the drift-free range while preserving high stroke
    /// quality up to 4× zoom.
    private static let pageRenderSupersample: CGFloat = 4.0

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
            // Ink is stored in a width-independent canonical space and scaled
            // to this on-screen page width for display. Report the width so
            // the view model re-derives the live drawing on rotation.
            .onAppear { viewModel.setDisplayPageWidth(logicalPageSize.width) }
            .onChange(of: logicalPageSize.width) { _, width in
                viewModel.setDisplayPageWidth(width)
            }
        }
    }

    @ViewBuilder
    private func canvasPageStack(
        geometry: GeometryProxy,
        logicalPageSize: CGSize,
        scrollContentSize: CGSize,
        rotation: Int
    ) -> some View {
        // The page card is ALWAYS laid out at its base (fit) size. Zoom is
        // applied purely as a transform by `ZoomablePageScrollView`'s native
        // UIScrollView zoom — the whole page (background + ink + overlays)
        // scales together as one rasterized image, exactly like pinching a
        // photo. Nothing is re-laid-out or re-rendered while zooming, so the
        // strokes never flash / regenerate. (Trade-off: like a photo, content
        // is raster-scaled when zoomed past 1×, so it softens at high zoom
        // rather than re-rasterising crisp.)
        let zoomedPageSize = logicalPageSize
        let pageStack = ZStack {
            ZoomablePageScrollView(
                baseContentSize: scrollContentSize,
                maxZoom: 8.0,
                nextSwipeCreatesPage: viewModel.currentPage >= viewModel.totalPages,
                atFirstPage: viewModel.currentPage <= 1,
                blocksPageGestures: hasOverlaySelection,
                contentStamp: pageContentStamp,
                onSwipeNext: { viewModel.goToNextPage() },
                onSwipePrevious: { viewModel.goToPreviousPage() },
                onPageFingerTap: { point in
                    // `point` arrives in BASE (unzoomed) coordinates so
                    // it lines up with `logicalPageSize`.
                    handlePageFingerTap(at: point, pageSize: logicalPageSize)
                },
                onTwoFingerDoubleTap: handleEditorUndo,
                onOverlayManipulation: { phase, start, translation in
                    handleOverlayManipulation(
                        phase: phase,
                        start: start,
                        translation: translation,
                        pageSize: logicalPageSize
                    )
                },
                overlayInteractionExclusionRects: overlayToolbarExclusionRects(
                    pageSize: logicalPageSize
                ),
                overlayAdjustToolbarRect: overlayAdjustToolbarRect(pageSize: logicalPageSize),
                onOverlayAdjustToolbarTap: { button in
                    handleOverlayAdjustToolbarTap(button, pageSize: logicalPageSize)
                },
                overlayPanAcceptsPencil: passesPencilToOverlays,
                overlayPinchTargetRect: selectedImageOverlayRect(pageSize: logicalPageSize),
                onOverlayPinchResize: isImageOverlaySelected
                    ? { phase, scale in
                        handleOverlayPinchResize(
                            phase: phase,
                            scale: scale,
                            pageSize: logicalPageSize
                        )
                    }
                    : nil,
                zoom: $canvasZoom
            ) {
                pageCard(logicalPageSize: zoomedPageSize, rotation: rotation)
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

    /// Bumps when persisted page/overlay data changes — not during live
    /// drawing or undo/redo (those must not remount the page canvas).
    private var pageContentStamp: Int {
        var stamp = 0
        stamp = stamp &* 31 &+ (viewModel.noteId?.hashValue ?? 0)
        stamp = stamp &* 31 &+ viewModel.currentPage
        stamp = stamp &* 31 &+ viewModel.currentPageRotation
        stamp = stamp &* 31 &+ viewModel.currentPageBackground.hashValue
        stamp = stamp &* 31 &+ overlayStoreStamp
        // Folded in so a bump of `canvasLayoutSettleNonce` propagates as
        // a body dependency — that forces the inner `GeometryReader`
        // inside `canvasArea` to re-emit with the settled proposal,
        // which fixes the "page renders tiny / squeezed on first open"
        // race. The stamp going up also lets the scroll view's
        // `updateUIView` refresh its hosted SwiftUI tree against the
        // new content size with no UIView recreation involved (the
        // pinch / zoom recognizers stay alive).
        stamp = stamp &* 31 &+ canvasLayoutSettleNonce
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

    /// Page card: background → stickers (below ink) → strokes → selected
    /// image (above ink while selected).
    @ViewBuilder
    private func pageCard(logicalPageSize: CGSize, rotation: Int) -> some View {
        pageCardChrome(logicalPageSize: logicalPageSize, rotation: rotation) {
            ZStack {
                Color.white
                    .allowsHitTesting(false)
                NotePageBackgroundView(
                    background: viewModel.currentPageBackground,
                    imageData: currentPageBackgroundImageData(),
                    zoomScale: 1
                )
                .allowsHitTesting(false)
                if let noteId = viewModel.noteId {
                    pageOverlayLayer(
                        noteId: noteId,
                        logicalPageSize: logicalPageSize,
                        suppressedOverlayIds: suppressedUnderInkOverlayIds
                    )
                }
                PencilCanvasView(
                    drawing: $viewModel.drawing,
                    drawingPushGeneration: viewModel.drawingPushGeneration,
                    tool: viewModel.pkTool,
                    zoomScale: Self.pageRenderSupersample,
                    drawingPolicy: .pencilOnly,
                    // Keep the canvas in the responder chain for every tool
                    // so finger routing stays consistent — disabling it for
                    // image / text / shape made pinch intermittently stop
                    // working when those tools were active. Fingers are routed
                    // to overlays via `passesFingerTouchesThrough`; Pencil
                    // ink is gated by `canDraw` through the drawing policy.
                    isDrawingEnabled: true,
                    allowsPencilDrawing: viewModel.activeTool.canDraw,
                    passesFingerTouchesThrough: viewModel.activeTool.passesFingerToOverlays,
                    passesPencilTouchesThrough: passesPencilToOverlays,
                    onCanvasReady: { canvas in
                        self.liveCanvas = canvas
                    },
                    onDrawingChanged: { previousDrawing in
                        viewModel.handleLiveDrawingChange(
                            from: previousDrawing,
                            store: store
                        )
                    },
                    onPencilDoubleTap: { interaction in
                        viewModel.handlePencilDoubleTap(interaction: interaction)
                    }
                )
                if let noteId = viewModel.noteId, let image = selectedImageOverlay {
                    pageOverlayLayer(
                        noteId: noteId,
                        logicalPageSize: logicalPageSize,
                        overlays: [image],
                        allowsHitTesting: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func pageOverlayLayer(
        noteId: String,
        logicalPageSize: CGSize,
        overlays: [NotePageOverlay]? = nil,
        suppressedOverlayIds: Set<String> = [],
        allowsHitTesting: Bool = true
    ) -> some View {
        NoteOverlayLayer(
            overlays: overlays ?? viewModel.currentPageOverlays(store: store),
            pageSize: logicalPageSize,
            zoomScale: 1,
            noteId: noteId,
            manipulationMode: allowsOverlayManipulation,
            selectedId: $selectedOverlayId,
            editingId: $editingOverlayId,
            onUpdate: { updated in
                if editingOverlayId == updated.id {
                    store.updateOverlay(updated, in: noteId)
                } else if let before = viewModel.makePageSnapshot(store: store) {
                    store.updateOverlay(updated, in: noteId)
                    viewModel.recordPageMutation(before: before, store: store)
                } else {
                    store.updateOverlay(updated, in: noteId)
                }
            },
            onDelete: { overlay in
                deleteOverlay(overlay, noteId: noteId)
            },
            onDuplicate: { overlay in
                duplicateOverlay(overlay, noteId: noteId, pageSize: logicalPageSize)
            },
            onSelectLasso: {
                viewModel.selectTool(.lasso)
                selectedOverlayId = nil
            },
            onCropImage: { _ in
                viewModel.flashStatus("Crop coming soon")
            },
            onOverlayDragChanged: { dragging in
                isOverlayDragging = dragging
            },
            imageDataProvider: { filename in
                store.loadOverlayImageData(for: noteId, filename: filename)
            },
            suppressedOverlayIds: suppressedOverlayIds
        )
        .allowsHitTesting(allowsHitTesting)
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
                    .allowsHitTesting(false)
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
