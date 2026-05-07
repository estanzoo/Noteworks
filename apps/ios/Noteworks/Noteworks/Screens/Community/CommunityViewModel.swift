//
//  CommunityViewModel.swift
//  Noteworks
//
//  Mirrors the community state in others/noteworks-library(2).jsx:
//  - `PROFILE_INITIAL`-style post list with tags, attachments, comment threads
//  - `createCommunityMeta`, `countCommunityThreadItems`, `updateCommunityThread`
//  - `togglePostReaction`, `toggleConnect`, `addComment`, `addReply`,
//    `toggleCommentReaction` actions.
//

import Foundation

// MARK: - Reactions

enum ReactionKind: String, Equatable {
    case like, dislike
}

// MARK: - Attachments

enum CommunityAttachmentKind: String, Equatable {
    case image, video, document, note
}

struct CommunityAttachment: Identifiable, Equatable {
    let id: String
    let kind: CommunityAttachmentKind
    var name: String = ""
    var url: String? = nil
    var size: String? = nil
    var ext: String? = nil
    var subject: String? = nil
}

// MARK: - Comment thread

struct CommunityComment: Identifiable, Equatable {
    let id: String
    var user: String
    var school: String
    var time: String
    var text: String
    var likes: Int
    var dislikes: Int
    var userReaction: ReactionKind?
    var author: Bool
    var replies: [CommunityComment]
}

// MARK: - Post

struct CommunityPost: Identifiable, Equatable {
    let id: Int
    var user: String
    var school: String
    var major: String
    var title: String
    var body: String?
    var tags: [String]
    var likes: Int
    var dislikes: Int
    var userReaction: ReactionKind?
    var connected: Bool
    var attachments: [CommunityAttachment]
    var commentThread: [CommunityComment]
}

extension CommunityPost {
    /// Total count including nested replies (mirrors `countCommunityThreadItems`).
    var commentCount: Int {
        countCommunityThreadItems(commentThread)
    }
}

/// Free-function mirror of `countCommunityThreadItems` (JSX L4275–L4277).
/// Lives outside `CommunityViewModel` so it can be used from non-isolated
/// `Equatable`/property contexts (e.g. on `CommunityPost`).
func countCommunityThreadItems(_ thread: [CommunityComment]) -> Int {
    thread.reduce(0) { $0 + 1 + countCommunityThreadItems($1.replies) }
}

// MARK: - View Model

@MainActor
class CommunityViewModel: ObservableObject {
    @Published var posts: [CommunityPost] = CommunityViewModel.samplePosts

    // MARK: Author a post

    func addPost(title: String, body: String?, tags: [String]) {
        let post = CommunityPost(
            id: Int(Date().timeIntervalSince1970),
            user: "You",
            school: "Your School",
            major: "Your Major",
            title: title,
            body: body,
            tags: tags.isEmpty ? ["General"] : tags,
            likes: 0,
            dislikes: 0,
            userReaction: nil,
            connected: false,
            attachments: [],
            commentThread: []
        )
        posts.insert(post, at: 0)
    }

    // MARK: Post reactions

