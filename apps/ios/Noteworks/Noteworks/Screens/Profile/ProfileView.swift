//
//  ProfileView.swift
//  Noteworks
//
//  Root of the Profile screen. Mirrors the `ProfilePage` return in
//  others/noteworks-library(2).jsx L6475–L6618: BETA badge + title row
//  with TopBar icons, hero GlassCard, then a GlassCard containing the
//  sidebar nav + detail panel with a fade/slide transition, plus the
//  email and feedback popups.
//

import SwiftUI

struct ProfileView: View {
    @Binding var selectedTab: AppTab?
    /// Tab to return to when the user taps the back chevron. Driven by
    /// `MainTabView.lastMainTab` so we mirror the JSX `lastMainPage`
    /// behaviour (noteworks-library.jsx L9346 / L10827).
    var previousTab: AppTab = .home
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ProfileViewModel()
    @StateObject private var schoolSearch = SchoolSearchService()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showSearch: Bool = false
    @State private var showNotifications: Bool = false
    /// Note id pushed onto the Profile nav stack when the user picks a
    /// note from the search popup. `nil` means "no editor on screen".
    @State private var searchedNoteId: String?

    private var unreadCount: Int { appState.notifications.unreadCount }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerBlock
                    ProfileHeroCard(viewModel: viewModel)
                    settingsCard
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 140)
                .frame(maxWidth: 1140)
                .frame(maxWidth: .infinity)
            }

            EmailVerificationPopup(viewModel: viewModel)
                .animation(.easeOut(duration: 0.18), value: viewModel.editingEmail)

            PasswordChangePopup(viewModel: viewModel)
                .animation(.easeOut(duration: 0.18), value: viewModel.editingPassword)

            FeedbackThanksPopup(viewModel: viewModel)
                .animation(.easeOut(duration: 0.18), value: viewModel.feedbackPopup.open)

            aboutYouPopups
        }
        .overlay { notificationsOverlay }
        .overlay { searchOverlay }
        .navigationDestination(item: $searchedNoteId) { noteId in
            NoteEditorView(noteId: noteId)
        }
        .navigationBarHidden(true)
        .onChange(of: viewModel.profile) { _, _ in
            viewModel.syncAboutDraftFromProfile()
        }
        .onAppear {
            viewModel.applyCredits(from: appState.creditsStore)
            if let userProfile = appState.profile {
                viewModel.hydrate(from: userProfile)
            }
            schoolSearch.prefetchAll(accessToken: appState.accessToken)
        }
        .onChange(of: appState.profile) { _, newValue in
            if let newValue {
                viewModel.hydrate(from: newValue)
            }
        }
        .onChange(of: appState.creditsStore.accountRevision) { _, _ in
            viewModel.applyCredits(from: appState.creditsStore)
        }
        .onChange(of: appState.accessToken) { _, token in
            schoolSearch.prefetchAll(accessToken: token)
        }
        .fullScreenCover(isPresented: $viewModel.courseEditorOpen) {
            ProfileCourseEditorSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var aboutYouPopups: some View {
        if let field = viewModel.profileTextEditor {
            ProfileTextEditPopup(
                field: field,
                value: $viewModel.profileTextEditorValue,
                onClose: { viewModel.closeProfileTextEditor() },
                onSave: { viewModel.saveProfileTextEditor() }
            )
            .transition(.opacity)
        }

        if viewModel.schoolEditorOpen {
            ProfileSchoolSearchPopup(viewModel: viewModel, searchService: schoolSearch)
                .transition(.opacity)
        }

        if viewModel.gradeEditorOpen {
            ProfileGradeSelectPopup(viewModel: viewModel)
                .transition(.opacity)
        }
    }

    // MARK: - Header (BETA badge + title + TopBar icons)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileBadgePill()

            HStack(alignment: .top, spacing: 16) {
                // Back chevron — mirrors the GlassIconBtn rendered at
                // noteworks-library.jsx L8913 immediately left of the
                // "Profile" title. Returns to whichever main tab the
                // user came from.
                ProfileGlassIconButton(systemName: "chevron.left") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = previousTab
                    }
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile")
                        .font(.system(size: 36, weight: .bold))
                        .tracking(-0.02 * 36)
                        .foregroundStyle(ProfileTheme.textPrimary)

                    Text("Personal settings, billing, credits, security, and account preferences.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ProfileTheme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                topBarIcons
            }
        }
    }

    // MARK: - Top-right icons

    private var topBarIcons: some View {
        HStack(spacing: 10) {
            ProfileTopBarIconButton(asset: "Icons/fluent_search-24-regular") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showSearch = true
                }
            }

            ZStack(alignment: .topTrailing) {
                ProfileTopBarIconButton(asset: "Icons/fluent_alert-24-regular") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNotifications.toggle()
                    }
                }
                if unreadCount > 0 && !showNotifications {
                    Text("\(unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(ProfileTheme.accent)
                        .clipShape(Circle())
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2) }
                        .offset(x: 4, y: -4)
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Same glass chip treatment as search / alerts — tap returns Home.
            ProfileAvatarTopBarButton(profile: viewModel.profile) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .home
                }
            }
        }
    }

    @ViewBuilder
    private var notificationsOverlay: some View {
        if showNotifications {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showNotifications = false }
                }
            VStack {
                HStack {
                    Spacer()
                    NotificationDropdown(
                        store: appState.notifications,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) { showNotifications = false }
                        }
                    )
                }
                .padding(.top, 80)
                .padding(.trailing, 28)
                Spacer()
            }
            .transition(.opacity)
            .zIndex(50)
        }
    }

    @ViewBuilder
    private var searchOverlay: some View {
        if showSearch {
            SearchPopupView(
                isPresented: $showSearch,
                onSelectCommunityPost: { post in
                    // Profile lives outside the main tab set, so we hop
                    // back into Community to use its detail popup.
                    appState.pendingCommunityPost = post
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedTab = .people
                    }
                },
                onSelectLocalNote: { note in
                    searchedNoteId = note.id
                }
            )
                .transition(.opacity)
                .zIndex(60)
        }
    }

    // MARK: - Settings card

    private var settingsCard: some View {
        GlassCard {
            Group {
                if horizontalSizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
        }
    }

    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 20) {
            sidebar
                .frame(width: 260)

            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            detailPanel
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(minHeight: 460, alignment: .topLeading)
                // Keep the section transition's 14pt offset visually
                // bounded to this column — without clipping the slide
                // could otherwise visually overlap the sidebar.
                .clipped()
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            sidebar
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(height: 1)
            detailPanel
                .clipped()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            ForEach(ProfileDetail.allCases) { item in
                ProfileNavItem(
                    label: item.label,
                    active: viewModel.activeDetail == item
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.activeDetail = item
                        if item == .general { viewModel.generalPanel = .overview }
                    }
                }
            }
        }
    }

    private var detailPanel: some View {
        Group {
            switch viewModel.activeDetail {
            case .about:        AboutYouSection(viewModel: viewModel, schoolSearch: schoolSearch)
            case .subscription: SubscriptionSection(viewModel: viewModel)
            case .credits:      CreditsSection(viewModel: viewModel)
            case .security:     SecuritySection(viewModel: viewModel)
            case .general:      GeneralSection(viewModel: viewModel)
            case .feedback:     FeedbackSection(viewModel: viewModel)
            }
        }
        .id(viewModel.activeDetail)
        // Mirrors `DetailPanelTransition` (JSX L6621–L6655): subtle 14pt slide
        // + 0.994 scale + fade so the panel stays inside its column instead of
        // sliding all the way to the left edge of the card.
        .transition(.profileDetailPanel)
        .animation(
            .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.22),
            value: viewModel.activeDetail
        )
    }
}

