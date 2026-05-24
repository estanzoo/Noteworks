//
//  MainTabView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "Home"
    case notebook = "Library"
    case people = "Community"

    var icon: String {
        switch self {
        case .home:     return "Icons/fluent_home-24-regular"
        case .notebook: return "Icons/fluent_notebook-24-regular"
        case .people:   return "Icons/fluent_people-24-regular"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var tutorial: TutorialCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab? = .home
    /// Mirrors the JSX `lastMainPage` (noteworks-library.jsx L9346): the
    /// previous Home/Library/Community tab the user was on before opening
    /// Profile. Profile's back chevron pops back to here instead of
    /// hard-coding `.home`.
    @State private var lastMainTab: AppTab = .home
    @State private var tutorialAnchors: [TutorialTarget: CGRect] = [:]

    private var showsTabLevelTutorialOverlay: Bool {
        guard tutorial.isActive, tutorial.tutorialNoteId == nil else { return false }
        // Popup-layer steps host their own overlay beside the modal target.
        switch tutorial.currentStepId {
        case "community-composer", "community-new-post", "profile-entry", "profile":
            return false
        default:
            return true
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // All four navigation stacks are kept mounted simultaneously
            // (matching the JSX `PageTransition` model at L6831) so:
            //   • per-tab navigation state survives a tab switch
            //   • CourseSpace's notes grid does not have to re-layout from
            //     scratch every time a Home bubble is tapped (the source
            //     of the perceived "lag")
            //   • SwiftUI can cross-fade the layers cleanly via
            //     `.opacity` + `.animation(_, value:)`, instead of
            //     destroying one tree and building another in the same
            //     frame.
            //
            // `allowsHitTesting(false)` on the inactive layers keeps
            // touches from leaking through to hidden screens.
            ZStack {
                tabContainer(.home, isActive: selectedTab == .home) {
                    NavigationStack { HomeView(selectedTab: $selectedTab) }
                }
                tabContainer(.notebook, isActive: selectedTab == .notebook) {
                    NavigationStack { CourseSpaceView(selectedTab: $selectedTab) }
                }
                tabContainer(.people, isActive: selectedTab == .people) {
                    NavigationStack { CommunityView(selectedTab: $selectedTab) }
                }
                tabContainer(nil, isActive: selectedTab == nil) {
                    NavigationStack {
                        ProfileView(
                            selectedTab: $selectedTab,
                            previousTab: lastMainTab
                        )
                    }
                }
            }
            // 0.22s mirrors the JSX `PageTransition` (L6893) which uses
            // `transition: opacity 0.24s cubic-bezier(0.22,0.61,0.36,1)`.
            .animation(.easeInOut(duration: 0.22), value: selectedTab)
            // Remember the last main tab the user was on so Profile's
            // back chevron knows where to return to (same `lastMainPage`
            // pattern the JSX uses at L9688).
            .onChange(of: selectedTab) { _, newValue in
                if let tab = newValue { lastMainTab = tab }
            }

            // Floating Home/Library/Community pill — hidden while the
            // user is inside the note editor so the writing surface gets
            // the entire bottom of the screen back. The slide-down +
            // fade transition matches the cross-fade used for tab
            // switches above.
            if !appState.isImmersiveEditing, !tutorial.isActive {
                FloatingTabBar(selectedTab: $selectedTab)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            TutorialOverlayView(
                coordinator: tutorial,
                firstName: tutorial.firstName(from: appState.profile),
                targetFrames: tutorialAnchors
            )
            .opacity(showsTabLevelTutorialOverlay ? 1 : 0)
            .allowsHitTesting(showsTabLevelTutorialOverlay)
            TutorialSkipConfirmPopup(coordinator: tutorial)
            TutorialCompleteView(
                coordinator: tutorial,
                firstName: tutorial.firstName(from: appState.profile)
            )
        }
        .onPreferenceChange(TutorialAnchorKey.self) { tutorialAnchors = $0 }
        .animation(.easeInOut(duration: 0.22), value: tutorial.isActive)
        .animation(.easeInOut(duration: 0.22), value: tutorial.stepIndex)
        .onAppear {
            tutorial.consumePendingAutoStartIfNeeded()
            applyTutorialNavigation(for: tutorial.currentStep)
        }
        .onChange(of: tutorial.pendingAutoStart) { _, _ in
            tutorial.consumePendingAutoStartIfNeeded()
            applyTutorialNavigation(for: tutorial.currentStep)
        }
        .onChange(of: tutorial.isActive) { _, active in
            if active {
                applyTutorialNavigation(for: tutorial.currentStep)
            } else {
                resetToHomeAfterTutorial()
            }
        }
        .onChange(of: tutorial.showComplete) { _, showing in
            if !showing, !tutorial.isActive {
                resetToHomeAfterTutorial()
            }
        }
        .onChange(of: tutorial.stepIndex) { _, _ in
            applyTutorialNavigation(for: tutorial.currentStep)
        }
        .onChange(of: tutorial.currentStepId) { _, _ in
            applyTutorialNavigation(for: tutorial.currentStep)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { tutorial.tutorialNoteId != nil },
                set: { presented in
                    if !presented { tutorial.tutorialNoteId = nil }
                }
            )
        ) {
            if let noteId = tutorial.tutorialNoteId {
                NoteEditorView(noteId: noteId, isTutorialPresentation: true)
                    .environmentObject(appState)
                    .environmentObject(store)
                    .id("\(noteId)-\(tutorial.stepIndex)")
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Poll the community feed while signed in so User B sees "User A
        // posted …" in the bell on Home without opening the Community tab.
        .task(id: communityPollingTaskId) {
            guard appState.isAuthenticated,
                  !appState.isGuestMode,
                  scenePhase == .active else { return }

            await CommunityNotificationPoller.run(
                notifications: appState.notifications,
                isActive: {
                    appState.isAuthenticated && !appState.isGuestMode
                },
                accessToken: { appState.accessToken },
                currentUserId: { appState.currentUser?.id }
            )
        }
    }

    /// Restarts the poll loop when auth, guest mode, or foreground state changes.
    private var communityPollingTaskId: String {
        let user = appState.currentUser?.id ?? "none"
        return "\(appState.isAuthenticated)-\(appState.isGuestMode)-\(user)-\(scenePhase)"
    }

    private func applyTutorialNavigation(for step: NoteWorksTutorialStep?) {
        guard tutorial.isActive, let step else { return }
        switch step.screen {
        case .home:
            tutorial.tutorialNoteId = nil
            if selectedTab != .home {
                withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .home }
            }
        case .library:
            tutorial.tutorialNoteId = nil
            store.libraryFilter = nil
            if selectedTab != .notebook {
                withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .notebook }
            }
        case .note:
            tutorial.presentTutorialNoteEditor()
        case .community:
            tutorial.tutorialNoteId = nil
            if selectedTab != .people {
                withAnimation(.easeInOut(duration: 0.22)) { selectedTab = .people }
            }
        case .profile:
            tutorial.tutorialNoteId = nil
            if selectedTab != nil {
                withAnimation(.easeInOut(duration: 0.22)) { selectedTab = nil }
            }
        }
    }

    /// After skip or finish, land on Home regardless of which tutorial step was active.
    private func resetToHomeAfterTutorial() {
        tutorial.tutorialNoteId = nil
        if selectedTab != .home {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedTab = .home
            }
        }
        if appState.isImmersiveEditing {
            withAnimation(.easeInOut(duration: 0.22)) {
                appState.isImmersiveEditing = false
            }
        }
    }

    /// Wraps one tab's view tree with cross-fade visibility + hit-testing
    /// gating. Keeping the tree alive when inactive (just invisible)
    /// preserves both per-tab state and child navigation history.
    @ViewBuilder
    private func tabContainer<Content: View>(
        _ tab: AppTab?,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if Self.isRunningInPreview && !isActive {
            // SwiftUI Previews have a 5-second render budget; mounting all
            // four NavigationStacks at once routinely blows past it. In
            // the real app every tab stays mounted so state survives a
            // tab switch — preview only ever needs the active one.
            Color.clear
        } else {
            content()
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
        }
    }

    private static let isRunningInPreview: Bool =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab?

    // Shared namespace for the matchedGeometryEffect that drives the
    // selected-pill slide between tabs. Without this each tab renders a
    // separate highlight that cross-fades in place — no slide.
    @Namespace private var pillNamespace

    // Selected highlight: hsba(0, 0%, 93%, 1), Plus Darker blend on the
    // legacy bar; on iOS 26 it's a tinted Liquid Glass capsule.
    private let highlightColor = Color(white: 0.93)

    var body: some View {
        GeometryReader { geo in
            // Scale bar width relative to screen: 290 / 390 ≈ 74% of screen width,
            // clamped so it never gets too wide on large iPads or too narrow on small ones.
            let barWidth = min(max(geo.size.width * 0.38, 280), 360)

            tabRow
                .frame(width: barWidth, height: 62)
                .modifier(FloatingTabBarBackground())
                // Center horizontally, pin to bottom with safe-area padding
                .position(x: geo.size.width / 2, y: geo.size.height - 20 - 31) // 31 = half bar height
        }
        .frame(height: 62 + 20 + 34) // bar + bottom gap + safe area estimate
    }

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabItemButton(
                    tab: tab,
                    selectedTab: $selectedTab,
                    highlightColor: highlightColor,
                    pillNamespace: pillNamespace
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Renders the bar's translucent backdrop. On iOS 26+ this uses Apple's
/// real Liquid Glass material (`.glassEffect(_:in:)`), which gives the
/// bar live refraction over the Home/CourseSpace content underneath plus
/// the press-morph response. On earlier OSes we fall back to the layered
/// color-dodge background that's been shipping since the first cut.
private struct FloatingTabBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                // Liquid Glass handles its own clipping/shape; no extra
                // .clipShape needed. `.interactive()` enables the
                // press/morph response when a tab is tapped.
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background {
                    ZStack {
                        Color(white: 0.20)
                        Color(white: 1.00).opacity(0.5).blendMode(.colorDodge)
                        Color(white: 0.97).blendMode(.colorDodge)
                    }
                }
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        }
    }
}

