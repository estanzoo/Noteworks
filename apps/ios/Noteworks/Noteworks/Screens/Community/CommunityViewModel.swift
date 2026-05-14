//
//  CommunityViewModel.swift
//  Noteworks
//
//  Owns the live state for the Community screen — the cursor-paginated
//  feed, optimistic like/dislike toggles, and the two-step post creation
//  flow (PDF upload then create-post). All persistence lives server-side;
//  this view model only caches what the UI is currently showing.
//

import Foundation

// MARK: - Centralized error mapping

/// A reduction of every API failure into the few buckets the UI actually
/// cares about. `mapCommunityError` translates `APIError` (which is
/// generic across all endpoints) into one of these so each screen can
/// decide what to do without re-implementing the same status-code switch.
enum CommunityError: Error, Equatable, LocalizedError {
    case unauthorized
    case forbidden(String)
    case notFound(String)
    case validation(String)
    case server(String)
    case unknown(String)

    var userMessage: String {
        switch self {
        case .unauthorized:        return "Your session expired. Please sign in again."
        case .forbidden(let m):    return m
        case .notFound(let m):     return m
        case .validation(let m):   return m
        case .server(let m):       return m
        case .unknown(let m):      return m
        }
    }

    var errorDescription: String? { userMessage }

    var isAuthFailure: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

/// Translate an arbitrary `Error` into a `CommunityError`. Each call site
/// can pass context-specific messages for the 403/404 cases (e.g. "This
/// post is no longer available" vs "Could not add comment").
func mapCommunityError(
    _ error: Error,
    forbidden: String = "You don't have permission to do that.",
    notFound: String = "That item is no longer available."
) -> CommunityError {
    guard let api = error as? APIError else {
        return .unknown(error.localizedDescription)
    }
    switch api {
    case .unauthorized:
        return .unauthorized
    case .badRequest(let m):
        return .validation(m.isEmpty ? "Some fields are invalid." : m)
    case .notFound:
        return .notFound(notFound)
    case .serverError:
        return .server("Something went wrong on our end. Please try again.")
    case .networkError:
        return .server("Network is unreachable. Check your connection and try again.")
    case .decodingError(let underlying):
        #if DEBUG
        return .unknown("Decode failed: \(decodeDebugDescription(underlying))")
        #else
        return .unknown("Couldn't read the server's response.")
        #endif
    case .unknown(let code, let m):
        // 403 maps to .unknown(403, …) in `APIClient.mapError`, so detect it here.
        if code == 403 { return .forbidden(forbidden) }
        return .unknown(m)
    }
}

/// Pulls the human-readable bits out of a `DecodingError` so the on-screen
/// banner says *what* went wrong (missing key, type mismatch, bad date,
/// etc.) instead of the generic "Couldn't read the server's response."
/// This is wired in only for `#if DEBUG` builds so production users never
/// see the raw error text.
private func decodeDebugDescription(_ error: Error) -> String {
    guard let de = error as? DecodingError else { return error.localizedDescription }
    switch de {
    case .keyNotFound(let key, let ctx):
        return "missing key \"\(key.stringValue)\" at \(pathString(ctx.codingPath))"
    case .typeMismatch(let type, let ctx):
        return "wrong type \(type) at \(pathString(ctx.codingPath)) — \(ctx.debugDescription)"
    case .valueNotFound(let type, let ctx):
        return "null \(type) at \(pathString(ctx.codingPath))"
    case .dataCorrupted(let ctx):
        return "corrupted at \(pathString(ctx.codingPath)) — \(ctx.debugDescription)"
    @unknown default:
        return de.localizedDescription
    }
}

private func pathString(_ path: [CodingKey]) -> String {
    path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
}

// MARK: - View Model

@MainActor
final class CommunityViewModel: ObservableObject {

    // MARK: Published state

    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var isLoadingFeed: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published var feedError: String?

    @Published private(set) var filter: FeedFilter = .publicFeed

    // MARK: Dependencies

    private weak var appState: AppState?
    private let service: CommunityServiceProtocol

    // MARK: Pagination

    private var nextCursor: String?
    private var hasMore: Bool = true

    /// Tracks the most recent feed load so an older response that resolves
    /// late (after the user changed filters) is ignored.
    private var loadGeneration: Int = 0

    init(service: CommunityServiceProtocol = CommunityService.shared) {
        self.service = service
    }