    /// Mirrors `togglePostReaction` from the JSX (L4887–L4903).
    func togglePostReaction(postId: Int, reaction: ReactionKind) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        var post = posts[index]
        let current = post.userReaction
        if current == .like { post.likes = max(0, post.likes - 1) }
        if current == .dislike { post.dislikes = max(0, post.dislikes - 1) }
        let next: ReactionKind? = (current == reaction) ? nil : reaction
        if next == .like { post.likes += 1 }
        if next == .dislike { post.dislikes += 1 }
        post.userReaction = next
        posts[index] = post
    }

    // MARK: Connect / follow

    func toggleConnect(postId: Int) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        posts[index].connected.toggle()
    }

    // MARK: Comments

    /// Mirrors `addComment` (JSX L4921–L4946): inserts at the top of the thread.
    func addComment(postId: Int, text: String, currentUserName: String = "You", currentUserSchool: String = "Your School") {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        let postAuthor = posts[index].user
        let comment = CommunityComment(
            id: "\(postId)-comment-\(Int(Date().timeIntervalSince1970))",
            user: currentUserName,
            school: currentUserSchool,
            time: "now",
            text: trimmed,
            likes: 0,
            dislikes: 0,
            userReaction: nil,
            author: currentUserName == postAuthor,
            replies: []
        )
        posts[index].commentThread.insert(comment, at: 0)
    }

    /// Mirrors `addReply` (JSX L4948–L4978).
    func addReply(postId: Int, commentId: String, text: String, currentUserName: String = "You", currentUserSchool: String = "Your School") {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        let postAuthor = posts[index].user
        let reply = CommunityComment(
            id: "\(commentId)-reply-\(Int(Date().timeIntervalSince1970))",
            user: currentUserName,
            school: currentUserSchool,
            time: "now",
            text: trimmed,
            likes: 0,
            dislikes: 0,
            userReaction: nil,
            author: currentUserName == postAuthor,
            replies: []
        )
        posts[index].commentThread = Self.updateThread(posts[index].commentThread, targetId: commentId) { comment in
            var copy = comment
            copy.replies.append(reply)
            return copy
        }
    }

    /// Mirrors `toggleCommentReaction` (JSX L4980–L4992).
    func toggleCommentReaction(postId: Int, targetId: String, reaction: ReactionKind) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        posts[index].commentThread = Self.updateThread(posts[index].commentThread, targetId: targetId) { item in
            Self.applyReaction(to: item, reaction: reaction)
        }
    }

    // MARK: Thread helpers

    /// Mirrors `updateCommunityThread` (JSX L4279–L4288): when `id` matches,
    /// return the transformed item and stop recursing; otherwise walk into replies.
    static func updateThread(_ thread: [CommunityComment], targetId: String, _ transform: (CommunityComment) -> CommunityComment) -> [CommunityComment] {
        thread.map { item in
            if item.id == targetId {
                return transform(item)
            }
            guard !item.replies.isEmpty else { return item }
            var copy = item
            copy.replies = updateThread(item.replies, targetId: targetId, transform)
            return copy
        }
    }

    /// Mirrors `toggleThreadReaction` (JSX L4290–L4309).
    static func applyReaction(to item: CommunityComment, reaction: ReactionKind) -> CommunityComment {
        var nextLikes = item.likes
        var nextDislikes = item.dislikes
        if item.userReaction == .like { nextLikes = max(0, nextLikes - 1) }
        if item.userReaction == .dislike { nextDislikes = max(0, nextDislikes - 1) }
        let nextReaction: ReactionKind? = (item.userReaction == reaction) ? nil : reaction
        if nextReaction == .like { nextLikes += 1 }
        if nextReaction == .dislike { nextDislikes += 1 }
        var copy = item
        copy.likes = nextLikes
        copy.dislikes = nextDislikes
        copy.userReaction = nextReaction
        return copy
    }

}

// MARK: - Sample data

extension CommunityViewModel {

    /// Mirrors `COMMUNITY_COMMENT_THREADS` from the JSX (L4129–L4266).
    static let sampleCommentThreads: [Int: [CommunityComment]] = [
        1: [
            CommunityComment(
                id: "1-c1", user: "Maya Liu", school: "Parsons", time: "12m ago",
                text: "Loved how concise this discussion recap is. It feels super easy to skim before class.",
                likes: 6, dislikes: 0, userReaction: nil, author: false,
                replies: [
                    CommunityComment(id: "1-r1", user: "Alex Chen", school: "Royal Academy of Arts",
                                     time: "8m ago",
                                     text: "That was the goal. I wanted something classmates could read in under a minute.",
                                     likes: 3, dislikes: 0, userReaction: nil, author: true, replies: []),
                    CommunityComment(id: "1-r2", user: "Jordan Park", school: "NYU",
                                     time: "6m ago",
                                     text: "The opening sentence especially works well.",
                                     likes: 1, dislikes: 0, userReaction: nil, author: false, replies: []),
                ]
            ),
            CommunityComment(
                id: "1-c2", user: "Grace Ho", school: "UCL", time: "3m ago",
                text: "Would you mind posting the follow-up reading list too?",
                likes: 2, dislikes: 0, userReaction: nil, author: false, replies: []
            ),
        ],
        2: [
            CommunityComment(
                id: "2-c1", user: "Kevin Xu", school: "Columbia", time: "25m ago",
                text: "I have a one-page summary of categorical imperative examples if you want it.",
                likes: 9, dislikes: 0, userReaction: nil, author: false,
                replies: [
                    CommunityComment(id: "2-r1", user: "Alex Chen", school: "Royal Academy of Arts",
                                     time: "17m ago",
                                     text: "Yes please, that would save me.",
                                     likes: 5, dislikes: 0, userReaction: nil, author: true, replies: []),
                ]
            ),
            CommunityComment(
                id: "2-c2", user: "Ella Stone", school: "King's College London", time: "11m ago",
                text: "Try mapping each version of the imperative to a really ordinary daily choice. It gets less abstract.",
                likes: 4, dislikes: 0, userReaction: nil, author: false,
                replies: [
                    CommunityComment(id: "2-r2", user: "Mina Park", school: "SNU",
                                     time: "9m ago",
                                     text: "Seconding this. It helped me a lot too.",
                                     likes: 1, dislikes: 0, userReaction: nil, author: false, replies: []),
                ]
            ),
        ],
        3: [
            CommunityComment(
                id: "3-c1", user: "Ava Patel", school: "Berkeley", time: "18m ago",
                text: "Can you share how you structure the active recall part?",
                likes: 3, dislikes: 0, userReaction: nil, author: false,
                replies: [
                    CommunityComment(id: "3-r1", user: "Sam Lee", school: "MIT",
                                     time: "10m ago",
                                     text: "I do a fast verbal recap first, then write 5 questions from memory.",
                                     likes: 4, dislikes: 0, userReaction: nil, author: true, replies: []),
                    CommunityComment(id: "3-r2", user: "Leo Kim", school: "Carnegie Mellon",
                                     time: "7m ago",
                                     text: "That sounds way more manageable than giant flashcard sets.",
                                     likes: 2, dislikes: 0, userReaction: nil, author: false, replies: []),
                ]
            ),
        ],
    ]

