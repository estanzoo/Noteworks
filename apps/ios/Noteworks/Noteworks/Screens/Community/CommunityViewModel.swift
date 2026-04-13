//
//  CommunityViewModel.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import Foundation

struct CommunityPost: Identifiable {
    let id: Int
    let user: String
    let school: String
    let major: String
    let title: String
    let body: String?
    let tags: [String]
    var likes: Int
    var comments: Int
}

@MainActor
class CommunityViewModel: ObservableObject {
    @Published var posts: [CommunityPost] = CommunityViewModel.samplePosts

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
            comments: 0
        )
        posts.insert(post, at: 0)
    }

    private static let samplePosts: [CommunityPost] = [
        CommunityPost(
            id: 1, user: "Alex Chen",
            school: "Royal Academy of Arts",
            major: "MA Information Experience Design",
            title: "The group discussion today was extremely interesting！！",
            body: nil,
            tags: ["Course", "Course"],
            likes: 12, comments: 3
        ),
        CommunityPost(
            id: 2, user: "Alex Chen",
            school: "Royal Academy of Arts",
            major: "MA Information Experience Design",
            title: "Does anyone actually understand Kant?",
            body: "I've reread the \"Groundwork\" three times and my brain is melting. If anyone has a simple summary or a breakdown of the categorical imperative, please share. My essay is due Friday and I'm lost.",
            tags: ["Course"],
            likes: 24, comments: 8
        ),
        CommunityPost(
            id: 3, user: "Sam Lee",
            school: "MIT",
            major: "BS Computer Science",
            title: "Just discovered the best study technique",
            body: "Spaced repetition + active recall + NoteWorks AI summaries = unbeatable combo. Went from C+ to A- in organic chem.",
            tags: ["Study Tips"],
            likes: 45, comments: 15
        ),
        CommunityPost(
            id: 4, user: "Amy Wang",
            school: "Stanford",
            major: "MS Biology",
            title: "Anyone taking Cell Bio with Prof. Martinez?",
            body: "Looking for study group partners. The midterm is in 2 weeks and I have 16 pages of notes to review.",
            tags: ["Biology"],
            likes: 8, comments: 5
        ),
        CommunityPost(
            id: 5, user: "Jordan Park",
            school: "NYU",
            major: "BA Philosophy",
            title: "Hot take: Nietzsche is overrated",
            body: "There, I said it. Change my mind in the comments.",
            tags: ["Philosophy"],
            likes: 67, comments: 32
        ),
        CommunityPost(
            id: 6, user: "Lisa Zhang",
            school: "Caltech",
            major: "BS Physics",
            title: "Lab report template that saved my life",
            body: "Sharing my physics lab report template. It follows the standard format and has built-in sections for error analysis.",
            tags: ["Physics", "Course"],
            likes: 31, comments: 11
        ),
    ]
}
