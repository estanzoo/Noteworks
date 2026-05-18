//
//  CommunityPostDetailPopup.swift
//  Noteworks
//
//  Full-post overlay shown when the user taps a card on the feed. On
//  open it fetches the post detail + the first page of threaded comments
//  in parallel, then renders the post body, hashtag chips, attachments,
//  the comment thread, and a composer pinned to the bottom.
//

import SwiftUI

struct CommunityPostDetailPopup: View {
    let initialPost: CommunityPost
    let accessToken: String
    let currentUserId: String?

    let onClose: () -> Void
    let onPostUpdated: (CommunityPost) -> Void
    let onPostDeleted: () -> Void
    let onCommentDelta: (_ delta: Int) -> Void
    let onLikeToggled: () -> Void
    let onHashtagTap: (String) -> Void

    @State private var post: CommunityPost
    @State private var comments: [CommunityComment] = []
    @State private var isLoadingComments: Bool = true
    @State private var loadError: String?
    @State private var commentDraft: String = ""
    @State private var isSubmittingComment: Bool = false
    @State private var attachmentPreview: PostAttachment?
    @State private var imagePreviewURL: String?
    @State private var showDeleteConfirm: Bool = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Used to mirror any Profile-screen edit (avatar / display name)
    /// into the post header and the comment thread while this popup is
    /// still open. See `.onChange(of: appState.profile)` below.
    @EnvironmentObject private var appState: AppState

    init(
        initialPost: CommunityPost,
        accessToken: String,
        currentUserId: String?,
        onClose: @escaping () -> Void,
        onPostUpdated: @escaping (CommunityPost) -> Void,
        onPostDeleted: @escaping () -> Void,
        onCommentDelta: @escaping (Int) -> Void,
        onLikeToggled: @escaping () -> Void,
        onHashtagTap: @escaping (String) -> Void
    ) {
        self.initialPost = initialPost
        self.accessToken = accessToken
        self.currentUserId = currentUserId
        self.onClose = onClose
        self.onPostUpdated = onPostUpdated
        self.onPostDeleted = onPostDeleted
        self.onCommentDelta = onCommentDelta
        self.onLikeToggled = onLikeToggled
        self.onHashtagTap = onHashtagTap
        _post = State(initialValue: initialPost)
    }

