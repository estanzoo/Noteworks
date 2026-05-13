//
//  CommunityService.swift
//  Noteworks
//
//  Thin wrapper around `APIClient` for the community Edge Functions
//  described in docs/Community_Posts_Guide.md. One method per endpoint,
//  all `async throws`. Every method takes an `accessToken` so callers can
//  share the same token they already hold (and so this service stays
//  free of `AppState` couplings).
//

import Foundation

protocol CommunityServiceProtocol {
    func fetchFeed(filter: FeedFilter, cursor: String?, limit: Int, currentUserId: String?, accessToken: String) async throws -> FeedPage
    func fetchPost(id: String, accessToken: String) async throws -> CommunityPost
    func createPost(_ request: CreatePostRequest, accessToken: String) async throws -> CommunityPost
    func updatePost(_ request: UpdatePostRequest, accessToken: String) async throws -> CommunityPost
    func deletePost(id: String, accessToken: String) async throws -> DeleteResponse
    func togglePostLike(postId: String, accessToken: String) async throws -> LikeResponse
    func fetchComments(postId: String, cursor: String?, limit: Int, accessToken: String) async throws -> CommentPage
    func createComment(_ request: CreateCommentRequest, accessToken: String) async throws -> CommunityComment
    func deleteComment(id: String, accessToken: String) async throws -> DeleteResponse
    func searchHashtags(prefix: String, limit: Int, accessToken: String) async throws -> [HashtagSuggestion]
}

final class CommunityService: CommunityServiceProtocol {
    static let shared = CommunityService()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    // MARK: - Posts

    /// `GET /get-posts`. `currentUserId` is only consulted when the filter
    /// is `.ownIncludingPrivate` (so the server's `user_id` parameter
    /// matches who's making the request).
    func fetchFeed(
        filter: FeedFilter,
        cursor: String?,
        limit: Int = 20,
        currentUserId: String?,
        accessToken: String
    ) async throws -> FeedPage {
        let url: URL
        switch filter {
        case .publicFeed:
            url = SupabaseConfig.getPostsURL(cursor: cursor, limit: limit)
        case .hashtag(let name):
            url = SupabaseConfig.getPostsURL(cursor: cursor, limit: limit, hashtag: name)
        case .course(let id):
            url = SupabaseConfig.getPostsURL(cursor: cursor, limit: limit, courseId: id)
        case .user(let id):
            url = SupabaseConfig.getPostsURL(cursor: cursor, limit: limit, userId: id)
        case .likedByMe:
            url = SupabaseConfig.getPostsURL(cursor: cursor, limit: limit, likedByMe: true)
        case .ownIncludingPrivate(let id):
            url = SupabaseConfig.getPostsURL(
                cursor: cursor,
                limit: limit,
                userId: id,
                includeOwnPrivate: true
            )
        }
        return try await api.get(url, accessToken: accessToken)
    }

    func fetchPost(id: String, accessToken: String) async throws -> CommunityPost {
        try await api.get(SupabaseConfig.getPostURL(postId: id), accessToken: accessToken)
    }

    func createPost(_ request: CreatePostRequest, accessToken: String) async throws -> CommunityPost {
        try await api.post(SupabaseConfig.createPostURL, body: request, accessToken: accessToken)
    }

    func updatePost(_ request: UpdatePostRequest, accessToken: String) async throws -> CommunityPost {
        try await api.patch(SupabaseConfig.updatePostURL, body: request, accessToken: accessToken)
    }

    func deletePost(id: String, accessToken: String) async throws -> DeleteResponse {
        try await api.delete(SupabaseConfig.deletePostURL(postId: id), accessToken: accessToken)
    }

    // MARK: - Likes

    func togglePostLike(postId: String, accessToken: String) async throws -> LikeResponse {
        try await api.post(
            SupabaseConfig.likePostURL,
            body: LikePostRequest(postId: postId),
            accessToken: accessToken
        )
    }

    // MARK: - Comments

    func fetchComments(
        postId: String,
        cursor: String? = nil,
        limit: Int = 50,
        accessToken: String
    ) async throws -> CommentPage {
        try await api.get(
            SupabaseConfig.getCommentsURL(postId: postId, cursor: cursor, limit: limit),
            accessToken: accessToken
        )
    }

    func createComment(_ request: CreateCommentRequest, accessToken: String) async throws -> CommunityComment {
        try await api.post(SupabaseConfig.createCommentURL, body: request, accessToken: accessToken)
    }

    func deleteComment(id: String, accessToken: String) async throws -> DeleteResponse {
        try await api.delete(SupabaseConfig.deleteCommentURL(commentId: id), accessToken: accessToken)
    }

    // MARK: - Hashtags

    func searchHashtags(prefix: String, limit: Int = 10, accessToken: String) async throws -> [HashtagSuggestion] {
        let response: HashtagSearchResponse = try await api.get(
            SupabaseConfig.searchHashtagsURL(prefix: prefix, limit: limit),
            accessToken: accessToken
        )
        return response.hashtags
    }
}
