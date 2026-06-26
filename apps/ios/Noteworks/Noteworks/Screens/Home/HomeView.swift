//
//  HomeView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

// MARK: - HomeView

/// Identifiable route used to push the canvas onto the Home navigation stack
/// when "Note" is tapped in the FAB.
struct NewNoteRoute: Hashable, Identifiable {
    let id: UUID
    let noteId: String?

    init(noteId: String? = nil) {
        self.id = UUID()
        self.noteId = noteId
    }
}

struct HomeView: View {
    @Binding var selectedTab: AppTab?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NotesStore

    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var fabOpen = false
    @State private var bubbleEditorMode: BubbleEditorMode? = nil
    @State private var newNoteRoute: NewNoteRoute? = nil

    // Edit mode = "jiggle mode" mirroring the iOS Home Screen. Long-pressing
    // a bubble surfaces a context menu; choosing "Move Bubbles" flips
    // `isEditingLayout` to true, the bubbles wiggle, and any of them can
    // be dragged. Manual positions persist on `NotesStore` so they survive
    // app launches.
    @State private var isEditingLayout = false
    @State private var pendingDeleteName: String? = nil
    /// Fallback spotlight for the `home-bubbles` tutorial step when Untitled
    /// Bubble is not on Home — picked once per visit to that step.
    @State private var tutorialBubbleHighlightName: String? = nil

    private var unreadCount: Int { appState.notifications.unreadCount }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OnboardingBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HomeBadgePill()
                    .padding(.top, 24)
                    .padding(.leading, 32)
                    .padding(.bottom, 12)