    static let samplePosts: [CommunityPost] = [
        CommunityPost(
            id: 1, user: "Alex Chen",
            school: "Royal Academy of Arts",
            major: "MA Information Experience Design",
            title: "The group discussion today was extremely interesting！！",
            body: nil,
            tags: ["Course", "Course"],
            likes: 12, dislikes: 0, userReaction: nil, connected: false,
            attachments: [],
            commentThread: sampleCommentThreads[1] ?? []
        ),
        CommunityPost(
            id: 2, user: "Alex Chen",
            school: "Royal Academy of Arts",
            major: "MA Information Experience Design",
            title: "Does anyone actually understand Kant?",
            body: "I've reread the \"Groundwork\" three times and my brain is melting. If anyone has a simple summary or a breakdown of the categorical imperative, please share. My essay is due Friday and I'm lost.",
            tags: ["Course"],
            likes: 24, dislikes: 0, userReaction: nil, connected: false,
            attachments: [],
            commentThread: sampleCommentThreads[2] ?? []
        ),
        CommunityPost(
            id: 3, user: "Sam Lee",
            school: "MIT",
            major: "BS Computer Science",
            title: "Just discovered the best study technique",
            body: "Spaced repetition + active recall + NoteWorks AI summaries = unbeatable combo. Went from C+ to A- in organic chem.",
            tags: ["Study Tips"],
            likes: 45, dislikes: 0, userReaction: nil, connected: false,
            attachments: [],
            commentThread: sampleCommentThreads[3] ?? []
        ),
        CommunityPost(
            id: 4, user: "Amy Wang",
            school: "Stanford",
            major: "MS Biology",
            title: "Anyone taking Cell Bio with Prof. Martinez?",
            body: "Looking for study group partners. The midterm is in 2 weeks and I have 16 pages of notes to review.",
            tags: ["Biology"],
            likes: 8, dislikes: 0, userReaction: nil, connected: false,
            attachments: [],
            commentThread: []
        ),
        CommunityPost(
            id: 5, user: "Jordan Park",
            school: "NYU",
            major: "BA Philosophy",
            title: "Hot take: Nietzsche is overrated",
            body: "There, I said it. Change my mind in the comments.",
            tags: ["Philosophy"],
            likes: 67, dislikes: 0, userReaction: nil, connected: false,
            attachments: [],
            commentThread: []
        ),
        CommunityPost(
            id: 6, user: "Lisa Zhang",
            school: "Caltech",
            major: "BS Physics",
            title: "Lab report template that saved my life",
            body: "Sharing my physics lab report template. It follows the standard format and has built-in sections for error analysis.",
            tags: ["Physics", "Course"],
            likes: 31, dislikes: 0, userReaction: nil, connected: false,
            attachments: [],
            commentThread: []
        ),
    ]
}

// MARK: - Name helper

/// Mirrors `nameToInitials` (JSX L4321–L4328).
func nameToInitials(_ name: String) -> String {
    let source = name.isEmpty ? "NW" : name
    let parts = source.split(separator: " ").prefix(2)
    return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
}
