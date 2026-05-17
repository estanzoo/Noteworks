//
//  NotificationsStore.swift
//  Noteworks
//
//  Single source of truth for the bell-icon inbox. Lives on `AppState`
//  so every tab (Home / Library / Community / Profile) reads the same
//  list — previously each screen owned its own empty `@State` array and
//  reset on tab switch.
//
//  No real server inbox exists yet; the store is populated by:
//    1. A welcome notification when the per-user session activates.
//    2. `recordNewCommunityPosts(_:currentUserId:)` — called by
//       `CommunityViewModel` whenever the feed surfaces posts the user
//       has not seen before. Posts authored by the current user are
//       filtered out.
//    3. `recordCommentOnOwnPost(...)` — best-effort placeholder until a
//       real push channel ships.
//

import Foundation

@MainActor
final class NotificationsStore: ObservableObject {
    @Published var items: [HomeNotification] = []

    /// IDs of community posts we've already turned into a notification.
    /// Used so a refresh of the feed doesn't replay the same post into
    /// the inbox over and over.
    private var notifiedPostIds: Set<String> = []

    private let inboxCap = 30

    // MARK: - Lifecycle

    /// Replaces the inbox with the welcome seed and resets the
    /// already-notified set. Called from `AppState` when a session
    /// (or guest session) becomes active.
    func resetForNewSession() {
        items = HomeNotification.seed()
        notifiedPostIds = []
    }

    /// Drops everything — used on sign-out so the next user doesn't see
    /// the previous user's inbox.
    func clear() {
        items = []
        notifiedPostIds = []
    }

    // MARK: - Read state

    var unreadCount: Int { items.filter(\.unread).count }

    func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].unread = false
    }

    func markAllRead() {
        for index in items.indices where items[index].unread {
            items[index].unread = false
        }
    }

    // MARK: - Event ingestion

    /// Push one notification onto the top of the inbox.
    func push(_ notification: HomeNotification) {
        items.insert(notification, at: 0)
        if items.count > inboxCap {
            items = Array(items.prefix(inboxCap))
        }
    }

    /// Called by `CommunityViewModel` after every feed refresh / page
    /// load. Generates a `.post` notification for each previously-unseen
    /// public post that wasn't authored by `currentUserId`.
    func recordNewCommunityPosts(
        _ posts: [CommunityPost],
        currentUserId: String?
    ) {
        // Walk oldest → newest so the freshest post ends up at the top.
        let freshest = posts
            .filter { $0.userId != currentUserId }
            .filter { !notifiedPostIds.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        for post in freshest {
            notifiedPostIds.insert(post.id)

            let who = displayName(for: post.author)
            let snippet = postSnippet(for: post)
            let text = "\(who) posted “\(snippet)”"

            push(HomeNotification(
                type: .post,
                text: text,
                createdAt: post.createdAt,
                unread: true
            ))
        }
    }

    /// Hand-rolled "someone commented on your post" entry. The detail
    /// popup calls this when it lands on a post the current user owns
    /// and a brand-new comment appears in the loaded list. Server-side
    /// push will eventually replace it.
    func recordCommentOnOwnPost(
        author: PostAuthor?,
        postTitle: String,
        commentCreatedAt: Date
    ) {
        let who = displayName(for: author)
        let title = postTitle.isEmpty ? "your post" : "your “\(postTitle.prefix(40))”"
        push(HomeNotification(
            type: .comment,
            text: "\(who) commented on \(title)",
            createdAt: commentCreatedAt,
            unread: true
        ))
    }

    // MARK: - Helpers

    private func displayName(for author: PostAuthor?) -> String {
        if let name = author?.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        return "Someone"
    }

    private func postSnippet(for post: CommunityPost) -> String {
        let title = post.title.trimmingCharacters(in: .whitespaces)
        let source = title.isEmpty ? post.body : title
        let clean = source.replacingOccurrences(of: "\n", with: " ")
        return clean.count <= 60 ? clean : String(clean.prefix(60)) + "…"
    }
}
