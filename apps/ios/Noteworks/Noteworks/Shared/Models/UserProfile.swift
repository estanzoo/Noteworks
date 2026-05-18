//
//  UserProfile.swift
//  Noteworks
//
//  Mirrors the JSON shape returned by `GET /functions/v1/get-user-profile`
//  (see docs/Frontend_Auth_and_Onboarding_Guide.md step 3). Decoded by
//  `APIClient`, which has `keyDecodingStrategy = .convertFromSnakeCase` and
//  `dateDecodingStrategy = .iso8601` already configured, so the Swift
//  property names mirror the server's snake_case fields one-for-one.
//

import Foundation

/// A row from `public.users` plus a couple of derived columns. Source of
/// truth for "who is this user" once a session is restored.
struct UserProfile: Codable, Equatable, Identifiable {
    let id: String
    var email: String
    var name: String?
    var yearOfGraduation: Int?
    var schoolAffiliation: String?
    var schoolEmail: String?
    /// Registrar-grade course identifiers (e.g. "ECON101"). Reserved
    /// for an upcoming real course picker — historically this was
    /// abused as a free-form interests bucket, which is now stored in
    /// `interests` (see migration `20260517200000_add_users_interests`).
    var courseCodes: [String]?
    /// Topics the user picked on the onboarding "Any Field of
    /// Interests?" step (e.g. "AI", "Design", "Soccer"). Lives in its
    /// own `users.interests` column so it doesn't muddy `courseCodes`.
    var interests: [String]?
    /// Program of study (e.g. "Computer Science", "Information Experience
    /// Design"). Captured in Onboarding Step 4 → persisted by
    /// `submit-onboarding`.
    var major: String?
    /// Short self-description shown on the Profile hero card and About
    /// You editor. Persisted by `submit-onboarding` whenever the caller
    /// includes a `bio` key on the payload.
    var bio: String?
    /// Public URL of the user's profile photo in the `avatars` storage
    /// bucket. Written by `upload-avatar` and surfaced everywhere the
    /// user appears (top-right pill, community posts, comments).
    var avatarUrl: String?
    /// `nil` while onboarding has not been submitted yet. `ContentView`
    /// routes incomplete users back into `OnboardingFlow(startAt: .college)`.
    var onboardingCompletedAt: Date?
    let createdAt: Date
    var updatedAt: Date
}

extension UserProfile {
    /// True once `submit-onboarding` has succeeded for this user.
    var hasCompletedOnboarding: Bool { onboardingCompletedAt != nil }

    /// Display name with a sane fallback so UI never shows an empty string.
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return email
    }
}
