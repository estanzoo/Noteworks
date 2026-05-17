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

    @State private var bubblesVisible = false
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var fabOpen = false
    @State private var bubbleEditorMode: BubbleEditorMode? = nil
    @State private var newNoteRoute: NewNoteRoute? = nil

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
            .padding(.trailing, 16)
            .padding(.bottom, 84)
        }
        .overlay { notificationOverlay }
        .overlay { searchOverlay }
        .overlay { bubbleEditorOverlay }
        .navigationBarHidden(true)
        .navigationDestination(item: $newNoteRoute) { route in
            NoteEditorView(noteId: route.noteId)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                bubblesVisible = true
            }
        }
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
        let note = store.createDraftNote(subject: nil)
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
                onSubmit: { name in
                    switch mode {
                    case .create:
                        if let error = store.addBubble(name: name) {
                            return .failure(message: error)
                        }
                        resolveBubbleCourse(name)
                    case .rename(let original):
                        if let error = store.renameBubble(from: original, to: name) {
                            return .failure(message: error)
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
            // (phone, iPad, split-view, rotation all just work).
            let bubbles = HomeBubbleLayout.bubbles(from: store, in: geo.size)
            ZStack {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, course in
                    Button {
                        // Set the filter first so CourseSpaceView's
                        // `onChange(of: store.libraryFilter)` (it now
                        // reacts even when not visible) adopts the
                        // bubble. The tab cross-fade is owned by
                        // MainTabView's `.animation(_, value:)` modifier
                        // — a `withAnimation` here would conflict.
                        store.libraryFilter = course.name
                        resolveBubbleCourse(course.name)
                        selectedTab = .notebook
                    } label: {
                        BubbleView(course: course)
                    }
                    .buttonStyle(BubblePressStyle())
                    .position(
                        x: geo.size.width / 2 + course.offsetX * geo.size.width,
                        y: geo.size.height / 2 + course.offsetY * geo.size.height
                    )
                    .scaleEffect(bubblesVisible ? 1 : 0.6)
                    .opacity(bubblesVisible ? 1 : 0)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.6)
                            .delay(Double(index) * 0.08),
                        value: bubblesVisible
                    )
                }
            }
        }
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

#Preview {
    let store = NotesStore.preview()
    NavigationStack {
        HomeView(selectedTab: .constant(AppTab.home))
            .environmentObject(AppState(notesStore: store))
            .environmentObject(store)
    }
}
