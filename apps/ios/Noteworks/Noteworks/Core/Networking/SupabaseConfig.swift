//
//  SupabaseConfig.swift
//  Noteworks
//
//  Created on 2026-03-18.
//

import Foundation

enum SupabaseConfig {
    static let baseURL = "https://app.noteworks.studio"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y"

    static let functionsBase = "\(baseURL)/functions/v1"
    static let authBase = "\(baseURL)/auth/v1"

    static var submitOnboardingURL: URL {
        URL(string: "\(functionsBase)/submit-onboarding")!
    }

    static var resolveCourseURL: URL {
        URL(string: "\(functionsBase)/resolve-course")!
    }

    static var getUserProfileURL: URL {
        URL(string: "\(functionsBase)/get-user-profile")!
    }

    /// Refresh-token grant endpoint. Used by `AuthService.refreshSession` and
    /// `APIClient`'s one-shot 401 retry.
    static var refreshTokenURL: URL {
        URL(string: "\(authBase)/token?grant_type=refresh_token")!
    }

    static func getSchoolsURL(search: String, page: Int = 1, pageSize: Int = 10) -> URL {
        var components = URLComponents(string: "\(functionsBase)/get-schools")!
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
        ]
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "search", value: trimmed))
        }
        components.queryItems = items
        return components.url!
    }

    static func uploadNotePDFURL(noteId: String, filename: String? = nil, courseId: String? = nil) -> URL {
        var components = URLComponents(string: "\(functionsBase)/upload-note-pdf")!
        var items = [URLQueryItem(name: "note_id", value: noteId)]
        if let filename { items.append(URLQueryItem(name: "filename", value: filename)) }
        if let courseId { items.append(URLQueryItem(name: "course_id", value: courseId)) }
        components.queryItems = items
        return components.url!
    }

    static func getNotePDFURL(noteId: String, expiresIn: Int? = nil) -> URL {
        var components = URLComponents(string: "\(functionsBase)/get-note-pdf-url")!
        var items = [URLQueryItem(name: "note_id", value: noteId)]
        if let expiresIn { items.append(URLQueryItem(name: "expires_in", value: "\(expiresIn)")) }
        components.queryItems = items
        return components.url!
    }

    static var gapDetectURL: URL {
        URL(string: "\(functionsBase)/gap-detect")!
    }

    /// `POST /upload-avatar` — uploads image bytes as the request body
    /// (Content-Type must be the image's MIME type), writes the file to
    /// the `avatars` storage bucket, and sets `users.avatar_url`.
    static var uploadAvatarURL: URL {
        URL(string: "\(functionsBase)/upload-avatar")!
    }

    /// `POST /upload-post-media` — uploads a single image as the request
    /// body (Content-Type = image MIME). Returns the `storage_path` to
    /// pass back to `create-post` in `media_paths[]`.
    static var uploadPostMediaURL: URL {
        URL(string: "\(functionsBase)/upload-post-media")!
    }

    // MARK: - Community endpoints

    /// `GET /get-posts` with the filters described in
    /// [docs/Community_Posts_Guide.md]. Every parameter is optional — pass
    /// only the ones the active `FeedFilter` requires.
    static func getPostsURL(
        cursor: String? = nil,
        limit: Int = 20,
        userId: String? = nil,
        hashtag: String? = nil,
        courseId: String? = nil,
        likedByMe: Bool = false,
        includeOwnPrivate: Bool = false
    ) -> URL {
        var components = URLComponents(string: "\(functionsBase)/get-posts")!
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let userId { items.append(URLQueryItem(name: "user_id", value: userId)) }
        if let hashtag { items.append(URLQueryItem(name: "hashtag", value: hashtag)) }
        if let courseId { items.append(URLQueryItem(name: "course_id", value: courseId)) }
        if likedByMe { items.append(URLQueryItem(name: "liked_by_me", value: "true")) }
        if includeOwnPrivate { items.append(URLQueryItem(name: "include_own_private", value: "true")) }
        components.queryItems = items
        return components.url!
    }

    static func getPostURL(postId: String) -> URL {
        var components = URLComponents(string: "\(functionsBase)/get-post")!
        components.queryItems = [URLQueryItem(name: "post_id", value: postId)]
        return components.url!
    }

    static var createPostURL: URL {
        URL(string: "\(functionsBase)/create-post")!
    }

    static var updatePostURL: URL {
        URL(string: "\(functionsBase)/update-post")!
    }

    static func deletePostURL(postId: String) -> URL {
        var components = URLComponents(string: "\(functionsBase)/delete-post")!
        components.queryItems = [URLQueryItem(name: "post_id", value: postId)]
        return components.url!
    }

    static var likePostURL: URL {
        URL(string: "\(functionsBase)/like-post")!
    }

    static var likeCommentURL: URL {
        URL(string: "\(functionsBase)/like-comment")!
    }

    static func getCommentsURL(postId: String, cursor: String? = nil, limit: Int = 50) -> URL {
        var components = URLComponents(string: "\(functionsBase)/get-comments")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "post_id", value: postId),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        return components.url!
    }

    static var createCommentURL: URL {
        URL(string: "\(functionsBase)/create-comment")!
    }

    static func deleteCommentURL(commentId: String) -> URL {
        var components = URLComponents(string: "\(functionsBase)/delete-comment")!
        components.queryItems = [URLQueryItem(name: "comment_id", value: commentId)]
        return components.url!
    }

    static func searchHashtagsURL(prefix: String, limit: Int = 10) -> URL {
        var components = URLComponents(string: "\(functionsBase)/search-hashtags")!
        components.queryItems = [
            URLQueryItem(name: "q", value: prefix),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        return components.url!
    }

    /// `GET /search-posts?q=…&limit=…&cursor=…`. Returns the same
    /// `FeedPage` shape as `get-posts`, so callers can reuse the feed UI
    /// to render search hits.
    static func searchPostsURL(query: String, cursor: String? = nil, limit: Int = 20) -> URL {
        var components = URLComponents(string: "\(functionsBase)/search-posts")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        return components.url!
    }
}
