//
//  CommunityView.swift
//  Noteworks
//
//  Mirrors CommunityPage from others/noteworks-library(2).jsx L4848–L5041.
//

import SwiftUI

// MARK: - Community View

struct CommunityView: View {
    @Binding var selectedTab: AppTab?
    @StateObject private var viewModel = CommunityViewModel()
    @State private var activeTab: CommunityTab = .post
    @State private var showPostEditor = false
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var notifications = HomeNotification.samples
    @State private var activePostId: Int? = nil

    private var activePost: CommunityPost? {
        guard let id = activePostId else { return nil }
        return viewModel.posts.first(where: { $0.id == id })
    }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommunityBadgePill()
                        .padding(.top, 24)
                        .padding(.leading, 32)
                        .padding(.bottom, 12)

                    titleRow
                    tabSwitcher

                    if activeTab == .post {
                        postContent
                    } else {
                        notePlaceholder
                    }
                }
            }
        }
        .overlay { notificationsOverlay }
        .overlay { searchOverlay }
        .overlay { postEditorOverlay }
        .overlay { postDetailOverlay }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Community")
                .font(.system(size: 40, weight: .bold))
                .tracking(-0.02 * 40)
                .foregroundStyle(CommunityTheme.textPrimary)

            Spacer()

            HStack(spacing: 10) {
                CommunityGlassIconButton(icon: "Icons/fluent_search-24-regular") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showSearch = true
                    }
                }

                ZStack(alignment: .topTrailing) {
                    CommunityGlassIconButton(icon: "Icons/fluent_alert-24-regular") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNotifications.toggle()
                        }
                    }
                    if notifications.filter(\.unread).count > 0 && !showNotifications {
                        Text("\(notifications.filter(\.unread).count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(CommunityTheme.accent)
                            .clipShape(Circle())
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2) }
                            .offset(x: 4, y: -4)
                            .allowsHitTesting(false)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                CommunityGlassIconButton(icon: "Icons/fluent_person-24-regular") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = nil
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            CommunityTabButton(label: "POST", isActive: activeTab == .post) {
                withAnimation(.easeInOut(duration: 0.2)) { activeTab = .post }
            }
            CommunityTabButton(label: "NOTE", isActive: activeTab == .note) {
                withAnimation(.easeInOut(duration: 0.2)) { activeTab = .note }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.2))
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    // MARK: - Post grid

    private var postContent: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
            spacing: 20
        ) {
            PostNewCardView {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showPostEditor = true
                }
            }

            ForEach(viewModel.posts) { post in
                PostCardView(
                    post: post,
                    onOpen: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            activePostId = post.id
                        }
                    },
                    onToggleReaction: { reaction in
                        viewModel.togglePostReaction(postId: post.id, reaction: reaction)
                    }
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
    }

    private var notePlaceholder: some View {
        VStack {
            Spacer(minLength: 100)
            Text("Shared notes coming soon.")
                .font(.system(size: 17))
                .foregroundStyle(CommunityTheme.textMuted)
            Spacer(minLength: 100)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Overlays

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
                .padding(.top, 130)
                .padding(.trailing, 32)
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

    @ViewBuilder
    private var postEditorOverlay: some View {
        if showPostEditor {
            PostEditorPopup(isPresented: $showPostEditor) { payload in
                viewModel.addPost(
                    title: payload.title,
                    body: payload.body,
                    tags: payload.tags
                )
            }
            .transition(.opacity)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private var postDetailOverlay: some View {
        if let post = activePost {
            CommunityPostDetailPopup(
                post: post,
                onClose: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        activePostId = nil
                    }
                },
                onToggleConnect: { viewModel.toggleConnect(postId: post.id) },
                onToggleReaction: { reaction in
                    viewModel.togglePostReaction(postId: post.id, reaction: reaction)
                },
                onToggleCommentReaction: { targetId, reaction in
                    viewModel.toggleCommentReaction(postId: post.id, targetId: targetId, reaction: reaction)
                },
                onAddComment: { text in
                    viewModel.addComment(postId: post.id, text: text)
                },
                onAddReply: { commentId, text in
                    viewModel.addReply(postId: post.id, commentId: commentId, text: text)
                }
            )
            .transition(.opacity)
            .zIndex(120)
        }
    }
}

// MARK: - Tab Enum

enum CommunityTab {
    case post, note
}

// MARK: - Badge

private struct CommunityBadgePill: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 11, weight: .bold))
            .tracking(0.06 * 11)
            .foregroundStyle(Color(red: 0x7A/255, green: 0x8A/255, blue: 0x96/255))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.45))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Glass Icon Button

