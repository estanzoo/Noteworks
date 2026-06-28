//
//  CommunityView.swift
//  Noteworks
//
//  Top-level Community screen. Hosts the post feed (with cursor-based
//  infinite scroll), the new-post editor overlay, the detail popup, and
//  the small notifications / search overlays inherited from the design.
//

import SwiftUI

// MARK: - Community View

struct CommunityView: View {
    @Binding var selectedTab: AppTab?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tutorial: TutorialCoordinator
    @StateObject private var viewModel = CommunityViewModel()
    @State private var activeTab: CommunityTab = .explore
    @State private var showPostEditor = false
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var tutorialAnchors: [TutorialTarget: CGRect] = [:]

    private var isComposerTutorialStep: Bool {
        tutorial.isActive && tutorial.currentStepId == "community-composer"
    }

    private var showsTutorialPostEditor: Bool {
        showPostEditor || (tutorial.isActive && isComposerTutorialStep)
    }

    private var postEditorPresented: Binding<Bool> {
        Binding(
            get: { showsTutorialPostEditor },
            set: { showPostEditor = $0 }
        )
    }

    private var isCommunityNewPostTutorialStep: Bool {
        tutorial.isActive && tutorial.currentStepId == "community-new-post"
    }

    private var isProfileEntryTutorialStep: Bool {
        tutorial.isActive && tutorial.currentStepId == "profile-entry"
    }

    @State private var activePostId: String? = nil
    /// Fallback storage for a post the user opened from the search
    /// popup that isn't (yet) in the loaded feed. The detail overlay
    /// reads `activePost` so it doesn't care which source the post
    /// came from.
    @State private var searchPreviewPost: CommunityPost? = nil

    private var activePost: CommunityPost? {
        guard let id = activePostId else { return nil }
        if let inFeed = viewModel.posts.first(where: { $0.id == id }) {
            return inFeed
        }
        return searchPreviewPost?.id == id ? searchPreviewPost : nil
    }

    var body: some View {
        mainContent
            .overlay { notificationsOverlay }
            .overlay { searchOverlay }
            .overlay { composerTutorialBackdropOverlay }
            .overlay { postEditorOverlay }
            .overlay { composerTutorialCoachOverlay }
            .overlay { postDetailOverlay }
            .overlay(alignment: .bottom) { feedErrorBanner }
            .overlay { communityNewPostTutorialOverlay }
            .overlay { profileEntryTutorialOverlay }
            .modifier(CommunityViewLifecycleModifier(
                appState: appState,
                tutorial: tutorial,
                viewModel: viewModel,
                showPostEditor: $showPostEditor,
                activePostId: $activePostId,
                tutorialAnchors: $tutorialAnchors,
                syncTutorialCommunityState: syncTutorialCommunityState,
                consumePendingCommunityPost: consumePendingCommunityPost
            ))
    }

    private var mainContent: some View {
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

                    postContent
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var composerTutorialBackdropOverlay: some View {
        if isComposerTutorialStep {
            communityTutorialOverlay(
                showsBackdrop: true,
                showsCoachCard: false,
                blocksBackgroundInteraction: false
            )
            .allowsHitTesting(false)
            .zIndex(95)
        }
    }

    @ViewBuilder
    private var composerTutorialCoachOverlay: some View {
        if isComposerTutorialStep {
            communityTutorialOverlay(showsBackdrop: false, showsCoachCard: true)
                .zIndex(110)
        }
    }

    @ViewBuilder
    private var communityNewPostTutorialOverlay: some View {
        if isCommunityNewPostTutorialStep {
            communityTutorialOverlay(showsBackdrop: true, showsCoachCard: true)
                .zIndex(200)
        }
    }

    @ViewBuilder
    private var profileEntryTutorialOverlay: some View {
        if isProfileEntryTutorialStep {
            communityTutorialOverlay(showsBackdrop: true, showsCoachCard: true)
                .zIndex(200)
        }
    }

    private func communityTutorialOverlay(
        showsBackdrop: Bool,
        showsCoachCard: Bool,
        blocksBackgroundInteraction: Bool = true
    ) -> some View {
        TutorialOverlayView(
            coordinator: tutorial,
            firstName: tutorial.firstName(from: appState.profile),
            targetFrames: tutorialAnchors,
            showsBackdrop: showsBackdrop,
            showsCoachCard: showsCoachCard,
            blocksBackgroundInteraction: blocksBackgroundInteraction
        )
    }

    private func syncTutorialCommunityState() {
        guard tutorial.isActive else { return }
        switch tutorial.currentStepId {
        case "community-new-post", "profile-entry":
            showPostEditor = false
            activePostId = nil
            activeTab = .explore
        case "community-composer":
            activeTab = .explore
            activePostId = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showPostEditor = true
            }
        default:
            break
        }
    }

