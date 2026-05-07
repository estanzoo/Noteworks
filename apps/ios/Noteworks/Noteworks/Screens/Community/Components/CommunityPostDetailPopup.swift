//
//  CommunityPostDetailPopup.swift
//  Noteworks
//
//  Mirrors CommunityPostDetailPopup from others/noteworks-library(2).jsx
//  L4663–L4846. Dimmed glass overlay with a two-column layout when the
//  post has attachments (collapses to a single column on compact width):
//  - header (avatar + user + Connect + close)
//  - title + body + reaction pills + comment count + tags
//  - scrollable comments list
//  - comment composer pinned to the bottom.
//

import SwiftUI

struct CommunityPostDetailPopup: View {
    let post: CommunityPost
    let onClose: () -> Void
    let onToggleConnect: () -> Void
    let onToggleReaction: (ReactionKind) -> Void
    let onToggleCommentReaction: (_ targetId: String, _ reaction: ReactionKind) -> Void
    let onAddComment: (_ text: String) -> Void
    let onAddReply: (_ commentId: String, _ text: String) -> Void

    @State private var commentDraft: String = ""
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var hasAttachments: Bool { !post.attachments.isEmpty }
    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        ZStack {
            // Dimmed backdrop that closes on tap (JSX L4704–L4705).
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
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                PostAttachmentStack(post: post, detail: true)
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 252/255, green: 253/255, blue: 255/255).opacity(0.7),
                    Color(red: 241/255, green: 246/255, blue: 250/255).opacity(0.48),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Content pane

    private var contentPane: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if hasAttachments && isCompact {
                        PostAttachmentStack(post: post, detail: true)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
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
                CommunityAvatar(name: post.user, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(post.user)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CommunityTheme.textPrimary)
                        Text(post.school)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CommunityTheme.textMuted)
                    }
                    Text(post.major)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CommunityTheme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    connectButton
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

                if let body = post.body {
                    Text(body)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CommunityTheme.textSecondary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FlowLayout(spacing: 8) {
                CommunityReactionPill(
                    label: "Like",
                    count: post.likes,
                    kind: .like,
                    active: post.userReaction == .like
                ) { onToggleReaction(.like) }

                CommunityReactionPill(
                    label: "Dislike",
                    count: post.dislikes,
                    kind: .dislike,
                    active: post.userReaction == .dislike
                ) { onToggleReaction(.dislike) }

                Text("\(post.commentCount) comments")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CommunityTheme.textMuted)
                    .padding(.horizontal, 4)

                ForEach(Array(post.tags.enumerated()), id: \.offset) { _, tag in
                    Text("#\(tag)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CommunityTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.62)))
                        .overlay(Capsule().strokeBorder(CommunityTheme.glassBorder, lineWidth: 1))
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

    private var connectButton: some View {
        Button(action: onToggleConnect) {
            Text(post.connected ? "Connected" : "Connect")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(post.connected ? CommunityTheme.textPrimary : .white)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(
                    Capsule().fill(
                        post.connected
                            ? AnyShapeStyle(Color.white.opacity(0.68))
                            : AnyShapeStyle(CommunityTheme.accentGradient)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        post.connected ? CommunityTheme.glassBorder : Color.white.opacity(0.24),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: post.connected ? .clear : CommunityTheme.accent.opacity(0.24),
                    radius: 14, x: 0, y: 8
                )
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
        if post.commentThread.isEmpty {
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
                ForEach(post.commentThread) { comment in
                    CommunityCommentItem(
                        comment: comment,
                        onToggleReaction: { targetId, reaction in
                            onToggleCommentReaction(targetId, reaction)
                        },
                        onSubmitReply: { text in
                            onAddReply(comment.id, text)
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

            Button {
                submitComment()
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
            .disabled(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
        .padding(20)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 219/255, green: 227/255, blue: 235/255).opacity(0.78))
                .frame(height: 1)
        }
    }

    private func submitComment() {
        let trimmed = commentDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAddComment(trimmed)
        commentDraft = ""
    }
}
