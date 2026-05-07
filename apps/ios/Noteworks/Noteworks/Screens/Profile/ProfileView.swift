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
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ProfileViewModel()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showSearch: Bool = false
    @State private var showNotifications: Bool = false
    @State private var notifications = HomeNotification.samples

    private var unreadCount: Int { notifications.filter(\.unread).count }

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

            FeedbackThanksPopup(viewModel: viewModel)
                .animation(.easeOut(duration: 0.18), value: viewModel.feedbackPopup.open)
        }
        .overlay { notificationsOverlay }
        .overlay { searchOverlay }
        .navigationBarHidden(true)
        .onChange(of: viewModel.profile) { _, _ in
            viewModel.syncAboutDraftFromProfile()
        }
    }

    // MARK: - Header (BETA badge + title + TopBar icons)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileBadgePill()

            HStack(alignment: .top, spacing: 16) {
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

            // Active avatar — tap to leave Profile back to the previous tab.
            ProfileAvatarTopBarButton(profile: viewModel.profile, active: true) {
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
                        notifications: $notifications,
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
            SearchPopupView(isPresented: $showSearch)
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
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            sidebar
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(height: 1)
            detailPanel
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
            case .about:        AboutYouSection(viewModel: viewModel)
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
        .buttonStyle(PillPressStyle())
    }
}

/// Active-state avatar version used as the rightmost icon when on the
/// Profile page (JSX L1197–L1218 — TopBar's avatar button uses
/// `active=true` styling: tinted background, accent border, square-ish radius).
private struct ProfileAvatarTopBarButton: View {
    let profile: Profile
    var active: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            AvatarBadge(profile: profile, size: 44, fontSize: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: active ? 12 : 22, style: .continuous)
                        .strokeBorder(
                            active ? ProfileTheme.accent.opacity(0.4) : ProfileTheme.glassBorder,
                            lineWidth: active ? 1.5 : 1
                        )
                }
                .background {
                    RoundedRectangle(cornerRadius: active ? 12 : 22, style: .continuous)
                        .fill(active ? ProfileTheme.accent.opacity(0.15) : Color.white.opacity(0.35))
                }
                .clipShape(RoundedRectangle(cornerRadius: active ? 12 : 22, style: .continuous))
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PillPressStyle())
    }
}

#Preview {
    ProfileView(selectedTab: .constant(nil))
        .environmentObject(AppState())
}