                titleRow
                // `store.isReady` guards against a half-rendered Home in the
                // window between sign-out (notesStore.deactivate) and
                // sign-in (notesStore.activate) on the same device.
                if store.isReady {
                    bubbleField
                        // Reserve room for the FloatingTabBar (62 bar + 20
                        // gap + 34 safe-area estimate ≈ 116pt) so bubbles
                        // never get placed under the nav pill.
                        .padding(.bottom, 120)
                } else {
                    homeNotReadyPlaceholder
                }
            }

            // Tap-to-close backdrop while the FAB menu is open
            // (mirrors JSX L1522: full-screen pointerdown listener).
            if fabOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.24)) {
                            fabOpen = false
                        }
                    }
                    .transition(.opacity)
            }

            HomeFAB(
                isOpen: $fabOpen,
                onAddBubble: handleAddBubble,
                onAddNote: handleAddNote
            )
            .tutorialHighlight(.homeFAB, activeTarget: appState.tutorialCoordinator.activeTarget)
            .padding(.trailing, 16)
            .padding(.bottom, 84)
        }
        // Pin the entire Home surface against the software keyboard. When the
        // BubbleEditorDialog (or any other text-input overlay) opens, SwiftUI's
        // default keyboard avoidance would otherwise shrink the bubbleField's
        // GeometryReader and reflow every bubble. The dialog itself sits in
        // its own overlay, so the title bar / bubbles behind it should stay
        // exactly where they were — mirroring how the note-editor chrome
        // ignores the keyboard while the title field is being edited.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay { notificationOverlay }
        .overlay { searchOverlay }
        .overlay { bubbleEditorOverlay }
        .navigationBarHidden(true)
        .navigationDestination(item: $newNoteRoute) { route in
            NoteEditorView(noteId: route.noteId)
        }
        .confirmationDialog(
            "Delete this bubble?",
            isPresented: Binding(
                get: { pendingDeleteName != nil },
                set: { if !$0 { pendingDeleteName = nil } }
            ),
            presenting: pendingDeleteName,
            actions: { name in
                Button("Delete \"\(name)\"", role: .destructive) {
                    handleConfirmedDelete(name)
                    pendingDeleteName = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteName = nil
                }
            },
            message: { _ in
                Text("Notes in this bubble will move to Untitled Bubble.")
            }
        )
        .onAppear {
            // The onboarding flow can finish while a TextField is still the
            // first responder (e.g. the courses step's input). Without this,
            // ContentView swaps in MainTabView while the keyboard is still
            // animating away, leaving a half-second of "Home behind a
            // keyboard" — the messy display the user reported.
            dismissKeyboard()
            assignTutorialBubbleHighlightIfNeeded()
        }
        .onChange(of: appState.tutorialCoordinator.currentStepId) { _, _ in
            assignTutorialBubbleHighlightIfNeeded()
        }
        .onChange(of: appState.tutorialCoordinator.isActive) { _, active in
            if !active {
                tutorialBubbleHighlightName = nil
            } else {
                assignTutorialBubbleHighlightIfNeeded()
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    // MARK: - FAB actions

    /// Mirrors `setEditorState({ mode: "create" })` (JSX L1529) — opens the
    /// BubbleEditorDialog so the user can name and create a new bubble. The
    /// dialog routes the trimmed value through `store.addBubble`.
    private func handleAddBubble() {
        withAnimation(.easeOut(duration: 0.2)) {
            bubbleEditorMode = .create
        }
    }

    /// Mirrors `onCreateNote?.()` (JSX L1567) — creates a fresh draft note in
    /// the store and pushes the canvas onto the current navigation stack.
    private func handleAddNote() {
        let note = store.createDraftNote()
        newNoteRoute = NewNoteRoute(noteId: note.id)
    }

    // MARK: - Bubble editor overlay

    @ViewBuilder
    private var bubbleEditorOverlay: some View {
        if let mode = bubbleEditorMode {
            BubbleEditorDialog(
                isPresented: Binding(
                    get: { bubbleEditorMode != nil },
                    set: { if !$0 { bubbleEditorMode = nil } }
                ),
                mode: mode,
                defaultDisplayMode: .code,
                onSubmit: { name, courseDraft, displayMode in
                    switch mode {
                    case .create:
                        guard let courseDraft, let displayMode else {
                            return .failure(message: "Enter a course name.")
                        }
                        var mutationError: String?
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            mutationError = store.addCourseBubble(draft: courseDraft, displayMode: displayMode)
                        }
                        if let mutationError {
                            return .failure(message: mutationError)
                        }
                        let normalized = courseDraft.normalized()
                        if let label = normalized.bubbleLabel(for: displayMode) {
                            resolveBubbleCourse(NotesStore.normalizeBubbleName(label))
                        }
                    case .rename(let original):
                        var mutationError: String?
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            mutationError = store.renameBubble(from: original, to: name)
                        }
                        if let mutationError {
                            return .failure(message: mutationError)
                        }
                        resolveBubbleCourse(name)
                    }
                    return .success
                }
            )
            .transition(.opacity)
            .zIndex(110)
        }
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack(alignment: .center) {
            // Matches noteworks-library.jsx L2260: SF Pro (system) 40pt
            // / 700, -0.02em tracking. The web mock has no "BUBBLES OF
            // THOUGHT" subtitle, so neither does Home.
            Text("NoteWorks")
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.02 * 40)
                .foregroundStyle(HomeTheme.textPrimary)

            Spacer()

            HStack(spacing: 10) {
                HomeGlassIconButton(icon: "Icons/fluent_search-24-regular") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showSearch = true
                    }
                }

                ZStack(alignment: .topTrailing) {
                    HomeGlassIconButton(
                        icon: "Icons/fluent_alert-24-regular",
                        isActive: showNotifications
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNotifications.toggle()
                        }
                    }

                    if unreadCount > 0 && !showNotifications {
                        Text("\(unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(HomeTheme.accent)
                            .clipShape(Circle())
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                            }
                            .offset(x: 4, y: -4)
                            .allowsHitTesting(false)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                AppAvatarTopBarButton(
                    name: appState.profile?.displayName ?? "",
                    avatarUrl: appState.profile?.avatarUrl
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = nil
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    // MARK: - Placeholder while the store has no active user

    private var homeNotReadyPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.primary.opacity(0.5))
            Text("Loading your library…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bubble Field

    private var bubbleField: some View {
        GeometryReader { geo in
            // Recompute the layout against the live container size so
            // the packer can guarantee no overlap on this exact canvas
            // (iPhone, iPad, split-view, rotation all just work).
            let bubbles = HomeBubbleLayout.bubbles(from: store, in: geo.size)
            ZStack {
                // Tap-out backdrop: when in edit mode, tapping any empty
                // area exits jiggle mode (mirrors the iPadOS Home Screen
                // gesture). zIndex(-1) keeps bubbles on top.
                if isEditingLayout {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isEditingLayout = false
                            }
                        }
                        .zIndex(-1)
                }

                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, course in
                    let isUntitledBubble = course.name.caseInsensitiveCompare(NotesStore.initialGuestBubbleName) == .orderedSame
                    let isTutorialTarget = tutorialHighlightBubbleName(in: bubbles)
                        .map { course.name.caseInsensitiveCompare($0) == .orderedSame } ?? false
                    HomeBubbleCell(
                        course: course,
                        siblings: bubbles.filter { $0.id != course.id },
                        index: index,
                        geometry: geo.size,
                        isEditing: isEditingLayout,
                        hasManualOffset: store.bubble(named: course.name)?.manualOffsetX != nil,
                        isReservedName: Self.isReservedBubbleName(course.name),
                        canDelete: course.name.caseInsensitiveCompare(NotesStore.initialGuestBubbleName) != .orderedSame,
                        isTutorialTarget: isTutorialTarget,
                        onTap: { handleBubbleTap(course.name, isUntitledBubble: isUntitledBubble) },
                        onRename: { handleRenameBubble(course.name) },
                        onMoveAll: { handleEnterEditMode() },
                        onResetPosition: { handleResetPosition(course.name) },
                        onDelete: { pendingDeleteName = course.name },
                        onCommitDrag: { fx, fy in
                            store.setBubbleManualOffset(name: course.name, offsetX: fx, offsetY: fy)
                        }
                    )
                }

                // "Done" pill — discoverable exit from jiggle mode.
                // Pinned top-trailing inside the field so it never sits
                // under the FloatingTabBar or the FAB.
                if isEditingLayout {
                    VStack {
                        HStack {
                            Spacer()
                            doneEditingPill
                                .padding(.top, 8)
                                .padding(.trailing, 16)
                        }
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                    .zIndex(20)
                }
            }
        }
    }

    private var doneEditingPill: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isEditingLayout = false
            }
        } label: {
            Text("Done")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HomeTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.55))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(HomeTheme.accent.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tutorial bubble spotlight

    private func tutorialHighlightBubbleName(in bubbles: [CourseBubble]) -> String? {
        guard appState.tutorialCoordinator.isActive,
              appState.tutorialCoordinator.currentStepId == "home-bubbles" else { return nil }
        if bubbles.contains(where: {
            $0.name.caseInsensitiveCompare(NotesStore.initialGuestBubbleName) == .orderedSame
        }) {
            return NotesStore.initialGuestBubbleName
        }
        return tutorialBubbleHighlightName
    }

    private func assignTutorialBubbleHighlightIfNeeded() {
        guard appState.tutorialCoordinator.isActive,
              appState.tutorialCoordinator.currentStepId == "home-bubbles" else {
            tutorialBubbleHighlightName = nil
            return
        }
        if store.bubbleNames.contains(where: {
            $0.caseInsensitiveCompare(NotesStore.initialGuestBubbleName) == .orderedSame
        }) {
            tutorialBubbleHighlightName = nil
            return
        }
        guard tutorialBubbleHighlightName == nil else { return }
        tutorialBubbleHighlightName = store.bubbleNames.randomElement()
    }

    // MARK: - Bubble actions

    private func handleBubbleTap(_ name: String, isUntitledBubble: Bool = false) {
        // Set the filter first so CourseSpaceView's `onChange(of:
        // store.libraryFilter)` (it now reacts even when not visible)
        // adopts the bubble. The tab cross-fade is owned by MainTabView's
        // `.animation(_, value:)` modifier — a `withAnimation` here would
        // conflict.
        store.libraryFilter = name
        resolveBubbleCourse(name)
        selectedTab = .notebook
    }

    private func handleRenameBubble(_ name: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            bubbleEditorMode = .rename(originalName: name)
        }
    }

    private func handleEnterEditMode() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isEditingLayout = true
        }
    }

    private func handleResetPosition(_ name: String) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            store.clearBubbleManualOffset(name: name)
        }
    }

    private func handleConfirmedDelete(_ name: String) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            store.deleteBubble(name: name)
        }
    }

    /// Legacy virtual bucket labels that should never appear as editable
    /// bubbles on Home (`Unnamed`, `Uncategorized`).
    private static func isReservedBubbleName(_ name: String) -> Bool {
        NotesStore.isLegacyOrphanSubject(name)
    }

    private func resolveBubbleCourse(_ name: String) {
        guard let accessToken = appState.accessToken, !accessToken.isEmpty else { return }
        let bubble = store.bubble(named: name)
        guard bubble?.courseId == nil else { return }
        Task {
            do {
                let response = try await CourseResolutionService.shared.resolveCourse(
                    code: bubble?.courseCode ?? name,
                    name: name,
                    accessToken: accessToken
                )
                await MainActor.run {
                    store.setCourseMetadata(
                        forBubbleNamed: name,
                        courseId: response.id,
                        courseCode: response.code
                    )
                }
            } catch {
                #if DEBUG
                print("[CourseResolution] Failed to resolve bubble '\(name)': \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Search Overlay

    @ViewBuilder
    private var searchOverlay: some View {
        if showSearch {
            SearchPopupView(
                isPresented: $showSearch,
                onSelectCommunityPost: { post in
                    // Hand the post off to `CommunityView` and jump to
                    // the Community tab so the detail popup opens
                    // inside its native screen (where comments, likes,
                    // and the post detail flow already live).
                    appState.pendingCommunityPost = post
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedTab = .people
                    }
                },
                onSelectLocalNote: { note in
                    // Push the editor onto Home's nav stack. We reuse
                    // `newNoteRoute` (already wired for the FAB) so the
                    // existing `navigationDestination(item:)` handles the
                    // push without a second destination.
                    newNoteRoute = NewNoteRoute(noteId: note.id)
                }
            )
                .transition(.opacity)
                .zIndex(100)
        }
    }

    // MARK: - Notification Overlay

    @ViewBuilder
    private var notificationOverlay: some View {
        if showNotifications {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNotifications = false
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    NotificationDropdown(
                        store: appState.notifications,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showNotifications = false
                            }
                        }
                    )
                }
                .padding(.top, 130)
                .padding(.trailing, 32)
                Spacer()
            }
            .transition(.opacity)
            .zIndex(50)
        }
    }
}

