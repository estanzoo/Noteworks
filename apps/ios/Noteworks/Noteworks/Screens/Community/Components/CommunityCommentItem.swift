//
//  CommunityCommentItem.swift
//  Noteworks
//
//  Mirrors CommunityCommentItem from others/noteworks-library(2).jsx
//  L4545–L4661: avatar + user + Author badge + time, clamped body with
//  Show more, Like/Dislike pills + Reply, the first author reply inline,
//  a "Show N more replies" toggle for hidden replies, and a reply composer.
//

import SwiftUI

struct CommunityCommentItem: View {
    let comment: CommunityComment
    let onToggleReaction: (_ targetId: String, _ reaction: ReactionKind) -> Void
    let onSubmitReply: (_ text: String) -> Void

    @State private var expandedReplies: Bool = false
    @State private var replyOpen: Bool = false
    @State private var replyDraft: String = ""

    /// Mirrors `authorReply = comment.replies.find(r => r.author)` (JSX L4556–L4557).
    private var authorReply: CommunityComment? {
        comment.replies.first(where: { $0.author })
    }

    private var hiddenReplies: [CommunityComment] {
        comment.replies.filter { $0.id != authorReply?.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            commentEntry(comment, nested: false)

            if let reply = authorReply {
                commentEntry(reply, nested: true)
                    .padding(.leading, 46)
                    .padding(.top, 12)
            }

            if !hiddenReplies.isEmpty && !expandedReplies {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { expandedReplies = true }
                } label: {
                    Text("Show \(hiddenReplies.count) more \(hiddenReplies.count > 1 ? "replies" : "reply")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CommunityTheme.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, 46)
                .padding(.top, 10)
            }

            if expandedReplies && !hiddenReplies.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(hiddenReplies) { reply in
                        commentEntry(reply, nested: true)
                            .padding(.top, 12)
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { expandedReplies = false }
                    } label: {
                        Text("Hide replies")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CommunityTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .padding(.leading, 46)
            }

            if replyOpen {
                replyComposer
                    .padding(.leading, 46)
                    .padding(.top, 12)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 219/255, green: 227/255, blue: 235/255).opacity(0.72))
                .frame(height: 1)
        }
    }

    // MARK: - Single comment / reply entry

    @ViewBuilder
    private func commentEntry(_ entry: CommunityComment, nested: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CommunityAvatar(name: entry.user, size: nested ? 30 : 36, nested: nested)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.user)
                        .font(.system(size: nested ? 13 : 14, weight: .bold))
                        .foregroundStyle(CommunityTheme.textPrimary)

                    if entry.author {
                        Text("AUTHOR")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.05 * 10)
                            .foregroundStyle(CommunityTheme.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(CommunityTheme.accent.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(CommunityTheme.accent.opacity(0.18), lineWidth: 1))
                    }

                    Text(entry.time)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CommunityTheme.textMuted)

                    Spacer(minLength: 0)
                }

                CommentBody(text: entry.text, nested: nested)

                HStack(spacing: 8) {
                    CommunityReactionPill(
                        label: "Like",
                        count: entry.likes,
                        kind: .like,
                        active: entry.userReaction == .like
                    ) { onToggleReaction(entry.id, .like) }

                    CommunityReactionPill(
                        label: "Dislike",
                        count: entry.dislikes,
                        kind: .dislike,
                        active: entry.userReaction == .dislike
                    ) { onToggleReaction(entry.id, .dislike) }

                    if !nested {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { replyOpen.toggle() }
                        } label: {
                            Text("Reply")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CommunityTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Reply composer

    private var replyComposer: some View {
        HStack(spacing: 8) {
            TextField("Write a reply...", text: $replyDraft)
                .font(.system(size: 13))
                .foregroundStyle(CommunityTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(
                    Capsule().fill(Color.white.opacity(0.78))
                )
                .overlay(
                    Capsule().strokeBorder(
                        Color(red: 214/255, green: 223/255, blue: 232/255).opacity(0.96),
                        lineWidth: 1
                    )
                )

            Button {
                submit()
            } label: {
                Text("Reply")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(Capsule().fill(CommunityTheme.accentGradient))
                    .shadow(color: CommunityTheme.accent.opacity(0.22), radius: 10, x: 0, y: 6)
            }
            .buttonStyle(CommunityReactionPressStyle())
            .disabled(replyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(replyDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
    }

    private func submit() {
        let trimmed = replyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSubmitReply(trimmed)
        replyDraft = ""
        withAnimation(.easeOut(duration: 0.15)) { replyOpen = false }
    }
}

// MARK: - Comment body with "Show more"

/// Mirrors `CommentText` (JSX L4511–L4542).
private struct CommentBody: View {
    let text: String
    let nested: Bool

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: nested ? 13 : 14, weight: .medium))
                .foregroundStyle(CommunityTheme.textSecondary)
                .lineLimit(expanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)

            // Approximate the JSX "overflow" detection: if the text looks long,
            // offer the Show more toggle. Using a simple heuristic (character
            // count) keeps this deterministic without Geometry/layout reads.
            if shouldOfferToggle {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show more")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CommunityTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shouldOfferToggle: Bool {
        // 4 lines of body text is typically ~220 chars at 14pt on ~460pt wide.
        text.count > 220
    }
}