// MARK: - Individual Tab Button

struct TabItemButton: View {
    let tab: AppTab
    @Binding var selectedTab: AppTab?
    let highlightColor: Color
    let pillNamespace: Namespace.ID

    private var isSelected: Bool { selectedTab == tab }

    /// Stable matchedGeometryEffect id so the same pill view follows the
    /// selection from tab to tab (instead of fading in/out at fixed slots).
    private static let pillID = "selectedTabPill"

    var body: some View {
        Button {
            // Snappy spring so the highlight reads as "liquid" — slides
            // and gently overshoots into the next slot, matching the
            // stock iOS 26 tab bar feel. Wrapping selection in
            // `withAnimation` is what actually drives
            // `matchedGeometryEffect` to interpolate position/size.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                if isSelected {
                    selectedHighlight
                        .matchedGeometryEffect(
                            id: Self.pillID,
                            in: pillNamespace,
                            properties: .frame,
                            isSource: true
                        )
                        .frame(width: 102, height: 54)
                }

                VStack(spacing: 4) {
                    Image(tab.icon)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)

                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(-0.1)
                        .lineLimit(1)
                }
                .foregroundStyle(unselectedAwareLabelColor)
                // Label color cross-fades; do NOT animate it from the
                // pill spring, otherwise the icon flashes mid-slide.
                .animation(.easeInOut(duration: 0.18), value: isSelected)
            }
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Selected-tab pill. iOS 26 uses a tinted Liquid Glass capsule that
    /// merges with the bar's backdrop; older OSes keep the original
    /// `plusDarker` blend + white rim treatment.
    @ViewBuilder
    private var selectedHighlight: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(highlightColor.opacity(0.55)).interactive(),
                    in: .capsule
                )
        } else {
            RoundedRectangle(cornerRadius: 100)
                .fill(highlightColor.blendMode(.plusDarker))
                .overlay {
                    RoundedRectangle(cornerRadius: 100)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.9),
                                    .white.opacity(0.4),
                                    .white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
    }

    /// Liquid Glass renders icons over a translucent backdrop, so the
    /// legacy `secondary.opacity(0.5)` unselected color was washing out
    /// against light Home content. Bump opacity on iOS 26 only — keeping
    /// the legacy look bit-for-bit identical on the dodge-blend bar.
    private var unselectedAwareLabelColor: Color {
        if isSelected { return .primary }
        if #available(iOS 26.0, *) {
            return Color.primary.opacity(0.7)
        }
        return Color.secondary.opacity(0.5)
    }
}

#Preview {
    let notesStore = NotesStore.preview()
    let appState = AppState(notesStore: notesStore)
    return MainTabView()
        .environmentObject(appState)
        .environmentObject(notesStore)
        .environmentObject(appState.tutorialCoordinator)
}