    /// Treat images and document attachments uniformly — both feed the
    /// left preview pane (matches the New Post composer's behaviour).
    private var hasAttachments: Bool {
        !post.attachments.isEmpty || !post.media.isEmpty
    }
    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var isOwnPost: Bool { post.userId == currentUserId }

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 27/255, blue: 39/255)
                .opacity(0.2)
                .background(.ultraThinMaterial.opacity(0.6))
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            GeometryReader { geo in
                let showSplit = hasAttachments && !isCompact
                popupShell(showSplit: showSplit)
                    .frame(
                        width: min(1180, geo.size.width - 32),
                        height: min(760, geo.size.height * 0.82)
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }

            if let preview = attachmentPreview {
                PDFAttachmentPreview(
                    attachment: preview,
                    accessToken: accessToken,
                    onDismiss: { attachmentPreview = nil }
                )
                .transition(.opacity)
                .zIndex(200)
            }

            if let imageURL = imagePreviewURL {
                ImageLightbox(
                    urlString: imageURL,
                    onDismiss: { imagePreviewURL = nil }
                )
                .transition(.opacity)
                .zIndex(200)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .task { await loadDetail() }
        // If the user edits their profile (avatar, display name, …) while
        // the popup is open, patch the post header (if it's their post)
        // and any of their own comments in this thread so the new info
        // shows up instantly instead of waiting for a reopen / refresh.
        .onChange(of: appState.profile) { _, newProfile in
            applyProfileToThread(newProfile)
        }
        .alert("Delete this post?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deletePost() }
            }
        } message: {
            Text("This action soft-deletes the post and removes it from the feed.")
        }
    }

    // MARK: - Loading

    private func loadDetail() async {
        isLoadingComments = true
        loadError = nil
        defer { isLoadingComments = false }

        do {
            async let detail = CommunityService.shared.fetchPost(id: post.id, accessToken: accessToken)
            async let commentPage = CommunityService.shared.fetchComments(postId: post.id, accessToken: accessToken)
            let fetched = try await detail
            let page = try await commentPage

            var merged = fetched
            // Keep client-known media if the server row hasn't synced yet.
            if merged.media.isEmpty, !post.media.isEmpty {
                merged.media = post.media
            }
            post = merged
            comments = page.comments
            onPostUpdated(fetched)
        } catch {
            let mapped = mapCommunityError(error, notFound: "This post is no longer available.")
            loadError = mapped.userMessage
            if case .notFound = mapped {
                // The feed VM will drop the stale row; close the overlay
                // so the user isn't staring at an empty card.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    onPostDeleted()
                }
            }
        }
    }

    /// Mirror a freshly-edited user profile into this popup's local
    /// state — the post header (if the post is mine) and any comments
    /// in the thread that I authored, including nested replies.
    private func applyProfileToThread(_ profile: UserProfile?) {
        guard let profile else { return }
        if post.userId == profile.id {
            post.author = PostAuthor(
                id: profile.id,
                name: profile.displayName,
                avatarUrl: profile.avatarUrl,
                school: profile.schoolAffiliation,
                major: profile.major
            )
        }
        comments = patchComments(
            comments,
            targetUserId: profile.id,
            name: profile.displayName,
            avatarUrl: profile.avatarUrl
        )
    }

    // MARK: - Mutations

    private func toggleLike() async {
        let snapshot = post
        post.hasLiked = !post.liked
        post.likesCount = max(0, post.likesCount + (snapshot.liked ? -1 : 1))

        do {
            let response = try await CommunityService.shared.togglePostLike(postId: post.id, accessToken: accessToken)
            post.hasLiked = response.liked
            post.likesCount = response.likesCount
            onLikeToggled()
            onPostUpdated(post)
        } catch {
            post = snapshot
            loadError = mapCommunityError(error).userMessage
        }
    }

    private func submitComment(parent: String?) async {
        let body = commentDraft.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }

        isSubmittingComment = true
        defer { isSubmittingComment = false }

        do {
            let created = try await CommunityService.shared.createComment(
                CreateCommentRequest(postId: post.id, body: body, parentCommentId: parent),
                accessToken: accessToken
            )
            insert(created)
            commentDraft = ""
            post.commentsCount += 1
            onCommentDelta(1)
            onPostUpdated(post)
        } catch {
            loadError = mapCommunityError(error, notFound: "Could not add comment.").userMessage
        }
    }

    /// Insert a created comment into the local thread, either as a new
    /// top-level entry or as a reply within its parent's `replies` chain.
    private func insert(_ comment: CommunityComment) {
        if let parentId = comment.parentCommentId {
            comments = CommunityPostDetailPopup.insertReply(
                comment,
                parentId: parentId,
                into: comments
            )
        } else {
            comments.insert(comment, at: 0)
        }
    }

    private static func insertReply(
        _ reply: CommunityComment,
        parentId: String,
        into thread: [CommunityComment]
    ) -> [CommunityComment] {
        thread.map { existing in
            if existing.id == parentId {
                var copy = existing
                copy.replies.append(reply)
                return copy
            }
            guard !existing.replies.isEmpty else { return existing }
            var copy = existing
            copy.replies = insertReply(reply, parentId: parentId, into: existing.replies)
            return copy
        }
    }

    /// Flips the heart on a comment (top-level or nested reply) immediately,
    /// fires the like-comment edge function, then reconciles with the
    /// server-returned count. Reverts on error.
    private func toggleCommentLike(id: String) async {
        let snapshot = comments
        comments = CommunityPostDetailPopup.applyLikeChange(
            commentId: id,
            in: comments,
            transform: { existing in
                var copy = existing
                let wasLiked = copy.liked
                copy.hasLiked = !wasLiked
                copy.likesCount = max(0, copy.likesCount + (wasLiked ? -1 : 1))
                return copy
            }
        )

        do {
            let response = try await CommunityService.shared.toggleCommentLike(
                commentId: id,
                accessToken: accessToken
            )
            comments = CommunityPostDetailPopup.applyLikeChange(
                commentId: id,
                in: comments,
                transform: { existing in
                    var copy = existing
                    copy.hasLiked = response.liked
                    copy.likesCount = response.likesCount
                    return copy
                }
            )
        } catch {
            comments = snapshot
            loadError = mapCommunityError(error, notFound: "That comment is no longer available.").userMessage
        }
    }

    /// Walks the thread tree and replaces the comment matching `commentId`
    /// with the result of `transform`. Used by the optimistic like flow so
    /// nested replies update in place without rebuilding the whole tree.
    private static func applyLikeChange(
        commentId: String,
        in thread: [CommunityComment],
        transform: (CommunityComment) -> CommunityComment
    ) -> [CommunityComment] {
        thread.map { existing in
            if existing.id == commentId {
                var changed = transform(existing)
                changed.replies = existing.replies
                return changed
            }
            guard !existing.replies.isEmpty else { return existing }
            var copy = existing
            copy.replies = applyLikeChange(
                commentId: commentId,
                in: existing.replies,
                transform: transform
            )
            return copy
        }
    }

    private func deleteComment(id: String) async {
        // Find how many descendants the comment has so we can decrement
        // the comments_count by the correct amount (the server cascades).
        let removed = CommunityPostDetailPopup.removeComment(id: id, from: comments)
        let dropped = removed.count
        comments = removed.thread

        do {
            _ = try await CommunityService.shared.deleteComment(id: id, accessToken: accessToken)
            post.commentsCount = max(0, post.commentsCount - dropped)
            onCommentDelta(-dropped)
            onPostUpdated(post)
        } catch {
            await loadDetail()
            loadError = mapCommunityError(error, notFound: "That comment was already deleted.").userMessage
        }
    }

    private static func removeComment(
        id: String,
        from thread: [CommunityComment]
    ) -> (thread: [CommunityComment], count: Int) {
        var totalDropped = 0
        var next: [CommunityComment] = []
        for comment in thread {
            if comment.id == id {
                totalDropped += comment.threadCount
                continue
            }
            var copy = comment
            let result = removeComment(id: id, from: comment.replies)
            copy.replies = result.thread
            totalDropped += result.count
            next.append(copy)
        }
        return (next, totalDropped)
    }

    private func deletePost() async {
        do {
            _ = try await CommunityService.shared.deletePost(id: post.id, accessToken: accessToken)
            onPostDeleted()
        } catch {
            loadError = mapCommunityError(error, forbidden: "You can only delete your own posts.").userMessage
        }
    }

    // MARK: - Shell

    @ViewBuilder
    private func popupShell(showSplit: Bool) -> some View {
        Group {
            if showSplit {
                HStack(spacing: 0) {
                    attachmentsPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle()
                        .fill(Color(red: 219/255, green: 227/255, blue: 235/255).opacity(0.8))
                        .frame(width: 1)
                    contentPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                contentPane
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.76),
                            Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.54),
                            Color(red: 231/255, green: 238/255, blue: 245/255).opacity(0.46),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: Color(red: 42/255, green: 61/255, blue: 84/255).opacity(0.18), radius: 60, x: 0, y: 28)
    }

    // MARK: - Attachments pane

    private var attachmentsPane: some View {
        PostAttachmentPreviewPane(
            post: post,
            accessToken: accessToken,
            onOpenAttachment: { attachmentPreview = $0 },
            onOpenImage: { imagePreviewURL = $0 }
        )
    }

    // MARK: - Content pane

    private var contentPane: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // On compact width (iPhone) we don't render the side
                    // preview pane, so attachments still need an inline
                    // affordance here. On regular width the side pane
                    // already shows the big preview + thumbnails.
                    if !post.attachments.isEmpty && isCompact {
                        PostAttachmentStack(
                            post: post,
                            detail: true,
                            onOpenAttachment: { attachmentPreview = $0 }
                        )
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }

                    if let error = loadError {
                        Text(error)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CommunityTheme.textMuted)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }

                    commentsList
                        .padding(.horizontal, 24)
                }
            }

            composer
        }
        .background(Color(red: 248/255, green: 251/255, blue: 254/255).opacity(0.78))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                CommunityAvatar(
                    name: post.authorName,
                    size: 42,
                    avatarUrl: post.author?.avatarUrl
                )

                VStack(alignment: .leading, spacing: 3) {
                    // Row 1: Author name + (optional) school affiliation —
                    // mirrors the NoteWorks_UI 3 community detail mock
                    // where "Alex Chen" is followed inline by his school.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(post.authorName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CommunityTheme.textPrimary)
                            .lineLimit(1)
                        if let school = post.author?.school, !school.isEmpty {
                            Text(school)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CommunityTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    // Row 2: Major (when set) — shown right under the
                    // name+school line, matching the mock's secondary
                    // "MA Information Experience Design" caption.
                    if let major = post.author?.major, !major.isEmpty {
                        Text(major)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CommunityTheme.textMuted)
                            .lineLimit(1)
                    }
                    // Row 3: Post-kind chip + timestamp.
                    HStack(spacing: 8) {
                        PostKindPill(kind: post.postKind)
                        Text(relativeTime(post.createdAt))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CommunityTheme.textMuted)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if isOwnPost {
                        deleteButton
                    }
                    closeButton
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(post.title)
                    .font(.system(size: 25, weight: .bold))
                    .tracking(-0.03 * 25)
                    .foregroundStyle(CommunityTheme.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.body.isEmpty {
                    Text(post.body)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CommunityTheme.textSecondary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // On regular width the left preview pane already shows
                // post images; only render the inline carousel on iPhone.
                if isCompact {
                    PostMediaCarousel(media: post.media) { url in
                        imagePreviewURL = url
                    }
                }
            }

            FlowLayout(spacing: 8) {
                CommunityReactionPill(
                    label: "Like",
                    count: post.likesCount,
                    active: post.liked
                ) {
                    Task { await toggleLike() }
                }

                // Comments count rendered as a non-interactive pill so it
                // sits flush with the Like pill on the same horizontal
                // baseline (matches the NoteWorks_UI 3 detail mock).
                CommunityCountPill(
                    icon: "bubble.right",
                    label: "\(post.commentsCount) \(post.commentsCount == 1 ? "comment" : "comments")"
                )

                ForEach(post.hashtags, id: \.self) { tag in
                    Button { onHashtagTap(tag) } label: {
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CommunityTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(CommunityTheme.accent.opacity(0.10)))
                            .overlay(Capsule().strokeBorder(CommunityTheme.accent.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 219/255, green: 227/255, blue: 235/255).opacity(0.78))
                .frame(height: 1)
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CommunityTheme.textMuted)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.05)))
        }
        .buttonStyle(CommunityReactionPressStyle())
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CommunityTheme.textMuted)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.05)))
        }
        .buttonStyle(CommunityReactionPressStyle())
    }

    // MARK: - Comments list

    @ViewBuilder
    private var commentsList: some View {
        if isLoadingComments {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading comments…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CommunityTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 200)
        } else if comments.isEmpty {
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.72))
                    Circle().strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
                    Image(systemName: "bubble.right")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(CommunityTheme.textMuted)
                }
                .frame(width: 68, height: 68)

                Text("No comments yet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CommunityTheme.textPrimary)

                Text("Start the conversation and this post will feel a lot more alive.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CommunityTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 240)
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(comments) { comment in
                    CommunityCommentItem(
                        comment: comment,
                        currentUserId: currentUserId,
                        postAuthorId: post.userId,
                        onSubmitReply: { parentId, text in
                            commentDraft = text
                            Task { await submitComment(parent: parentId) }
                        },
                        onDelete: { id in
                            Task { await deleteComment(id: id) }
                        },
                        onToggleLike: { id in
                            Task { await toggleCommentLike(id: id) }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Write a comment...", text: $commentDraft)
                .font(.system(size: 14))
                .foregroundStyle(CommunityTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(minHeight: 42)
                .background(Capsule().fill(Color.white.opacity(0.82)))
                .overlay(
                    Capsule().strokeBorder(
                        Color(red: 214/255, green: 223/255, blue: 232/255).opacity(0.96),
                        lineWidth: 1
                    )
                )
                .disabled(isSubmittingComment)

            Button {
                Task { await submitComment(parent: nil) }
            } label: {
                Text("Comment")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .background(Capsule().fill(CommunityTheme.accentGradient))
                    .shadow(color: CommunityTheme.accent.opacity(0.22), radius: 10, x: 0, y: 6)
            }
            .buttonStyle(CommunityReactionPressStyle())
            .disabled(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty || isSubmittingComment)
            .opacity(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
        .padding(20)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 219/255, green: 227/255, blue: 235/255).opacity(0.78))
                .frame(height: 1)
        }
    }
}

// MARK: - Image lightbox

/// Full-screen image viewer triggered from the preview pane / inline
/// carousel. Pinch-to-zoom is intentionally light here — the goal is a
/// quick "show me the photo bigger" affordance, not a full editor.
private struct ImageLightbox: View {
    let urlString: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            RemotePostImage(urlString: urlString, contentMode: .fit)
                .padding(24)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                Spacer()
            }
        }
    }
}