// MARK: - HomeBubbleCell
//
// One bubble inside the `bubbleField` ZStack. Wraps the existing
// `BubbleView` with:
//
// - A `Button` + `.contextMenu` in normal mode (long-press surfaces
//   Rename / Move / Reset Position / Delete, mirroring the iOS Home
//   Screen pattern).
// - A `DragGesture` in edit mode, with a subtle sine-wave jiggle
//   (`TimelineView` + `rotationEffect`) that survives layout re-renders.
// - A lifted scale + zIndex while it's the actively dragged bubble.
// - Spring animations on position so reset / re-sort / drag-commit all
//   tween into place rather than snap.
//
// The cell is intentionally dumb — every side effect is a closure owned
// by `HomeView`, so this struct can stay private to the file and
// participate in #Preview without dragging extra dependencies in.
private struct HomeBubbleCell: View {
    @EnvironmentObject private var appState: AppState
    let course: CourseBubble
    /// Every other rendered bubble, used on drag release to push this
    /// bubble out of any overlap into the nearest free space.
    var siblings: [CourseBubble] = []
    let index: Int
    let geometry: CGSize
    let isEditing: Bool
    let hasManualOffset: Bool
    let isReservedName: Bool
    let canDelete: Bool
    var isTutorialTarget: Bool = false

