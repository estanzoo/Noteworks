//
//  CommunityModels.swift
//  Noteworks
//
//  Mirrors the JSON shapes returned by the community Edge Functions
//  (see docs/Community_Posts_Guide.md). Decoded by `APIClient`, which has
//  `keyDecodingStrategy = .convertFromSnakeCase` and `dateDecodingStrategy
//  = .iso8601` already configured, so Swift property names map one-for-one
//  to the server's snake_case fields.
//

import Foundation

// MARK: - Author

struct PostAuthor: Codable, Equatable, Identifiable {
    let id: String
    /// Optional because the server joins `users.name`, which is itself
    /// nullable — newly signed-up users haven't picked a display name yet,
    /// in which case the server returns `name: null`.
    let name: String?
}

// MARK: - Attachment

/// A note attached to a post. The server links posts to notes via the
/// `post_attachments` table; each row includes whether the note has a PDF
/// uploaded so the UI can decide whether to show a "View PDF" affordance.
struct PostAttachment: Codable, Equatable, Identifiable {
    let noteId: String
    let title: String
    let hasPdf: Bool
    let pdfFilename: String?

    var id: String { noteId }
}

// MARK: - Post

/// A community post as returned by `get-posts`, `get-post`, `create-post`,
/// and `update-post`. `create-post` doesn't include `author` or `has_liked`
/// in its response, so those are optional on decode but always present on
/// feed reads — the view model fills them in when needed.
struct CommunityPost: Codable, Equatable, Identifiable {
    let id: String
    let userId: String
    var author: PostAuthor?
    var title: String
    var body: String
    var visibility: String
    var courseId: String?
    var likesCount: Int
    var commentsCount: Int
    /// `false` on `create-post` responses (server doesn't include it), but
    /// present on feed reads.
    var hasLiked: Bool?
    var hashtags: [String]
    /// `create-post` returns `[String]` (just the note IDs) instead of full
    /// `PostAttachment` rows; feed/detail reads return the full structure.
    /// The custom decoder below collapses both into `attachments` so the
    /// rest of the app deals with a single shape.
    var attachments: [PostAttachment]
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId, author, title, body, visibility, courseId
        case likesCount, commentsCount, hasLiked, hashtags
        case attachments, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        author = try c.decodeIfPresent(PostAuthor.self, forKey: .author)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        visibility = try c.decode(String.self, forKey: .visibility)
        courseId = try c.decodeIfPresent(String.self, forKey: .courseId)
        likesCount = try c.decode(Int.self, forKey: .likesCount)
        commentsCount = try c.decode(Int.self, forKey: .commentsCount)
        hasLiked = try c.decodeIfPresent(Bool.self, forKey: .hasLiked)
        hashtags = try c.decodeIfPresent([String].self, forKey: .hashtags) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)

        // `attachments` is `[String]` on create-post responses and
        // `[PostAttachment]` on feed reads. Accept both.
        if let full = try? c.decode([PostAttachment].self, forKey: .attachments) {
            attachments = full
        } else if let ids = try? c.decode([String].self, forKey: .attachments) {
            attachments = ids.map {
                PostAttachment(noteId: $0, title: "", hasPdf: false, pdfFilename: nil)
            }
        } else {
            attachments = []
        }
    }

    init(
        id: String,
        userId: String,
        author: PostAuthor?,
        title: String,
        body: String,
        visibility: String,
        courseId: String?,
        likesCount: Int,
        commentsCount: Int,
        hasLiked: Bool?,
        hashtags: [String],
        attachments: [PostAttachment],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.author = author
        self.title = title
        self.body = body
        self.visibility = visibility
        self.courseId = courseId
        self.likesCount = likesCount
        self.commentsCount = commentsCount
        self.hasLiked = hasLiked
        self.hashtags = hashtags
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension CommunityPost {
    /// True if the current user has liked this post (defaults to false when
    /// the server omits `has_liked`).
    var liked: Bool { hasLiked ?? false }

    /// Convenience for the heart/avatar UI — falls back to "Anonymous" if
    /// the server hasn't populated the joined author row, or if the user
    /// hasn't set a display name yet (server returns `name: null`).
    var authorName: String {
        if let name = author?.name, !name.isEmpty { return name }
        return "Anonymous"
    }
}

// MARK: - Comment

/// A threaded comment. The server returns top-level comments at the root
/// with their replies nested in `replies` (which can themselves have
/// `replies` arbitrarily deep).
struct CommunityComment: Codable, Equatable, Identifiable {
    let id: String
    let postId: String
    let userId: String
    let author: PostAuthor
    let parentCommentId: String?
    var body: String
    var likesCount: Int
    /// `create-comment` doesn't include `has_liked` (the user just made the
    /// comment, so it's implicitly false); `get-comments` always does.
    var hasLiked: Bool?
    var visibility: String
    let createdAt: Date
    var updatedAt: Date
    /// Server returns nested replies; on `create-comment` responses this
    /// field is absent, so we default to an empty array on decode.
    var replies: [CommunityComment] = []

    enum CodingKeys: String, CodingKey {
        case id, postId, userId, author, parentCommentId
        case body, likesCount, hasLiked, visibility, createdAt, updatedAt, replies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        postId = try c.decode(String.self, forKey: .postId)
        userId = try c.decode(String.self, forKey: .userId)
        author = try c.decode(PostAuthor.self, forKey: .author)
        parentCommentId = try c.decodeIfPresent(String.self, forKey: .parentCommentId)
        body = try c.decode(String.self, forKey: .body)
        likesCount = try c.decode(Int.self, forKey: .likesCount)
        hasLiked = try c.decodeIfPresent(Bool.self, forKey: .hasLiked)
        visibility = try c.decode(String.self, forKey: .visibility)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        replies = try c.decodeIfPresent([CommunityComment].self, forKey: .replies) ?? []
    }

    init(
        id: String,
        postId: String,
        userId: String,
        author: PostAuthor,
        parentCommentId: String?,
        body: String,
        likesCount: Int,
        hasLiked: Bool? = nil,
        visibility: String,
        createdAt: Date,
        updatedAt: Date,
        replies: [CommunityComment] = []
    ) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.author = author
        self.parentCommentId = parentCommentId
        self.body = body
        self.likesCount = likesCount
        self.hasLiked = hasLiked
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.replies = replies
    }
}

