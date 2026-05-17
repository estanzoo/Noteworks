//
//  ProfileViewModel.swift
//  Noteworks
//
//  Holds all state for the Profile screen, mirroring the useState fields in
//  ProfilePage (others/noteworks-library(2).jsx L5649–L5926).
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Enums

enum ProfileDetail: String, CaseIterable, Identifiable {
    case about, subscription, credits, security, general, feedback
    var id: String { rawValue }

    var label: String {
        switch self {
        case .about:        return "About You"
        case .subscription: return "Subscription"
        case .credits:      return "Credits"
        case .security:     return "Security Settings"
        case .general:      return "General"
        case .feedback:     return "Feedback"
        }
    }
}

enum GeneralPanel: String, Identifiable {
    case overview, language, migration, referral, storage
    var id: String { rawValue }
}

enum EmailVerificationStep {
    case email, verify
}

enum MigrationStatus: String {
    case ready = "Ready"
    case queued = "Queued"
}

struct FeedbackPhoto: Identifiable, Equatable {
    let id: UUID
    let data: Data
}

// MARK: - View Model

@MainActor
final class ProfileViewModel: ObservableObject {

    // Source of truth for the displayed profile.
    @Published var profile: Profile = .initial

    // Navigation state.
    @Published var activeDetail: ProfileDetail = .subscription
    @Published var generalPanel: GeneralPanel = .overview

    // About You draft state.
    @Published var aboutDraft: AboutDraft
    @Published var aboutSaved: Bool = false

    // Email change popup state.
    @Published var editingEmail: Bool = false
    @Published var emailVerificationStep: EmailVerificationStep = .email
    @Published var emailDraft: String = ""
    @Published var emailVerificationCode: String = ""
    @Published var previewVerificationCode: String = "248163"
    @Published var emailVerificationError: String = ""

    // Hints (mirrors the state strings in the JSX).
    @Published var subscriptionHint: String = "Pro unlocks AI study workflows, higher monthly credit refills, and priority access to new beta features."
    @Published var securityHint: String = "Your account already has 2 linked providers for smoother sign-in recovery."
    @Published var storageHint: String = "Local storage keeps recent notes, previews, and imports feeling instant on iPad."

    // Migration sources (JSX L5684–L5689).
    @Published var migrationStatus: [(source: String, status: MigrationStatus)] = [
        ("Notion",    .ready),
        ("Goodnotes", .ready),
        ("Evernote",  .ready),
        ("Other",     .ready),
    ]

    // Feedback form state.
    @Published var feedbackType: String = "Idea"
    @Published var feedbackArea: String = "Profile"
    @Published var feedbackAreaOther: String = ""
    @Published var feedbackPriority: String = "Major"
    @Published var feedbackTitle: String = ""
    @Published var feedbackText: String = ""
    @Published var feedbackFollowUp: Bool = true
    @Published var feedbackOtherEmailOpen: Bool = false
    @Published var feedbackOtherEmail: String = ""
    @Published var feedbackPhotos: [FeedbackPhoto] = []
    @Published var feedbackSent: Bool = false

    // Feedback popup state.
    struct FeedbackPopupState: Equatable {
        var open: Bool = false
        var followUpEnabled: Bool = false
        var contactEmail: String = ""
    }
    @Published var feedbackPopup: FeedbackPopupState = .init()

    // Small UI affordances.
    @Published var copied: Bool = false

    // MARK: - Constants

    /// Mirrors JSX L5705–L5710.
    let storageUsage: [(label: String, value: Int, detail: String)] = [
        ("Note Library",  286, "Downloaded notebooks, page thumbnails, and recent edits"),
        ("Media Cache",   148, "Images, preview renders, and imported visual assets"),
        ("Offline Files",  94, "Files kept available for quick local access"),
    ]

    var totalStorageUsage: Int { storageUsage.reduce(0) { $0 + $1.value } }

    let feedbackTypes: [String]     = ["Bug", "UX", "Idea", "Performance", "Love it"]
    let feedbackAreas: [String]     = ["Home", "Library", "Community", "Note Editor", "Profile", "Other"]
    let feedbackPriorities: [String] = ["Minor", "Major", "Blocker"]

    // MARK: - Init

    init() {
        self.aboutDraft = AboutDraft(from: .initial)
    }

    // MARK: - Hydration from AppState.profile