    private func consumePendingCommunityPost(_ post: CommunityPost) {
        if viewModel.posts.contains(where: { $0.id == post.id }) {
            viewModel.upsert(post)
            searchPreviewPost = nil
        } else {
            searchPreviewPost = post
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            activePostId = post.id
        }
        appState.pendingCommunityPost = nil
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
                    if appState.notifications.unreadCount > 0 && !showNotifications {
                        Text("\(appState.notifications.unreadCount)")
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

                AppAvatarTopBarButton(
                    name: appState.profile?.displayName ?? "",
                    avatarUrl: appState.profile?.avatarUrl
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = nil
                    }
                }
                .tutorialAnchor(.profileAvatar)
                .tutorialHighlight(.profileAvatar, activeTarget: tutorial.activeTarget)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    private var tabSwitcher: some View {
        HStack {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(CommunityTab.allCases, id: \.self) { tab in
                        CommunityTabButton(label: tab.label, isActive: activeTab == tab) {
                            withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                            Task { await viewModel.selectPostKind(tab.postKind) }
                        }
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.2))
                .background(.ultraThinMaterial.opacity(0.3))
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
                }

                if !viewModel.filter.isDefault, let label = viewModel.filter.displayName {
                    activeFilterPill(label: label)
                        .padding(.leading, 12)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }

    private func activeFilterPill(label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CommunityTheme.accent)

            Button {
                Task { await viewModel.clearFilter() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CommunityTheme.accent)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(CommunityTheme.accent.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(CommunityTheme.accent.opacity(0.08)))
        .overlay(Capsule().strokeBorder(CommunityTheme.accent.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Post grid

    private var postContent: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
            spacing: 20
        ) {
            PostNewCardView(
                authorName: appState.profile?.displayName ?? "You",
                authorAvatarUrl: appState.profile?.avatarUrl
            ) {
                guard !tutorial.isActive else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    showPostEditor = true
                }
            }
            .tutorialAnchor(.communityNewPost)
            .tutorialHighlight(.communityNewPost, activeTarget: tutorial.activeTarget)

            ForEach(viewModel.posts) { post in
                PostCardView(
                    post: post,
                    avatarUrl: viewModel.avatarUrl(for: post, profile: appState.profile),
                    onOpen: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            activePostId = post.id
                        }
                    },
                    onToggleLike: {
                        Task { await viewModel.togglePostLike(post) }
                    },
                    onHashtagTap: { tag in
                        Task { await viewModel.selectHashtag(tag) }
                    }
                )
                .onAppear {
                    Task { await viewModel.loadMoreIfNeeded(currentItem: post) }
                }
            }

            if viewModel.isLoadingFeed && viewModel.posts.isEmpty {
                feedSkeleton
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .overlay(alignment: .bottom) {
            if viewModel.isLoadingMore {
                ProgressView()
                    .padding(.bottom, 24)
            }
        }
    }

    private var feedSkeleton: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading posts…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CommunityTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .gridCellColumns(3)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var feedErrorBanner: some View {
        if let error = viewModel.feedError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    viewModel.feedError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0xE4/255, green: 0x64/255, blue: 0x64/255))
            )
            .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
            .padding(.horizontal, 24)
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
            SearchPopupView(
                isPresented: $showSearch,
                initialTab: .community,
                onSelectCommunityPost: { post in
                    // If the post is already loaded in the feed, keep
                    // its (potentially fresher) feed copy as the source
                    // of truth via `upsert`. Otherwise stash the search
                    // hit in `searchPreviewPost` so `activePost` can
                    // find it without polluting the chronological feed.
                    if viewModel.posts.contains(where: { $0.id == post.id }) {
                        viewModel.upsert(post)
                        searchPreviewPost = nil
                    } else {
                        searchPreviewPost = post
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activePostId = post.id
                    }
                }
            )
            .transition(.opacity)
            .zIndex(60)
        }
    }

    @ViewBuilder
    private var postEditorOverlay: some View {
        if showsTutorialPostEditor {
            PostEditorPopup(
                isPresented: postEditorPresented,
                accessToken: appState.accessToken ?? "",
                isTutorialStatic: isComposerTutorialStep,
                onPublished: { post in
                    viewModel.upsert(post)
                    if !viewModel.posts.contains(where: { $0.id == post.id }) {
                        // `createPost` already inserts at the top; this branch
                        // covers the edge case where the call returned but the
                        // upsert ran before insert.
                    }
                },
                submit: { request in
                    try await viewModel.createPost(request)
                }
            )
            .transition(.opacity)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private var postDetailOverlay: some View {
        if let post = activePost, let token = appState.accessToken {
            CommunityPostDetailPopup(
                initialPost: post,
                accessToken: token,
                currentUserId: appState.currentUser?.id,
                onClose: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        activePostId = nil
                        searchPreviewPost = nil
                    }
                },
                onPostUpdated: { updated in
                    viewModel.upsert(updated)
                    if searchPreviewPost?.id == updated.id {
                        searchPreviewPost = updated
                    }
                },
                onPostDeleted: {
                    Task {
                        await viewModel.deletePost(post)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            activePostId = nil
                            searchPreviewPost = nil
                        }
                    }
                },
                onCommentDelta: { delta in
                    viewModel.bumpCommentCount(postId: post.id, by: delta)
                },
                onLikeToggled: {
                    // Detail's optimistic toggle is the source of truth here;
                    // `onPostUpdated` syncs the feed copy.
                },
                onHashtagTap: { tag in
                    activePostId = nil
                    Task { await viewModel.selectHashtag(tag) }
                }
            )
            .transition(.opacity)
            .zIndex(120)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.22)) {
                    appState.isImmersiveEditing = true
                }
            }
            .onDisappear {
                withAnimation(.easeInOut(duration: 0.22)) {
                    appState.isImmersiveEditing = false
                }
            }
        }
    }
}

