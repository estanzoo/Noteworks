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

/// Two-step state machine for the "Change Password" popup. Mirrors the
/// onboarding forgot-password flow: first we email a code, then the user
/// types the code + new password.
enum PasswordChangeStep {
    case request, reset
}

enum ProfileTextEditorField: String {
    case name, bio, major

    var label: String {
        switch self {
        case .name: return "Name"
        case .bio: return "Bio"
        case .major: return "Major"
        }
    }
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
    @Published var profileTextEditor: ProfileTextEditorField?
    @Published var profileTextEditorValue: String = ""
    @Published var schoolEditorOpen: Bool = false
    @Published var schoolQuery: String = ""
    @Published var gradeEditorOpen: Bool = false
    @Published var courseEditorOpen: Bool = false

    // Email change popup state.
    @Published var editingEmail: Bool = false
    @Published var emailVerificationStep: EmailVerificationStep = .email
    @Published var emailDraft: String = ""
    @Published var emailVerificationCode: String = ""
    @Published var emailVerificationError: String = ""
    /// True while we wait on Supabase to send the OTP or verify it.
    /// Drives the Continue / Verify buttons into a loading state and
    /// blocks duplicate submissions.
    @Published var emailVerificationBusy: Bool = false

    // Change-password popup state. Identical UX to the onboarding
    // forgot-password flow: we send a 6-digit recovery code to the
    // account email and let the user pick a new password.
    @Published var editingPassword: Bool = false
    @Published var passwordChangeStep: PasswordChangeStep = .request
    @Published var passwordResetCode: String = ""
    @Published var passwordNewValue: String = ""
    @Published var passwordConfirmValue: String = ""
    @Published var passwordChangeError: String = ""
    @Published var passwordChangeBusy: Bool = false
    @Published var passwordChangeSuccess: Bool = false

    // Hints (mirrors the state strings in the JSX).
    @Published var subscriptionHint: String = "Pro unlocks AI study workflows, higher monthly credit refills, and priority access to new beta features."
    @Published var securityHint: String = "Use an educational email so the blue verified badge appears under your profile photo."
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

    // MARK: - Storage (live, measured from `DeviceStorageService`)

    /// Latest snapshot of the on-device bucket sizes. Starts at zero so
    /// the panel renders immediately on first launch; `refreshStorageReport()`
    /// fills it in on appear.
    @Published var storageReport: StorageReport = .empty
    @Published var isMeasuringStorage: Bool = false

    var storageBuckets: [StorageReport.Bucket] { storageReport.buckets }
    var totalStorageBytes: Int64 { storageReport.totalBytes }
    var totalStorageFormatted: String { storageReport.totalBytes.formattedAsStorageSize() }

    let feedbackTypes: [String]     = ["Bug", "UX", "Idea", "Performance", "Love it"]
    let feedbackAreas: [String]     = ["Home", "Library", "Community", "Note Editor", "Profile", "Other"]
    let feedbackPriorities: [String] = ["Minor", "Major", "Blocker"]

    // MARK: - Init

    init() {
        self.aboutDraft = AboutDraft(from: .initial)
        // Replace the placeholder `Profile.initial.version` with the
        // real `CFBundleShortVersionString` (Build `CFBundleVersion`)
        // so the General → Version Number row reflects the actual
        // bundle we shipped, not a literal that drifts over time.
        self.profile.version = Self.bundleVersionString()
    }

