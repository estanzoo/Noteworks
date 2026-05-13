//
//  CommunityCommentItem.swift
//  Noteworks
//
//  Renders one top-level comment with its author info, body (clamped to
//  4 lines with a "Show more" toggle), a like count, a Reply affordance,
//  and any nested replies. The reply composer becomes inline once the
//  user taps Reply and routes `(parentCommentId, body)` back up to the
//  detail popup's view model.
//

import SwiftUI

struct CommunityCommentItem: View {
    let comment: CommunityComment
    /// Set to the current user's id so the row can show a "Delete" action
    /// for comments that belong to them.
    let currentUserId: String?
    /// Identifies the post author so we can show the "AUTHOR" badge next
    /// to their comments / replies.
    let postAuthorId: String
    let onSubmitReply: (_ parentCommentId: String, _ text: String) -> Void
    let onDelete: (_ commentId: String) -> Void

    @State private var expandedReplies: Bool = false
    @State private var replyOpen: Bool = false
    @State private var replyDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            commentEntry(comment, nested: false)

            // Show the first 2 replies inline; collapse the rest behind
            // a "Show N more replies" toggle to keep the thread readable.
            if !comment.replies.isEmpty {
                let visible = expandedReplies ? comment.replies : Array(comment.replies.prefix(2))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visible) { reply in
                        commentEntry(reply, nested: true)
                            .padding(.top, 12)
                    }
                    if !expandedReplies && comment.replies.count > 2 {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { expandedReplies = true }
                        } label: {
                            Text("Show \(comment.replies.count - 2) more \(comment.replies.count - 2 > 1 ? "replies" : "reply")")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CommunityTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    if expandedReplies && comment.replies.count > 2 {
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
            CommunityAvatar(name: entry.author.name, size: nested ? 30 : 36, nested: nested)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.author.name)
                        .font(.system(size: nested ? 13 : 14, weight: .bold))
                        .foregroundStyle(CommunityTheme.textPrimary)

                    if entry.userId == postAuthorId {
                        Text("AUTHOR")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.05 * 10)
                            .foregroundStyle(CommunityTheme.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(CommunityTheme.accent.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(CommunityTheme.accent.opacity(0.18), lineWidth: 1))
                    }

                    Text(relativeTime(entry.createdAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CommunityTheme.textMuted)

                    Spacer(minLength: 0)

                    if entry.userId == currentUserId {
                        Button {
                            onDelete(entry.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CommunityTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }

                CommentBody(text: entry.body, nested: nested)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(entry.likesCount)")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(CommunityTheme.textMuted)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 26)
                    .background(Capsule().fill(Color.white.opacity(0.56)))
                    .overlay(
                        Capsule().strokeBorder(
                            Color(red: 220/255, green: 228/255, blue: 236/255).opacity(0.9),
                            lineWidth: 1
                        )
                    )

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
                .background(Capsule().fill(Color.white.opacity(0.78)))
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
        onSubmitReply(comment.id, trimmed)
        replyDraft = ""
        withAnimation(.easeOut(duration: 0.15)) { replyOpen = false }
    }
}

// MARK: - Relative time formatter

/// Lightweight "5m ago" / "2h ago" formatter; falls back to a short date
/// for anything older than a week so the UI doesn't show "350h ago".
func relativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "now" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    if interval < 86_400 { return "\(Int(interval / 3600))h ago" }
    if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

// MARK: - Comment body with "Show more"

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

    private var shouldOfferToggle: Bool { text.count > 220 }
}