// MARK: - Tab Enum

enum CommunityTab: CaseIterable {
    case explore, note, studyQuestion, discussion

    var label: String {
        switch self {
        case .explore: return "EXPLORE"
        case .note: return "NOTE"
        case .studyQuestion: return "STUDY QUESTION"
        case .discussion: return "DISCUSSION"
        }
    }

    var postKind: PostKind? {
        switch self {
        case .explore: return nil
        case .note: return .note
        case .studyQuestion: return .studyQuestions
        case .discussion: return .discussions
        }
    }
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
        .tint(CommunityTheme.textPrimary)
        .buttonStyle(.plain)
        .focusEffectDisabled()
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
                .padding(.horizontal, 20)
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

// MARK: - Post New Card

private struct PostNewCardView: View {
    let authorName: String
    var authorAvatarUrl: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    CommunityAvatar(name: authorName, size: 40, avatarUrl: authorAvatarUrl)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(authorName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CommunityTheme.textPrimary)
                        Text("Share something with the community")
                            .font(.system(size: 12))
                            .foregroundStyle(CommunityTheme.textMuted)
                            .lineSpacing(2)
                    }
                }
                .padding(.bottom, 20)

                Text("Start a new post…")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CommunityTheme.accent)
                    .padding(.bottom, 12)

                Text("Ask a question, share notes, or just say hi.")
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