extension CommunityComment {
    /// True if the current user has liked this comment. Defaults to false
    /// when the server omits `has_liked` (e.g. on `create-comment` responses).
    var liked: Bool { hasLiked ?? false }

    /// Recursive count of this comment + all nested replies.
    var threadCount: Int {
        1 + replies.reduce(0) { $0 + $1.threadCount }
    }

    /// Display name with the same fallback rules as `CommunityPost.authorName`.
    /// Necessary because the server returns `author.name: null` for users
    /// who haven't set a display name yet.
    var authorName: String {
        if let name = author.name, !name.isEmpty { return name }
        return "Anonymous"
    }
}

// MARK: - Hashtag

struct HashtagSuggestion: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let postCount: Int
}

// MARK: - Feed page

/// One page of the cursor-paginated post feed. `nextCursor == nil` means
/// the end of the feed has been reached.
struct FeedPage: Codable, Equatable {
    let posts: [CommunityPost]
    let nextCursor: String?
}

/// One page of comments for a post. Top-level comments only — replies are
/// inlined inside each comment's `replies` array.
struct CommentPage: Codable, Equatable {
    let comments: [CommunityComment]
    let nextCursor: String?
}

struct HashtagSearchResponse: Codable, Equatable {
    let hashtags: [HashtagSuggestion]
}

struct LikeResponse: Codable, Equatable {
    let liked: Bool
    let likesCount: Int
}

struct DeleteResponse: Codable, Equatable {
    let message: String
    let postId: String?
    let commentId: String?
}

// MARK: - Feed filter

/// What the user is currently looking at. Maps directly to the query
/// parameters of `get-posts`.
enum FeedFilter: Equatable {
    case publicFeed
    case hashtag(String)
    case course(String)
    case user(String)
    case likedByMe
    case ownIncludingPrivate(String)

    var displayName: String? {
        switch self {
        case .publicFeed: return nil
        case .hashtag(let name): return "#\(name)"
        case .course(let id): return "Course · \(id.prefix(6))"
        case .user(let id): return "User · \(id.prefix(6))"
        case .likedByMe: return "Liked by me"
        case .ownIncludingPrivate: return "My posts"
        }
    }

    var isDefault: Bool {
        if case .publicFeed = self { return true }
        return false
    }
}

// MARK: - Request bodies

struct CreatePostRequest: Encodable {
    let title: String
    let body: String
    let visibility: String
    let courseId: String?
    let attachmentNoteIds: [String]?
    let hashtags: [String]?

    enum CodingKeys: String, CodingKey {
        case title, body, visibility
        case courseId = "course_id"
        case attachmentNoteIds = "attachment_note_ids"
        case hashtags
    }
}

struct UpdatePostRequest: Encodable {
    let postId: String
    var title: String?
    var body: String?
    var visibility: String?
    var courseId: String?
    var attachmentNoteIds: [String]?
    var hashtags: [String]?

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case title, body, visibility
        case courseId = "course_id"
        case attachmentNoteIds = "attachment_note_ids"
        case hashtags
    }
}

struct LikePostRequest: Encodable {
    let postId: String

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
    }
}

struct LikeCommentRequest: Encodable {
    let commentId: String

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
    }
}

struct CreateCommentRequest: Encodable {
    let postId: String
    let body: String
    let parentCommentId: String?

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case body
        case parentCommentId = "parent_comment_id"
    }
}