    /// Builds `"NoteWorks <marketing> (Build <build>)"` from Info.plist
    /// keys. Falls back to a friendly placeholder when running in a
    /// preview / test target that doesn't ship those keys.
    static func bundleVersionString() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketing = (info["CFBundleShortVersionString"] as? String) ?? "0.0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        return "NoteWorks \(marketing) (Build \(build))"
    }

    // MARK: - Storage actions

    /// Walks the sandbox off-thread and publishes the result. Called
    /// when the user opens the Storage panel and after any cache-clear
    /// button so the new totals show up immediately.
    func refreshStorageReport() {
        guard !isMeasuringStorage else { return }
        isMeasuringStorage = true
        Task { @MainActor in
            let report = await DeviceStorageService.measure()
            storageReport = report
            isMeasuringStorage = false
        }
    }

    func clearMediaCache() {
        guard !isMeasuringStorage else { return }
        isMeasuringStorage = true
        Task { @MainActor in
            let report = await DeviceStorageService.clearMediaCache()
            storageReport = report
            storageHint = "Preview cache cleared. Core note files stay available offline."
            isMeasuringStorage = false
        }
    }

    func clearOfflineFiles() {
        guard !isMeasuringStorage else { return }
        isMeasuringStorage = true
        Task { @MainActor in
            let report = await DeviceStorageService.clearOfflineFiles()
            storageReport = report
            storageHint = "Imported overlay images removed. PencilKit ink stays on-device."
            isMeasuringStorage = false
        }
    }

    // MARK: - Hydration from AppState.profile

    /// Copies server-backed fields from `UserProfile` into the local
    /// `Profile` struct so the hero card, avatar, and About You section
    /// show real data instead of the JSX `PROFILE_INITIAL` placeholder.
    /// Subscription / credits / referral fields remain placeholder until a
    /// future backend ships them — credits/tier sync from `CreditsStore`
    /// via `applyCredits(from:)`.
    /// `bioFallbackIfMissing` is used only after an About-You save when the
    /// GET profile response still omits `bio` (older edge deploys or
    /// PostgREST omitting null keys) — without it `syncAboutDraftFromProfile`
    /// would copy a stale empty `profile.bio` back onto the draft and the
    /// hero card would never show what the user just submitted.
    func hydrate(from userProfile: UserProfile, bioFallbackIfMissing: String? = nil) {
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
        // Mirror `school` / `major`: missing or null `bio` in JSON becomes
        // `nil` here — treat that like an empty string unless we just saved
        // and pass a fallback string from that submit.
        profile.bio = userProfile.bio ?? bioFallbackIfMissing ?? ""
        // Always mirror school/major from the server so a save clears the
        // field locally too (we used to gate on non-empty, which made
        // empty-out edits feel like they didn't take).
        profile.school = userProfile.schoolAffiliation ?? ""
        profile.major = userProfile.major ?? ""
        if let year = userProfile.yearOfGraduation {
            profile.grade = Self.gradeLabel(for: year, existing: profile.grade)
        }
        syncAboutDraftFromProfile()
    }

    /// Mirrors the live credit balance / tier from `CreditsStore` into the
    /// profile UI (hero chip, Credits panel, Subscription row).
    func applyCredits(from store: CreditsStore) {
        profile.subscription = store.profileSubscription()
        profile.credits = store.profileCredits()
    }

    /// Converts the server-stored `year_of_graduation` into a profile
    /// grade label. Prefers the richer `PROFILE_GRADE_GROUPS` labels
    /// when we can infer them from the graduation year.
    static func gradeLabel(for graduationYear: Int, existing: String = "") -> String {
        if graduationYear >= 2100 { return "Other" }
        let now = Calendar.current.component(.year, from: Date())
        let yearsAway = graduationYear - now
        switch yearsAway {
        case 4: return "Freshman (Year 1)"
        case 3: return "Sophomore (Year 2)"
        case 2: return "Junior (Year 3)"
        case 1: return "Senior (Year 4)"
        case 0: return "Senior (Year 4)"
        default:
            if yearsAway < 0 { return "Other" }
            if !existing.isEmpty { return existing }
            return "Freshman (Year 1)"
        }
    }

    /// Best-effort mapping from the About You grade picker back to the
    /// integer `year_of_graduation` column the server understands.
    static func yearOfGraduation(for grade: String, fallback: Int) -> Int {
        if grade == "Other" { return 2100 }
        let y = Calendar.current.component(.year, from: Date())
        switch grade {
        case "Freshman (Year 1)": return y + 4
        case "Sophomore (Year 2)": return y + 3
        case "Junior (Year 3)": return y + 2
        case "Senior (Year 4)": return y + 1
        case "Super Senior (Year 5+)": return y
        default: return fallback
        }
    }

    func gradeLabel(for graduationYear: Int) -> String {
        Self.gradeLabel(for: graduationYear, existing: profile.grade)
    }

    /// Submitter for the "Save Changes" button in `AboutYouSection`. Reuses
    /// `submit-onboarding` as an upsert (per `docs/Frontend_Auth_and_Onboarding_Guide.md`)
    /// then refetches the profile via `AppState.refreshProfile()`.
    func saveAbout(using appState: AppState) async {
        guard !aboutSchoolNeedsSelection else { return }
        let trimmedName = aboutDraft.name.trimmingCharacters(in: .whitespaces)
        let resolvedName = trimmedName.isEmpty ? profile.name : trimmedName
        let school = aboutDraft.school.trimmingCharacters(in: .whitespaces)
        let trimmedMajor = aboutDraft.major.trimmingCharacters(in: .whitespaces)
        let resolvedMajor: String? = trimmedMajor.isEmpty ? nil : trimmedMajor
        let trimmedBio = aboutDraft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearOfGrad = Self.yearOfGraduation(
            for: aboutDraft.grade,
            fallback: appState.profile?.yearOfGraduation ?? 2100
        )
        let schoolEmail = appState.profile?.schoolEmail ?? profile.email
        // Preserve whatever the server has for these arrays — the About-You
        // section doesn't edit them. Sending the existing values makes the
        // upsert a no-op for those columns. Importantly, `interests` is its
        // own field now; do NOT forward `courseCodes` in its place.
        let courseCodes = appState.profile?.courseCodes ?? []
        let interests = appState.profile?.interests ?? []

        let payload = OnboardingPayload(
            name: resolvedName,
            yearOfGraduation: yearOfGrad,
            schoolAffiliation: school.isEmpty ? (appState.profile?.schoolAffiliation ?? "") : school,
            schoolId: aboutDraft.selectedSchoolId,
            schoolEmail: schoolEmail,
            courseCodes: courseCodes,
            interests: interests,
            major: resolvedMajor,
            // Always send the trimmed bio (including empty string) so the
            // user can clear it. `OnboardingPayload.bio` is `String?` only
            // so the onboarding flow can omit it — the About-You editor
            // is always authoritative.
            bio: trimmedBio
        )

        guard let token = appState.accessToken else { return }
        do {
            try await appState.authService.submitOnboarding(payload, accessToken: token)
            // Optimistic: hero + About You read `profile` before refresh returns.
            profile.bio = trimmedBio
            profile.grade = aboutDraft.grade
            if let next = await appState.refreshProfile() {
                hydrate(from: next, bioFallbackIfMissing: trimmedBio)
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

    var aboutSchoolNeedsSelection: Bool {
        aboutDraft.hasUnrecognisedSchool(vs: profile)
    }

    var canSaveAbout: Bool {
        aboutHasChanges && !aboutSchoolNeedsSelection
    }

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

    // MARK: - About You editors

    func openProfileTextEditor(_ field: ProfileTextEditorField) {
        profileTextEditor = field
        switch field {
        case .name: profileTextEditorValue = aboutDraft.name
        case .bio: profileTextEditorValue = aboutDraft.bio
        case .major: profileTextEditorValue = aboutDraft.major
        }
    }

    func closeProfileTextEditor() {
        profileTextEditor = nil
        profileTextEditorValue = ""
    }

    func saveProfileTextEditor() {
        guard let field = profileTextEditor else { return }
        aboutSaved = false
        switch field {
        case .name:
            let trimmed = profileTextEditorValue.trimmingCharacters(in: .whitespaces)
            aboutDraft.name = trimmed.isEmpty ? aboutDraft.name : profileTextEditorValue
        case .bio:
            aboutDraft.bio = profileTextEditorValue
        case .major:
            aboutDraft.major = profileTextEditorValue
        }
        closeProfileTextEditor()
    }

    func openSchoolEditor() {
        schoolQuery = aboutDraft.school
        gradeEditorOpen = false
        schoolEditorOpen = true
    }

    func closeSchoolEditor() {
        schoolEditorOpen = false
    }

    func selectSchool(_ school: SchoolResult) {
        aboutSaved = false
        aboutDraft.school = school.name
        aboutDraft.selectedSchoolId = school.id
        schoolQuery = school.name
        schoolEditorOpen = false
    }

    func openGradeEditor() {
        schoolEditorOpen = false
        gradeEditorOpen = true
    }

    func closeGradeEditor() {
        gradeEditorOpen = false
    }

    func selectGrade(_ grade: String) {
        aboutSaved = false
        aboutDraft.grade = grade
        gradeEditorOpen = false
    }

    func openCourseEditor() {
        courseEditorOpen = true
    }

    func closeCourseEditor() {
        courseEditorOpen = false
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
        emailVerificationBusy = false
        emailDraft = profile.email
    }

    func closeEmailPopup() {
        editingEmail = false
        emailVerificationStep = .email
        emailVerificationCode = ""
        emailVerificationError = ""
        emailVerificationBusy = false
        emailDraft = profile.email
    }

    /// Step 1 of the change-email flow: ask Supabase to dispatch a
    /// 6-digit OTP to the new address. Mirrors the onboarding sign-up
    /// verification — no preview code, no local state. The popup
    /// advances to the `.verify` step once the request succeeds.
    func sendEmailVerificationCode(using appState: AppState) {
        let next = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return }
        guard !emailVerificationBusy else { return }
        emailVerificationBusy = true
        emailVerificationError = ""
        Task { @MainActor in
            do {
                try await appState.authService.requestEmailChange(newEmail: next)
                emailVerificationStep = .verify
                emailVerificationCode = ""
                securityHint = "Verification code sent to \(next). Enter the code to confirm the new email."
            } catch {
                emailVerificationError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            emailVerificationBusy = false
        }
    }

    /// Step 2: verify the OTP. On success the local `profile.email` is
    /// updated, the access token (which Supabase rotated for the new
    /// email) is pushed back into `AppState`, and the server-backed
    /// profile is refreshed so every surface reads the new value.
    func saveEmail(using appState: AppState) {
        let next = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = emailVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty, code.count == 6 else { return }
        guard !emailVerificationBusy else { return }
        emailVerificationBusy = true
        emailVerificationError = ""
        Task { @MainActor in
            do {
                let result = try await appState.authService.confirmEmailChange(
                    newEmail: next,
                    code: code
                )
                appState.handleAuthResult(result)
                _ = await appState.refreshProfile()
                profile.email = next
                editingEmail = false
                emailVerificationStep = .email
                emailVerificationCode = ""
                emailVerificationError = ""
                securityHint = isAcademicEmail(next)
                    ? "Academic email verified. The blue badge now appears under the profile photo."
                    : "Email updated. Use an educational email to show a verified blue badge under the profile photo."
            } catch {
                emailVerificationError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            emailVerificationBusy = false
        }
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

    // MARK: - Password popup (reuses the forgot-password OTP flow)

    func openPasswordPopup() {
        editingPassword = true
        passwordChangeStep = .request
        passwordResetCode = ""
        passwordNewValue = ""
        passwordConfirmValue = ""
        passwordChangeError = ""
        passwordChangeBusy = false
        passwordChangeSuccess = false
    }

    func closePasswordPopup() {
        editingPassword = false
        passwordChangeStep = .request
        passwordResetCode = ""
        passwordNewValue = ""
        passwordConfirmValue = ""
        passwordChangeError = ""
        passwordChangeBusy = false
    }

    func updatePasswordResetCode(_ value: String) {
        let digits = value.filter { $0.isNumber }
        passwordResetCode = String(digits.prefix(6))
        passwordChangeError = ""
    }

    var canSendPasswordResetCode: Bool {
        !passwordChangeBusy && !profile.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmitPasswordReset: Bool {
        !passwordChangeBusy
            && passwordResetCode.count == 6
            && passwordNewValue.count >= 8
            && passwordNewValue == passwordConfirmValue
    }

    /// Step 1: dispatch a recovery code to the account's current email.
    /// Same `resetPasswordForEmail` call the onboarding "Forgot password"
    /// link uses — the user receives the standard recovery template.
    func sendPasswordResetCode(using appState: AppState) {
        let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            passwordChangeError = "No email on file for this account."
            return
        }
        guard !passwordChangeBusy else { return }
        passwordChangeBusy = true
        passwordChangeError = ""
        Task { @MainActor in
            do {
                try await appState.authService.resetPassword(email: email)
                passwordChangeStep = .reset
                passwordResetCode = ""
                passwordNewValue = ""
                passwordConfirmValue = ""
                securityHint = "Recovery code sent to \(email). Check your inbox and enter the 6-digit code below."
            } catch {
                passwordChangeError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            passwordChangeBusy = false
        }
    }

    /// Step 2: verify the recovery OTP and set the new password. Reuses
    /// `confirmPasswordReset(email:code:newPassword:)`, which runs
    /// `verifyOTP(type: .recovery)` followed by
    /// `auth.update(user: UserAttributes(password:))` under the hood.
    func confirmPasswordChange(using appState: AppState) {
        let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = passwordResetCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPassword = passwordNewValue
        guard !email.isEmpty, code.count == 6,
              newPassword.count >= 8,
              newPassword == passwordConfirmValue else { return }
        guard !passwordChangeBusy else { return }
        passwordChangeBusy = true
        passwordChangeError = ""
        Task { @MainActor in
            do {
                try await appState.authService.confirmPasswordReset(
                    email: email,
                    code: code,
                    newPassword: newPassword
                )
                passwordChangeSuccess = true
                securityHint = "Password updated. Use your new password the next time you sign in."
                editingPassword = false
                passwordChangeStep = .request
                passwordResetCode = ""
                passwordNewValue = ""
                passwordConfirmValue = ""
                // Auto-clear the success flash after a couple of seconds.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    passwordChangeSuccess = false
                }
            } catch {
                passwordChangeError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            passwordChangeBusy = false
        }
    }

    func resendPasswordResetCode(using appState: AppState) {
        let email = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !passwordChangeBusy else { return }
        passwordChangeBusy = true
        passwordChangeError = ""
        Task { @MainActor in
            do {
                try await appState.authService.resetPassword(email: email)
                securityHint = "New recovery code sent to \(email)."
            } catch {
                passwordChangeError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            passwordChangeBusy = false
        }
    }

    // MARK: - Feedback

    var canSubmitFeedback: Bool {
        !feedbackTitle.trimmingCharacters(in: .whitespaces).isEmpty
            && !feedbackText.trimmingCharacters(in: .whitespaces).isEmpty
            && (feedbackArea != "Other" || !feedbackAreaOther.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Whether a `submit-feedback` POST is currently in flight. Drives
    /// the Submit button's loading state and blocks duplicate taps.
    @Published var feedbackSubmitting: Bool = false
    /// Surfaced under the submit bar when the edge function rejects the
    /// payload (validation or auth) or the network call fails.
    @Published var feedbackSubmitError: String = ""

    func submitFeedback(using appState: AppState) {
        guard canSubmitFeedback, !feedbackSubmitting else { return }
        let contactEmail = feedbackFollowUp
            ? (feedbackOtherEmail.trimmingCharacters(in: .whitespaces).isEmpty ? profile.email : feedbackOtherEmail.trimmingCharacters(in: .whitespaces))
            : ""

        // Snapshot the values into a payload *before* clearing the
        // fields so we can resend on retry (and so the request isn't
        // mutated mid-flight by the user typing again).
        let trimmedAreaOther = feedbackAreaOther.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = SubmitFeedbackRequest(
            feedback_type: feedbackType,
            area: feedbackArea,
            area_other: feedbackArea == "Other" ? trimmedAreaOther : nil,
            priority: feedbackPriority,
            title: feedbackTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            body: feedbackText.trimmingCharacters(in: .whitespacesAndNewlines),
            follow_up_enabled: feedbackFollowUp,
            contact_email: feedbackFollowUp ? contactEmail : nil,
            // Photo upload is intentionally deferred (no media bucket
            // wired yet). The column accepts an empty array.
            media_paths: [],
            app_version: profile.version,
            device_info: FeedbackService.currentDeviceInfo()
        )

        guard let token = appState.accessToken else {
            feedbackSubmitError = "Session expired. Please sign in again to submit feedback."
            return
        }

        feedbackSubmitting = true
        feedbackSubmitError = ""
        Task { @MainActor in
            do {
                _ = try await FeedbackService.shared.submitFeedback(payload, accessToken: token)
                feedbackTitle = ""
                feedbackText = ""
                if feedbackArea == "Other" { feedbackAreaOther = "" }
                feedbackPhotos = []
                feedbackSent = true
                feedbackPopup = FeedbackPopupState(
                    open: true,
                    followUpEnabled: feedbackFollowUp,
                    contactEmail: contactEmail
                )
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    feedbackSent = false
                }
            } catch {
                feedbackSubmitError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            feedbackSubmitting = false
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
    var selectedSchoolId: String?
    var major: String
    var grade: String

    init(from profile: Profile) {
        self.name   = profile.name
        self.bio    = profile.bio
        self.school = profile.school
        self.selectedSchoolId = nil
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

    /// True when the user typed a school name but hasn't picked a row from
    /// the autocomplete list (same rule as onboarding). Existing saved
    /// schools are allowed until the user edits the field.
    func hasUnrecognisedSchool(vs profile: Profile) -> Bool {
        let trimmed = school.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let saved = profile.school.trimmingCharacters(in: .whitespaces)
        if trimmed == saved && selectedSchoolId == nil { return false }
        return selectedSchoolId == nil
    }
}
