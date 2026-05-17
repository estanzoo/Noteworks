//
//  ProfileData.swift
//  Noteworks
//
//  Mirrors PROFILE_INITIAL from others/noteworks-library(2).jsx (L112–L154).
//

import Foundation

// MARK: - Models

struct Profile: Equatable {
    var name: String
    var email: String
    /// Optimistic local cache of the freshly-picked photo, used while
    /// `upload-avatar` is in flight (so the UI updates instantly). Once
    /// the server returns a URL we drop the bytes in favour of
    /// `avatarUrl`, which is the canonical, shareable source.
    var photoData: Data?
    /// Server-backed avatar URL (mirrors `users.avatar_url`). Set after a
    /// successful upload-avatar response or on profile hydrate.
    var avatarUrl: String?
    var bio: String
    var school: String
    var major: String
    var grade: String
    var subscription: Subscription
    var credits: Credits
    var security: SecurityLinks
    var referral: Referral
    var language: String
    var version: String
}

struct Subscription: Equatable {
    var plan: String
    var status: String
    var renewsOn: String
}

struct Credits: Equatable {
    var balance: Int
    var history: [CreditEntry]
    var usage: [CreditUsage]
}

struct CreditEntry: Identifiable, Equatable {
    let id: Int
    var label: String
    var detail: String
    var delta: Int
}

struct CreditUsage: Identifiable, Equatable {
    let id: Int
    var label: String
    var used: Int
    var total: Int
    var detail: String
}

struct SecurityLinks: Equatable {
    var googleLinked: Bool
    var appleLinked: Bool
    var notionLinked: Bool

    var linkedCount: Int {
        [googleLinked, appleLinked, notionLinked].filter { $0 }.count
    }
}

struct Referral: Equatable {
    var code: String
    var invited: Int
    var pending: Int
    var rewardCopy: String
    var invites: [Invite]
}

struct Invite: Identifiable, Equatable {
    let id: Int
    var name: String
    var invitedOn: String
    var status: String // "Activated" or "Pending"
}

// MARK: - Initial Data

extension Profile {
    /// Blank initial state — every identity field is empty so a brand-
    /// new user never briefly sees the previous "Hao Guan Cheng"
    /// placeholder before `ProfileViewModel.hydrate(from:)` fills in
    /// the real values from `AppState.profile`. Subscription / credits
    /// / referral / security objects exist (so the UI can render rows
    /// without optional-chaining everywhere) but they're zeroed —
    /// they'll start filling in once those backend features ship.
    static let initial = Profile(
        name: "",
        email: "",
        photoData: nil,
        avatarUrl: nil,
        bio: "",
        school: "",
        major: "",
        grade: "",
        subscription: Subscription(
            plan: "Free",
            status: "Active",
            renewsOn: ""
        ),
        credits: Credits(
            balance: 0,
            history: [],
            usage: []
        ),
        security: SecurityLinks(googleLinked: false, appleLinked: false, notionLinked: false),
        referral: Referral(
            code: "",
            invited: 0,
            pending: 0,
            rewardCopy: "Earn credits for every friend who joins NoteWorks.",
            invites: []
        ),
        language: "English",
        version: "NoteWorks Beta 0.9.4 (Build 214)"
    )

    /// Preview-only seed kept around for SwiftUI canvas and design
    /// inspection. Never reaches a real user. Mirrors the JSX
    /// `PROFILE_INITIAL` placeholder so designers can see the layout
    /// populated when iterating.
    static let previewSample = Profile(
        name: "Hao Guan Cheng",
        email: "haoguan@arts.ac.uk",
        photoData: nil,
        avatarUrl: nil,
        bio: "Designing a calmer study flow with visual notes, quick recall, and a little bit of AI help.",
        school: "Royal Academy of Arts",
        major: "Information Experience Design",
        grade: "Graduate Year 1",
        subscription: Subscription(
            plan: "NoteWorks Pro",
            status: "Active",
            renewsOn: "APR.30  2026"
        ),
        credits: Credits(
            balance: 128,
            history: [
                CreditEntry(id: 1, label: "Referral bonus",       detail: "Invited Amy to join NoteWorks",        delta: +40),
                CreditEntry(id: 2, label: "Monthly plan credit",  detail: "Pro subscription refill",              delta: +120),
                CreditEntry(id: 3, label: "AI summary pack",      detail: "Cell Biology study set",               delta: -18),
                CreditEntry(id: 4, label: "Practice quiz pack",   detail: "Organic Chem self-test generation",    delta: -14),
            ],
            usage: [
                CreditUsage(id: 1, label: "AI Summaries",   used: 18, total: 40, detail: "Great for dense readings"),
                CreditUsage(id: 2, label: "Citation Assist", used: 14, total: 25, detail: "Essay workflow support"),
                CreditUsage(id: 3, label: "Practice Quiz",   used: 10, total: 20, detail: "Quick self-checks before class"),
            ]
        ),
        security: SecurityLinks(googleLinked: true, appleLinked: false, notionLinked: true),
        referral: Referral(
            code: "NOTE-HCG-2026",
            invited: 3,
            pending: 1,
            rewardCopy: "Earn 40 credits for every friend who activates a Pro trial.",
            invites: [
                Invite(id: 1, name: "Amy Zhang",  invitedOn: "APR.14  2026", status: "Activated"),
                Invite(id: 2, name: "Sam Lee",    invitedOn: "APR.11  2026", status: "Activated"),
                Invite(id: 3, name: "Nina Patel", invitedOn: "APR.08  2026", status: "Activated"),
                Invite(id: 4, name: "Leo Chen",   invitedOn: "APR.16  2026", status: "Pending"),
            ]
        ),
        language: "English",
        version: "NoteWorks Beta 0.9.4 (Build 214)"
    )
}

// MARK: - Constants

let LANGUAGE_OPTIONS: [String] = ["English", "简体中文", "日本語", "한국어"]

// MARK: - Helpers

/// Mirrors `isAcademicEmail` from the JSX (L332–L341).
func isAcademicEmail(_ email: String) -> Bool {
    let normalized = email.trimmingCharacters(in: .whitespaces).lowercased()
    guard normalized.contains("@") else { return false }
    let domain = normalized.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        .dropFirst().first.map(String.init) ?? ""
    return domain.hasSuffix(".edu")
        || domain.contains(".edu.")
        || domain.hasPrefix("edu.")
        || domain.contains(".ac.")
        || domain.hasSuffix(".ac")
}

/// Returns the initials used in `AvatarBadge` (JSX L343–L350).
func profileInitials(from name: String) -> String {
    let source = name.isEmpty ? "NoteWorks" : name
    let parts = source.split(separator: " ").prefix(2)
    return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
}
