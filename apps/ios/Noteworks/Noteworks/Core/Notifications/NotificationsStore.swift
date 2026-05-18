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
//    1. A pinned welcome notification when the user signs in or enters
//       guest mode — persisted per user so it survives relaunches.
//    2. `recordNewCommunityPosts(_:currentUserId:)` — called by
//       `CommunityViewModel` for posts that arrive after the first feed
//       snapshot (historical feed items are baselined silently).
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

    /// True after the first community feed snapshot for this session.
    /// The first snapshot only establishes a baseline (mark existing
    /// posts as seen) so historical feed items don't flood a new inbox.
    private var hasEstablishedFeedBaseline = false

    /// Notifications are only created for community activity after this
    /// moment (sign-in, guest entry, or first feed open for a returning
    /// user). Stops paginated historical posts from filling the inbox.
    private var sessionStartedAt: Date?

    private var activeUserId: String?
    private let inboxCap = 30
    private let defaults = UserDefaults.standard

    // MARK: - Lifecycle

    /// Binds the inbox to `userId`, restores any saved rows (including
    /// the welcome notification), and resets feed-baseline tracking for
    /// this app session. Call from `AppState` whenever a user session
    /// becomes active (cold launch, sign-in, or guest mode).
    ///
    /// - Parameter freshSession: When `true` (sign-in / guest entry),
    ///   starts a new notification cutoff so only activity after that
    ///   moment generates rows. The welcome row is added if missing.
    func activate(userId: String, freshSession: Bool = false) {
        activeUserId = userId
        loadFromDisk()

        if freshSession {
            sessionStartedAt = Date()
            notifiedPostIds = []
        } else if sessionStartedAt == nil {
            sessionStartedAt = Date()
        }

        hasEstablishedFeedBaseline = false
        ensureWelcomePresent()
        saveToDisk()
    }

    /// Clears in-memory state on sign-out. Persisted inbox for each user
    /// is kept on disk so the welcome row is still there on next sign-in.
    func deactivate() {
        saveToDisk()
        activeUserId = nil
        items = []
        notifiedPostIds = []
        hasEstablishedFeedBaseline = false
        sessionStartedAt = nil
    }

    // MARK: - Read state

    var unreadCount: Int { items.filter(\.unread).count }

    func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].unread = false
        saveToDisk()
    }

    func markAllRead() {
        for index in items.indices where items[index].unread {
            items[index].unread = false
        }
        saveToDisk()
    }

    // MARK: - Event ingestion

    /// Push one notification onto the top of the inbox.
    func push(_ notification: HomeNotification) {
        items.insert(notification, at: 0)
        trimInbox()
        saveToDisk()
    }

    /// Called by `CommunityViewModel` after every feed refresh / page
    /// load. Generates a `.post` notification for each previously-unseen
    /// public post that wasn't authored by `currentUserId`.
    func recordNewCommunityPosts(
        _ posts: [CommunityPost],
        currentUserId: String?
    ) {
        let fromOthers = posts.filter { $0.userId != currentUserId }

        // First feed load after sign-in: treat everything already on the
        // feed as "seen" without notifying — only posts that appear later
        // (refresh, pagination of new items, or genuinely new posts) land
        // in the inbox.
        if !hasEstablishedFeedBaseline {
            hasEstablishedFeedBaseline = true
            if sessionStartedAt == nil {
                sessionStartedAt = Date()
            }
            notifiedPostIds.formUnion(fromOthers.map(\.id))
            saveToDisk()
            return
        }

        guard let cutoff = sessionStartedAt else { return }

        // Walk oldest → newest so the freshest post ends up at the top.
        let freshest = fromOthers
            .filter { !notifiedPostIds.contains($0.id) }
            .filter { $0.createdAt > cutoff }
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

    // MARK: - Welcome row

    /// Inserts the welcome notification if this user doesn't have one yet.
    /// Existing welcome rows are never removed — only marked read.
    private func ensureWelcomePresent() {
        guard !items.contains(where: { $0.id == HomeNotification.welcomeNotificationId }) else {
            return
        }
        items.append(HomeNotification.welcomeNotification())
    }

    /// Keeps the newest `inboxCap - 1` rows plus the pinned welcome row.
    private func trimInbox() {
        guard items.count > inboxCap else { return }

        let welcome = items.first { $0.id == HomeNotification.welcomeNotificationId }
        var rest = items.filter { $0.id != HomeNotification.welcomeNotificationId }
        let cap = welcome == nil ? inboxCap : inboxCap - 1
        rest = Array(rest.prefix(cap))
        items = welcome.map { rest + [$0] } ?? rest
    }

    // MARK: - Persistence

    private struct PersistedInbox: Codable {
        var items: [HomeNotification]
        var notifiedPostIds: [String]
        var sessionStartedAt: Date?
    }

    private func storageKey(for userId: String) -> String {
        "notifications.inbox.\(userId)"
    }

    private func loadFromDisk() {
        guard let userId = activeUserId,
              let data = defaults.data(forKey: storageKey(for: userId)),
              let saved = try? JSONDecoder().decode(PersistedInbox.self, from: data) else {
            items = []
            notifiedPostIds = []
            sessionStartedAt = nil
            return
        }
        items = saved.items
        notifiedPostIds = Set(saved.notifiedPostIds)
        sessionStartedAt = saved.sessionStartedAt
    }

    private func saveToDisk() {
        guard let userId = activeUserId else { return }
        let payload = PersistedInbox(
            items: items,
            notifiedPostIds: Array(notifiedPostIds),
            sessionStartedAt: sessionStartedAt
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey(for: userId))
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