    let onTap: () -> Void
    let onRename: () -> Void
    let onMoveAll: () -> Void
    let onResetPosition: () -> Void
    let onDelete: () -> Void
    let onCommitDrag: (Double, Double) -> Void

    // Per-frame drag delta stays local so HomeView doesn't re-layout
    // every sibling on each finger move (that killed their wiggle anim).
    @State private var dragOffset: CGSize = .zero
    @State private var isLocalDragging: Bool = false

    private static let wiggleAngle: Double = 1.4

    private var isDraggingThisBubble: Bool { isLocalDragging || dragOffset != .zero }

    /// Only the bubble under the finger stops wiggling; siblings keep
    /// jiggling while edit mode stays active.
    private var wiggleActive: Bool { isEditing && !isDraggingThisBubble }

    /// Per-bubble period so the cluster desynchronises after a few seconds.
    private var wiggleDuration: Double {
        0.13 + Double(index % 5) * 0.012
    }

    /// Sine-wave jiggle angle for `date`. Time-based so parent re-renders
    /// (layout recompute, drag commit) never cancel a `repeatForever`.
    private func wiggleAngle(at date: Date) -> Double {
        guard wiggleActive else { return 0 }
        let phaseOffset = Double(index) * 0.09
        let t = date.timeIntervalSinceReferenceDate + phaseOffset
        return Self.wiggleAngle * sin(t * .pi * 2 / wiggleDuration)
    }