// MARK: - Post Card

private struct PostCardView: View {
    let post: CommunityPost
    let avatarUrl: String?
    let onOpen: () -> Void
    let onToggleLike: () -> Void
    let onHashtagTap: (String) -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    CommunityAvatar(
                        name: post.authorName,
                        size: 40,
                        avatarUrl: avatarUrl
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CommunityTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(relativeTime(post.createdAt))
                            .font(.system(size: 12))
                            .foregroundStyle(CommunityTheme.textMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PostKindPill(kind: post.postKind, compact: true)
                }
                .padding(.bottom, 16)

                Text(post.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CommunityTheme.textPrimary)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .padding(.bottom, post.body.isEmpty ? 0 : 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                if !post.body.isEmpty {
                    Text(post.body)
                        .font(.system(size: 14))
                        .foregroundStyle(CommunityTheme.textSecondary)
                        .lineLimit(4)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }

                PostMediaCarousel(media: post.media)
                PostAttachmentStack(post: post, detail: false)

                Spacer(minLength: 16)

                HStack(alignment: .center) {
                    if !post.hashtags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(post.hashtags.prefix(2), id: \.self) { tag in
                                Button {
                                    onHashtagTap(tag)
                                } label: {
                                    Text("#\(tag)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(CommunityTheme.textMuted)
                                        // One line per tag — a narrow card
                                        // otherwise wraps "#group-study" into
                                        // a "#gr / oup- / stud / y" stack.
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .layoutPriority(1)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 14))
                                .foregroundStyle(CommunityTheme.textMuted)
                            Text("\(post.commentsCount)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CommunityTheme.textMuted)
                        }
                        .padding(.horizontal, 6)

                        CommunityCardReactionButton(
                            count: post.likesCount,
                            active: post.liked
                        ) {
                            onToggleLike()
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

// MARK: - Lifecycle

private struct CommunityViewLifecycleModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @ObservedObject var tutorial: TutorialCoordinator
    @ObservedObject var viewModel: CommunityViewModel
    @Binding var showPostEditor: Bool
    @Binding var activePostId: String?
    @Binding var tutorialAnchors: [TutorialTarget: CGRect]
    let syncTutorialCommunityState: () -> Void
    let consumePendingCommunityPost: (CommunityPost) -> Void

    func body(content: Content) -> some View {
        content
            .task {
                viewModel.configure(appState: appState)
                if viewModel.posts.isEmpty {
                    await viewModel.loadInitialFeed()
                }
            }
            .onChange(of: appState.pendingCommunityPost) { _, post in
                guard let post else { return }
                consumePendingCommunityPost(post)
            }
            .onAppear {
                if let post = appState.pendingCommunityPost {
                    consumePendingCommunityPost(post)
                }
                if let me = appState.profile {
                    viewModel.reconcileOwnPostAuthors(from: me)
                }
                syncTutorialCommunityState()
            }
            .onChange(of: appState.profile) { _, newProfile in
                viewModel.reconcileOwnPostAuthors(from: newProfile)
            }
            .onChange(of: tutorial.tutorialCommunityComposerOpen) { _, shouldOpen in
                if shouldOpen {
                    showPostEditor = true
                } else if tutorial.isActive {
                    showPostEditor = false
                }
            }
            .onChange(of: tutorial.isActive) { _, active in
                if !active {
                    showPostEditor = false
                    activePostId = nil
                }
            }
            .onChange(of: tutorial.currentStepId) { _, _ in
                syncTutorialCommunityState()
            }
            .onChange(of: tutorial.stepIndex) { _, _ in
                syncTutorialCommunityState()
            }
            .onPreferenceChange(TutorialAnchorKey.self) { tutorialAnchors = $0 }
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
    let appState = AppState(notesStore: NotesStore.preview())
    return NavigationStack {
        CommunityView(selectedTab: .constant(AppTab.people))
            .environmentObject(appState)
            .environmentObject(appState.tutorialCoordinator)
    }
}