    /// Called by `CommunityView` on appear. Captures the `AppState` so the
    /// view model can read the current access token / user ID on every
    /// request without re-passing them on every call.
    func configure(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Feed

    /// Fetches the first page for the current `filter`. Cheap to call
    /// multiple times — `isLoadingFeed` guards against duplicate work.
    func loadInitialFeed() async {
        guard !isLoadingFeed else { return }
        loadGeneration += 1
        let generation = loadGeneration

        isLoadingFeed = true
        feedError = nil
        defer { isLoadingFeed = false }

        guard let token = appState?.accessToken else { return }
        do {
            let page = try await service.fetchFeed(
                filter: filter,
                cursor: nil,
                limit: 20,
                currentUserId: appState?.currentUser?.id,
                accessToken: token
            )
            guard generation == loadGeneration else { return }
            posts = page.posts
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            guard generation == loadGeneration else { return }
            handle(error)
        }
    }

    /// Pulled by the feed list when the user nears the bottom. Looks at
    /// `currentItem` so SwiftUI's `.onAppear`-driven trigger is cheap to
    /// hook into a `ForEach`.
    func loadMoreIfNeeded(currentItem: CommunityPost) async {
        guard hasMore, !isLoadingMore, !isLoadingFeed else { return }
        // Only fire when the user is within ~3 items of the end of the
        // currently-loaded page; otherwise every cell appear triggers it.
        guard let triggerIndex = posts.firstIndex(where: { $0.id == currentItem.id }),
              triggerIndex >= posts.count - 3 else { return }
        guard let token = appState?.accessToken, let cursor = nextCursor else { return }

        let generation = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await service.fetchFeed(
                filter: filter,
                cursor: cursor,
                limit: 20,
                currentUserId: appState?.currentUser?.id,
                accessToken: token
            )
            guard generation == loadGeneration else { return }
            // Server-side cursor pagination is by `created_at`; new posts
            // arriving in real time would still be safe to merge by id.
            let existingIds = Set(posts.map(\.id))
            let newOnes = page.posts.filter { !existingIds.contains($0.id) }
            posts.append(contentsOf: newOnes)
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
        } catch {
            guard generation == loadGeneration else { return }
            handle(error)
        }
    }

    /// Pull-to-refresh.
    func refresh() async {
        nextCursor = nil
        hasMore = true
        await loadInitialFeed()
    }

    // MARK: - Filter

    /// Switch the feed to a hashtag filter and reload. The view shows an
    /// "active filter" pill while a non-default filter is in effect.
    func selectHashtag(_ name: String) async {
        let normalized = name.lowercased()
        guard filter != .hashtag(normalized) else { return }
        filter = .hashtag(normalized)
        nextCursor = nil
        hasMore = true
        await loadInitialFeed()
    }

    /// Reset to the default public feed.
    func clearFilter() async {
        guard !filter.isDefault else { return }
        filter = .publicFeed
        nextCursor = nil
        hasMore = true
        await loadInitialFeed()
    }

    // MARK: - Likes (optimistic)

    /// Flips `hasLiked` and ±1 to `likesCount` immediately, fires the API
    /// call, then reverts on error so the heart can't get out of sync with
    /// what the server actually recorded.
    func togglePostLike(_ post: CommunityPost) async {
        guard let token = appState?.accessToken,
              let index = posts.firstIndex(where: { $0.id == post.id }) else { return }

        let snapshot = posts[index]
        let wasLiked = snapshot.liked
        posts[index].hasLiked = !wasLiked
        posts[index].likesCount = max(0, snapshot.likesCount + (wasLiked ? -1 : 1))

        do {
            let response = try await service.togglePostLike(postId: post.id, accessToken: token)
            guard let now = posts.firstIndex(where: { $0.id == post.id }) else { return }
            posts[now].hasLiked = response.liked
            posts[now].likesCount = response.likesCount
        } catch {
            // Revert the optimistic mutation.
            if let now = posts.firstIndex(where: { $0.id == post.id }) {
                posts[now].hasLiked = snapshot.hasLiked
                posts[now].likesCount = snapshot.likesCount
            }
            handle(error)
        }
    }

    // MARK: - Create / delete posts

    /// Calls `create-post`; on success prepends the result to the feed.
    /// Caller (`PostEditorPopup`) is responsible for uploading any PDF
    /// attachments first and passing their note IDs in.
    @discardableResult
    func createPost(_ request: CreatePostRequest) async throws -> CommunityPost {
        guard let token = appState?.accessToken else {
            throw CommunityError.unauthorized
        }
        let created = try await service.createPost(request, accessToken: token)
        // The create-post response omits `author`, so backfill it with the
        // current user's name from `AppState.profile` so the feed renders
        // the post correctly without a follow-up fetch.
        var withAuthor = created
        if let me = appState?.profile {
            withAuthor.author = PostAuthor(id: me.id, name: me.displayName)
        }
        posts.insert(withAuthor, at: 0)
        return withAuthor
    }

    /// Soft-deletes a post and removes it from the local feed on success.
    func deletePost(_ post: CommunityPost) async {
        guard let token = appState?.accessToken else { return }
        do {
            _ = try await service.deletePost(id: post.id, accessToken: token)
            posts.removeAll { $0.id == post.id }
        } catch {
            handle(error, notFound: "This post is no longer available")
        }
    }

    // MARK: - Helpers

    /// Apply a server-returned post (e.g. after fetching its detail) on top
    /// of whatever is currently in the feed, so likes/comments counts stay
    /// in sync without dropping the user's scroll position.
    func upsert(_ post: CommunityPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
    }

    /// Increment a post's `commentsCount` (used after creating a comment).
    func bumpCommentCount(postId: String, by delta: Int) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        posts[index].commentsCount = max(0, posts[index].commentsCount + delta)
    }

    private func handle(
        _ error: Error,
        forbidden: String = "You don't have permission to do that.",
        notFound: String = "That post is no longer available"
    ) {
        let mapped = mapCommunityError(error, forbidden: forbidden, notFound: notFound)
        if case .notFound = mapped {
            // Drop the missing post from the local feed so the user isn't
            // staring at a tombstone.
            // (Caller's notFound copy implies the most-recent post id is
            // not in the feed any more.)
        }
        feedError = mapped.userMessage
    }
}