// MARK: - Profile detail panel transition

private struct ProfileDetailPanelModifier: ViewModifier {
    let translation: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(x: translation)
    }
}

private extension AnyTransition {
    /// Subtle 14pt translate + 0.994 scale + opacity fade, matching the JSX
    /// `DetailPanelTransition` (others/noteworks-library(2).jsx L6644–L6651).
    /// Removal slides 14pt toward leading; insertion arrives from 14pt
    /// trailing — without ever leaving the panel column.
    static var profileDetailPanel: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ProfileDetailPanelModifier(translation: 14, scale: 0.994, opacity: 0),
                identity: ProfileDetailPanelModifier(translation: 0, scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: ProfileDetailPanelModifier(translation: -14, scale: 0.994, opacity: 0),
                identity: ProfileDetailPanelModifier(translation: 0, scale: 1, opacity: 1)
            )
        )
    }
}

// MARK: - BETA badge

/// Mirrors `Badge` (others/noteworks-library(2).jsx L92–L102).
struct ProfileBadgePill: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 11, weight: .bold))
            .tracking(0.06 * 11)
            .foregroundStyle(Color(red: 0x7A/255, green: 0x8A/255, blue: 0x96/255))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.45))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Top-bar icon buttons

/// Mirrors the round 44×44 GlassIconBtn used in TopBar (JSX L80–L90).
private struct ProfileTopBarIconButton: View {
    let asset: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(ProfileTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.35))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .tint(ProfileTheme.textPrimary)
        .buttonStyle(PillPressStyle())
        .focusEffectDisabled()
    }
}

/// Avatar in a 44×44 glass circle — matches `ProfileTopBarIconButton` so
/// there is no extra accent “frame” around the initials / photo.
private struct ProfileAvatarTopBarButton: View {
    let profile: Profile
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            AvatarBadge(profile: profile, size: 44, fontSize: 12)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.35))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .tint(ProfileTheme.textPrimary)
        .buttonStyle(PillPressStyle())
        .focusEffectDisabled()
    }
}

#Preview {
    ProfileView(selectedTab: .constant(nil))
        .environmentObject(AppState(notesStore: NotesStore.preview()))
}