    private var baseCenter: CGPoint {
        CGPoint(
            x: geometry.width / 2 + course.offsetX * geometry.width,
            y: geometry.height / 2 + course.offsetY * geometry.height
        )
    }

    var body: some View {
        interactiveBubble
            // Pin layout to the bubble's unscaled diameter so the lift
            // scale is purely visual and never shrinks finger travel.
            .frame(width: course.size, height: course.size)
            .position(
                x: baseCenter.x + dragOffset.width,
                y: baseCenter.y + dragOffset.height
            )
            .animation(nil, value: dragOffset)
            .gesture(isEditing ? dragGesture : nil)
            .zIndex(isDraggingThisBubble ? 10 : 0)
            // Do not attach implicit position animations here. A spring on
            // `course.offsetX` / `offsetY` also runs when the tab layer
            // cross-fades back in and `GeometryReader` delivers a slightly
            // different size — every bubble "settles" downward. Moves that
            // should animate (drag commit, reset, delete, add/rename) already
            // wrap their `NotesStore` mutations in `withAnimation` on the
            // Home side or inside the drag gesture.
    }

    private var bubbleVisuals: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !wiggleActive)) { timeline in
            BubbleView(course: course)
                .contentShape(Circle())
                .rotationEffect(.degrees(wiggleAngle(at: timeline.date)))
        }
        .scaleEffect(isDraggingThisBubble ? 1.05 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isDraggingThisBubble)
        .shadow(
            color: isDraggingThisBubble ? .black.opacity(0.18) : .clear,
            radius: isDraggingThisBubble ? 18 : 0,
            x: 0,
            y: isDraggingThisBubble ? 10 : 0
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isDraggingThisBubble)
    }

    @ViewBuilder
    private var interactiveBubble: some View {
        if isEditing {
            bubbleVisuals
        } else {
            Button(action: onTap) {
                BubbleView(course: course)
                    // Without this, iPadOS draws its automatic pointer
                    // hover effect as a rounded-rectangle around the
                    // Button's bounding box — looks like a "double
                    // circle" rim sitting just outside the real bubble.
                    // Pinning the shape to a circle makes the hover
                    // (and hit testing) match the bubble itself.
                    .contentShape(Circle())
                    .hoverEffect(.lift)
                    .if(isTutorialTarget) { view in
                        view
                            .tutorialAnchor(.homeBubble)
                            .tutorialHighlight(.homeBubble, activeTarget: appState.tutorialCoordinator.activeTarget)
                    }
            }
            .buttonStyle(BubblePressStyle())
            .focusEffectDisabled()
            .contextMenu {
                if !isReservedName {
                    Button {
                        onRename()
                    } label: {
                        Label("Rename Bubble", systemImage: "pencil")
                    }
                    Button {
                        onMoveAll()
                    } label: {
                        Label("Move Bubbles", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    }
                    if hasManualOffset {
                        Button {
                            onResetPosition()
                        } label: {
                            Label("Reset Position", systemImage: "arrow.uturn.backward")
                        }
                    }
                    if canDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete Bubble", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func clampedDragOffset(for translation: CGSize) -> CGSize {
        let base = baseCenter
        let r = course.size / 2
        // Clamp only to the container so the bubble never disappears
        // off-screen. Overlap is resolved on release via `onCommitDrag`.
        let targetX = min(geometry.width - r, max(r, base.x + translation.width))
        let targetY = min(geometry.height - r, max(r, base.y + translation.height))
        return CGSize(width: targetX - base.x, height: targetY - base.y)
    }

    private var dragGesture: some Gesture {
        // `minimumDistance: 1` keeps the drag snappy (finger barely
        // moves before the bubble tracks) while still ignoring perfect
        // taps. Pure taps stay no-ops because the cell isn't a Button
        // in edit mode — there's nothing for a tap to trigger.
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                var txn = Transaction()
                txn.disablesAnimations = true
                withTransaction(txn) {
                    if !isLocalDragging { isLocalDragging = true }
                    dragOffset = clampedDragOffset(for: value.translation)
                }
            }
            .onEnded { value in
                let clamped = clampedDragOffset(for: value.translation)
                // Where the finger let go (clamped to the screen edges).
                let requestedCenter = CGPoint(
                    x: baseCenter.x + clamped.width,
                    y: baseCenter.y + clamped.height
                )
                // Push out of any overlap with the other bubbles into the
                // nearest free spot, mirroring the iOS Home Screen: drag is
                // smooth, but on release the bubble self-corrects so two
                // bubbles never stay overlapping.
                let resolvedCenter = HomeBubbleLayout.resolveDragPosition(
                    requestedCenter: requestedCenter,
                    radius: course.size / 2,
                    siblings: siblings,
                    in: geometry
                )

                let requestedOffsetX = Double((requestedCenter.x - geometry.width / 2) / max(geometry.width, 1))
                let requestedOffsetY = Double((requestedCenter.y - geometry.height / 2) / max(geometry.height, 1))
                let resolvedOffsetX = Double((resolvedCenter.x - geometry.width / 2) / max(geometry.width, 1))
                let resolvedOffsetY = Double((resolvedCenter.y - geometry.height / 2) / max(geometry.height, 1))

                let needsCorrection =
                    abs(resolvedCenter.x - requestedCenter.x) > 0.5 ||
                    abs(resolvedCenter.y - requestedCenter.y) > 0.5

                // Step 1: pin the bubble exactly where the finger released
                // (no animation) so `baseCenter` matches the drop point and
                // `dragOffset` can return to zero without a snap-back.
                var txn = Transaction()
                txn.disablesAnimations = true
                withTransaction(txn) {
                    onCommitDrag(requestedOffsetX, requestedOffsetY)
                    dragOffset = .zero
                    isLocalDragging = false
                }

                // Step 2: if the drop overlapped a neighbour, spring to the
                // resolved free spot on the next run-loop tick. Deferring
                // lets step 1 render first (bubble pinned at the drop point,
                // no snap-back) so this transition animates cleanly instead
                // of being merged into step 1's non-animated transaction.
                // `dragOffset` stays at zero so the `.animation(nil, value:
                // dragOffset)` guard doesn't cancel the move — only
                // `baseCenter` (driven by the store) shifts.
                if needsCorrection {
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                            onCommitDrag(resolvedOffsetX, resolvedOffsetY)
                        }
                    }
                }
            }
    }
}

#Preview {
    let store = NotesStore.preview()
    NavigationStack {
        HomeView(selectedTab: .constant(AppTab.home))
            .environmentObject(AppState(notesStore: store))
            .environmentObject(store)
    }
}