private struct CommunityGlassIconButton: View {
    let icon: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(CommunityTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.35))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Button

private struct CommunityTabButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.02 * 14)
                .foregroundStyle(isActive ? CommunityTheme.textPrimary : CommunityTheme.textMuted)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(isActive ? Color.white.opacity(0.6) : Color.clear)
                .clipShape(Capsule())
                .shadow(
                    color: isActive ? .black.opacity(0.06) : .clear,
                    radius: 3, y: 1
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Post New Card (React PostNewCard)

private struct PostNewCardView: View {
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("User name")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CommunityTheme.textPrimary)
                        Text("Your school\nYour major")
                            .font(.system(size: 12))
                            .foregroundStyle(CommunityTheme.textMuted)
                            .lineSpacing(2)
                    }
                }
                .padding(.bottom, 20)

                Text("Please enter the title...")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CommunityTheme.accent)
                    .padding(.bottom, 12)

                Text("Type the text here...")
                    .font(.system(size: 14))
                    .foregroundStyle(CommunityTheme.textMuted)

                Spacer(minLength: 40)

                HStack {
                    Text("# topic")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CommunityTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    HStack(spacing: 12) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 16))
                            .foregroundStyle(CommunityTheme.textMuted)
                        Image(systemName: "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(CommunityTheme.textMuted)
                    }
                }
            }
            .padding(24)
            .frame(minHeight: 280, alignment: .topLeading)
            .modifier(CommunityGlassCardModifier())
        }
        .buttonStyle(CommunityCardPressStyle())
    }
}

// MARK: - Post Card (React PostCard)

private struct PostCardView: View {
    let post: CommunityPost
    let onOpen: () -> Void
    let onToggleReaction: (ReactionKind) -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                // User row
                HStack(spacing: 12) {
                    CommunityAvatar(name: post.user, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.user)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CommunityTheme.textPrimary)
                        Text("\(post.school)\n\(post.major)")
                            .font(.system(size: 12))
                            .foregroundStyle(CommunityTheme.textMuted)
                            .lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 16)

                // Title
                Text(post.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CommunityTheme.textPrimary)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .padding(.bottom, post.body != nil ? 8 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Body
                if let body = post.body {
                    Text(body)
                        .font(.system(size: 14))
                        .foregroundStyle(CommunityTheme.textSecondary)
                        .lineLimit(4)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Attachments
                PostAttachmentStack(post: post, detail: false)

                Spacer(minLength: 16)

                // Tags + stats row
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        ForEach(Array(post.tags.enumerated()), id: \.offset) { _, tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CommunityTheme.textMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 14))
                                .foregroundStyle(CommunityTheme.textMuted)
                            Text("\(post.commentCount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CommunityTheme.textMuted)
                        }
                        .padding(.horizontal, 6)

                        CommunityCardReactionButton(
                            kind: .like,
                            count: post.likes,
                            active: post.userReaction == .like
                        ) {
                            onToggleReaction(.like)
                        }

                        CommunityCardReactionButton(
                            kind: .dislike,
                            count: post.dislikes,
                            active: post.userReaction == .dislike
                        ) {
                            onToggleReaction(.dislike)
                        }
                    }
                }
            }
            .padding(24)
            .frame(minHeight: 200, alignment: .topLeading)
            .modifier(CommunityGlassCardModifier())
        }
        .buttonStyle(CommunityCardPressStyle())
    }
}

// MARK: - Glass card modifier

struct CommunityGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(-1)
            }
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.2),
                                Color(red: 245/255, green: 248/255, blue: 252/255).opacity(0.3)
                            ],
                            startPoint: UnitPoint(x: 0.15, y: 0),
                            endPoint: UnitPoint(x: 0.85, y: 1)
                        )
                    )
            }
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: .white.opacity(0.6), radius: 0, x: 0, y: -0.5)
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

// MARK: - Card Press Style

struct CommunityCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        CommunityView(selectedTab: .constant(AppTab.people))
    }
}