    /// Copies server-backed fields from `UserProfile` into the local
    /// `Profile` struct so the hero card, avatar, and About You section
    /// show real data instead of the JSX `PROFILE_INITIAL` placeholder.
    /// Subscription / credits / referral fields remain placeholder until a
    /// future backend ships them.
    func hydrate(from userProfile: UserProfile) {
        if let name = userProfile.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.name = name
        }
        profile.email = userProfile.email
        // Pull the server-backed avatar URL (set by `upload-avatar`). Clear
        // the optimistic local bytes once we've got a canonical URL so
        // every surface reads from the same source.
        if let avatar = userProfile.avatarUrl,
           !avatar.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.avatarUrl = avatar
            profile.photoData = nil
        }
        if let school = userProfile.schoolAffiliation, !school.isEmpty {
            profile.school = school
        }
        if let major = userProfile.major,
           !major.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.major = major
        } else {
            // Server hasn't recorded a major yet (e.g. legacy account that
            // onboarded before the field existed) — leave whatever the user
            // had locally so the field doesn't blank out unexpectedly.
        }
        if let year = userProfile.yearOfGraduation {
            profile.grade = "Graduates \(year)"
        }
        syncAboutDraftFromProfile()
    }

    /// Submitter for the "Save Changes" button in `AboutYouSection`. Reuses
    /// `submit-onboarding` as an upsert (per `docs/Frontend_Auth_and_Onboarding_Guide.md`)
    /// then refetches the profile via `AppState.refreshProfile()`.
    func saveAbout(using appState: AppState) async {
        let trimmedName = aboutDraft.name.trimmingCharacters(in: .whitespaces)
        let resolvedName = trimmedName.isEmpty ? profile.name : trimmedName
        let school = aboutDraft.school.trimmingCharacters(in: .whitespaces)
        let trimmedMajor = aboutDraft.major.trimmingCharacters(in: .whitespaces)
        let resolvedMajor: String? = trimmedMajor.isEmpty ? nil : trimmedMajor
        let yearOfGrad = appState.profile?.yearOfGraduation ?? 2100
        let schoolEmail = appState.profile?.schoolEmail ?? profile.email
        let courseCodes = appState.profile?.courseCodes ?? []

        let payload = OnboardingPayload(
            name: resolvedName,
            yearOfGraduation: yearOfGrad,
            schoolAffiliation: school.isEmpty ? (appState.profile?.schoolAffiliation ?? "") : school,
            schoolEmail: schoolEmail,
            courseCodes: courseCodes,
            major: resolvedMajor
        )

        guard let token = appState.accessToken else { return }
        do {
            try await appState.authService.submitOnboarding(payload, accessToken: token)
            if let next = await appState.refreshProfile() {
                hydrate(from: next)
            } else {
                // Still apply the local edits so the user sees their changes.
                saveAbout()
            }
            aboutSaved = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                aboutSaved = false
            }
        } catch {
            // Profile edit failed; fall back to local-only save so the UI
            // still reflects the user's intent and they can retry later.
            saveAbout()
        }
    }

    // MARK: - Derived

    var usageTotal: Int {
        profile.credits.usage.reduce(0) { $0 + $1.used }
    }

    var inviteLink: String {
        "https://noteworks.app/invite/\(profile.referral.code)"
    }

    var academicEmailVerified: Bool {
        isAcademicEmail(profile.email)
    }

    var effectiveFeedbackArea: String {
        feedbackArea == "Other"
            ? (feedbackAreaOther.trimmingCharacters(in: .whitespaces).isEmpty ? "Other" : feedbackAreaOther.trimmingCharacters(in: .whitespaces))
            : feedbackArea
    }

    var queuedCount: Int { migrationStatus.filter { $0.status == .queued }.count }

    var linkedCount: Int { profile.security.linkedCount }

    var aboutHasChanges: Bool { aboutDraft.hasChanges(vs: profile) }

    // MARK: - Profile edits

    func updateProfile<T>(_ keyPath: WritableKeyPath<Profile, T>, _ value: T) {
        profile[keyPath: keyPath] = value
    }

    func saveAbout() {
        profile.name   = aboutDraft.name.trimmingCharacters(in: .whitespaces).isEmpty ? profile.name : aboutDraft.name
        profile.bio    = aboutDraft.bio
        profile.school = aboutDraft.school
        profile.major  = aboutDraft.major
        profile.grade  = aboutDraft.grade
        aboutSaved = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            aboutSaved = false
        }
    }

    func syncAboutDraftFromProfile() {
        aboutDraft = AboutDraft(from: profile)
    }

    // MARK: - Photo

    /// Inline status shown next to "Set Photo" / "Change Photo" so the
    /// user knows the upload is in flight or failed. Cleared on success.
    @Published var photoUploadError: String?
    @Published var isUploadingPhoto: Bool = false

    /// Stages the freshly-picked image locally (for instant UI feedback)
    /// and kicks off the `upload-avatar` request. On success we refresh
    /// the AppState profile so the new URL propagates to every surface
    /// (top-right pill, community posts, comments).
    func setPhoto(_ data: Data, using appState: AppState) {
        // Immediate optimistic update — AvatarBadge prefers `photoData`
        // over `avatarUrl`, so the new image shows up at the same instant
        // the user taps Choose Photo.
        profile.photoData = data
        photoUploadError = nil

        guard let token = appState.accessToken, !token.isEmpty else {
            // Guest mode (no Supabase session) — keep the local cache and
            // skip the upload. The bytes live for the rest of the session
            // only; there's no account to write them against.
            return
        }

        isUploadingPhoto = true
        Task { @MainActor in
            do {
                let url = try await AvatarUploadService.shared.uploadAvatar(
                    imageData: data,
                    accessToken: token
                )
                profile.avatarUrl = url
                profile.photoData = nil
                _ = await appState.refreshProfile()
            } catch {
                photoUploadError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isUploadingPhoto = false
        }
    }

    func removePhoto() {
        profile.photoData = nil
        profile.avatarUrl = nil
        // We don't currently expose a server "remove" endpoint — the next
        // upload simply overwrites the bucket object. If the user removes
        // locally and never re-uploads, the row's `avatar_url` stays
        // pointed at the last upload until they pick a new image.
    }

    // MARK: - Migration

    func queueMigration(_ source: String) {
        if let idx = migrationStatus.firstIndex(where: { $0.source == source }) {
            migrationStatus[idx] = (source, .queued)
        }
    }

    // MARK: - Referral

    func copyInviteLink() {
        UIPasteboard.general.string = inviteLink
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            copied = false
        }
    }

    // MARK: - Email popup

    func openEmailPopup() {
        editingEmail = true
        emailVerificationStep = .email
        emailVerificationCode = ""
        emailVerificationError = ""
        emailDraft = profile.email
    }

    func closeEmailPopup() {
        editingEmail = false
        emailVerificationStep = .email
        emailVerificationCode = ""
        emailVerificationError = ""
        emailDraft = profile.email
    }

    func sendEmailVerificationCode() {
        let next = emailDraft.trimmingCharacters(in: .whitespaces)
        guard !next.isEmpty else { return }
        previewVerificationCode = "248163"
        emailVerificationStep = .verify
        emailVerificationCode = ""
        emailVerificationError = ""
        securityHint = "Verification code sent to \(next). Enter the code to confirm the new email."
    }

    func saveEmail() {
        let next = emailDraft.trimmingCharacters(in: .whitespaces)
        guard !next.isEmpty else { return }
        guard emailVerificationCode.trimmingCharacters(in: .whitespaces) == previewVerificationCode else {
            emailVerificationError = "That code doesn’t match. Please try the 6-digit verification code again."
            return
        }
        profile.email = next
        editingEmail = false
        emailVerificationStep = .email
        emailVerificationCode = ""
        emailVerificationError = ""
        securityHint = isAcademicEmail(next)
            ? "Academic email verified. The blue badge now appears under the profile photo."
            : "Email updated. Use an educational email to show a verified blue badge under the profile photo."
    }

    func updateEmailDraft(_ value: String) {
        emailDraft = value
        emailVerificationError = ""
    }

    func updateVerificationCode(_ value: String) {
        let digits = value.filter { $0.isNumber }
        emailVerificationCode = String(digits.prefix(6))
        emailVerificationError = ""
    }

    // MARK: - Feedback

    var canSubmitFeedback: Bool {
        !feedbackTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && !feedbackText.trimmingCharacters(in: .whitespaces).isEmpty
            && (feedbackArea != "Other" || !feedbackAreaOther.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func submitFeedback() {
        guard canSubmitFeedback else { return }
        let contactEmail = feedbackFollowUp
            ? (feedbackOtherEmail.trimmingCharacters(in: .whitespaces).isEmpty ? profile.email : feedbackOtherEmail.trimmingCharacters(in: .whitespaces))
            : ""
        feedbackTitle = ""
        feedbackText = ""
        if feedbackArea == "Other" { feedbackAreaOther = "" }
        feedbackPhotos = []
        feedbackSent = true
        feedbackPopup = FeedbackPopupState(open: true, followUpEnabled: feedbackFollowUp, contactEmail: contactEmail)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            feedbackSent = false
        }
    }

    func appendFeedbackPhoto(_ data: Data) {
        feedbackPhotos.append(FeedbackPhoto(id: UUID(), data: data))
    }

    func removeFeedbackPhoto(_ id: UUID) {
        feedbackPhotos.removeAll { $0.id == id }
    }
}

// MARK: - About Draft

struct AboutDraft: Equatable {
    var name: String
    var bio: String
    var school: String
    var major: String
    var grade: String

    init(from profile: Profile) {
        self.name   = profile.name
        self.bio    = profile.bio
        self.school = profile.school
        self.major  = profile.major
        self.grade  = profile.grade
    }

    func hasChanges(vs profile: Profile) -> Bool {
        name   != profile.name
            || bio    != profile.bio
            || school != profile.school
            || major  != profile.major
            || grade  != profile.grade
    }
}
