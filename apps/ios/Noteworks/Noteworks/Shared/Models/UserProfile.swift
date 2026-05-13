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
    var courseCodes: [String]?
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
