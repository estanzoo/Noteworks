//
//  AuthService.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import Foundation
import AuthenticationServices
import Supabase

// MARK: - Auth models

struct AuthResult: Sendable {
    let userId: String
    let email: String
    let accessToken: String
}

/// After sign-up, `accessToken` is nil until email is verified (when confirmation is enabled).
struct SignUpOutcome: Sendable {
    let userId: String
    let email: String
    let accessToken: String?
}

// MARK: - Auth errors

/// Typed errors thrown by `AuthServiceProtocol` so callers can branch on
/// specific failure modes (vs. just surfacing a generic alert).
enum AuthError: LocalizedError {
    /// The email passed to `signUp` already belongs to an existing account.
    /// Detected via Supabase's "fake user" response (no `identities`) when
    /// the project has email-enumeration protection enabled.
    case emailAlreadyRegistered

    var errorDescription: String? {
        switch self {
        case .emailAlreadyRegistered:
            return "An account with this email already exists."
        }
    }
}

// MARK: - Onboarding API

struct OnboardingPayload: Encodable, Sendable {
    let name: String
    let yearOfGraduation: Int
    let schoolAffiliation: String
    /// Optional `schools.id` UUID picked from the autocomplete. When
    /// present, `submit-onboarding` uses it directly for the
    /// `school_enrollments` upsert instead of trying to match
    /// `school_affiliation` by name.
    var schoolId: String? = nil
    let schoolEmail: String
    /// Registrar-grade course identifiers (e.g. "ECON101"). Today this is
    /// always an empty array — the onboarding "Field of Interests" step
    /// no longer leaks into this field. Will be repopulated when we ship
    /// a real course picker.
    var courseCodes: [String] = []
    /// Free-form topics the user picked on the "Any Field of Interests?"
    /// step (e.g. "AI", "Design", "Soccer"). Persisted to `users.interests`.
    var interests: [String] = []
    /// Optional program of study. When non-nil and non-empty, the server
    /// persists it onto `users.major`.
    var major: String? = nil
    /// Optional short self-description. Only sent when the caller wants
    /// to update the bio (the onboarding flow leaves it nil so the
    /// server treats the column as "leave alone"; the Profile editor
    /// sets it to the user's typed value, including an empty string to
    /// clear the field).
    var bio: String? = nil

    enum CodingKeys: String, CodingKey {
        case name
        case yearOfGraduation = "year_of_graduation"
        case schoolAffiliation = "school_affiliation"
        case schoolId = "school_id"
        case schoolEmail = "school_email"
        case courseCodes = "course_codes"
        case interests
        case major
        case bio
    }
}

private struct SubmitOnboardingResponse: Decodable, Sendable {
    let id: String
}

private struct ConfirmPasswordResetPayload: Encodable, Sendable {
    let email: String
    let code: String
    let password: String
    let confirmPassword: String

    enum CodingKeys: String, CodingKey {
        case email
        case code
        case password
        case confirmPassword = "confirm_password"
    }
}

private struct ConfirmPasswordResetResponse: Decodable, Sendable {
    let message: String
}

// MARK: - Token refresh

/// Returned by `/auth/v1/token?grant_type=refresh_token`. Only the fields
/// we actually consume are decoded; everything else (token type, expiry,
/// user record) is ignored.
struct RefreshedSession: Sendable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let email: String
}

// MARK: - Protocol

protocol AuthServiceProtocol: AnyObject {
    func signUp(name: String, email: String, password: String) async throws -> SignUpOutcome
    func signIn(email: String, password: String) async throws -> AuthResult
    func signInWithGoogle() async throws -> AuthResult
    func signInWithApple() async throws -> AuthResult
    func verifyEmail(code: String, email: String) async throws -> AuthResult
    func resendSignupConfirmation(email: String) async throws
    func submitOnboarding(_ payload: OnboardingPayload, accessToken: String) async throws
    func resetPassword(email: String) async throws
    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws
    /// Triggers Supabase's email-change flow: dispatches a 6-digit OTP /
    /// confirmation link to the new email address. The user must call
    /// `confirmEmailChange` with the OTP before the change takes effect.
    func requestEmailChange(newEmail: String) async throws
    /// Verifies the 6-digit OTP that Supabase sent to the user's new
    /// email. On success the auth row's email is rotated and the
    /// returned access token reflects the change.
    func confirmEmailChange(newEmail: String, code: String) async throws -> AuthResult
    func getUserProfile(accessToken: String) async throws -> UserProfile
    /// Exchange the current refresh token for a fresh access token. Uses the
    /// Supabase Swift SDK so the new session is also persisted to Keychain.
    func refreshSession() async throws -> RefreshedSession
    /// Returns the active session if one is restored from Keychain, else `nil`.
    /// Triggers a refresh on the way out if the cached token is expired.
    func restoreSession() async throws -> RefreshedSession?
    /// Signs the user out of Supabase (clears the Keychain-stored session).
    func signOut() async throws
    /// True when the active Supabase session was created via Google or Apple
    /// OAuth and has no email-password identity. Reads `auth.users` identities
    /// from the restored session (Dashboard → Authentication → Users).
    func isOAuthSignIn() async -> Bool
}

// MARK: - Supabase

final class SupabaseAuthService: AuthServiceProtocol {
    let client: SupabaseClient

    init() {
        client = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.baseURL)!,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: URL(string: "noteworks://auth-callback")!,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    func signUp(name: String, email: String, password: String) async throws -> SignUpOutcome {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["name": .string(name)]
        )
        let user = response.user
        // When the Supabase project has email-enumeration protection on
        // (the default), signing up with an already-registered email
        // returns a 200 with a "fake" user that has no linked identities
        // and no session — instead of a 4xx — so phishing tools can't
        // probe the auth API. Detect that shape here and surface it as
        // a typed error so the sign-up screen can show an inline
        // "account already exists" message under the Email field
        // instead of routing the user to a verify-email screen whose
        // OTP will never arrive.
        if response.session == nil, (user.identities?.isEmpty ?? true) {
            throw AuthError.emailAlreadyRegistered
        }
        let userId = user.id.uuidString
        let resolvedEmail = user.email ?? email
        if let session = response.session {
            return SignUpOutcome(userId: userId, email: resolvedEmail, accessToken: session.accessToken)
        }
        return SignUpOutcome(userId: userId, email: resolvedEmail, accessToken: nil)
    }

    func signIn(email: String, password: String) async throws -> AuthResult {
        let session = try await client.auth.signIn(email: email, password: password)
        return authResult(from: session, fallbackEmail: email)
    }

    func signInWithGoogle() async throws -> AuthResult {
        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            scopes: "email profile"
        )
        return authResult(from: session, fallbackEmail: session.user.email ?? "")
    }

    @MainActor
    func signInWithApple() async throws -> AuthResult {
        let helper = AppleSignInHelper()
        let credential = try await helper.performSignIn()
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: credential.idToken,
                nonce: credential.rawNonce
            )
        )
        return authResult(from: session, fallbackEmail: session.user.email ?? "")
    }

    func verifyEmail(code: String, email: String) async throws -> AuthResult {
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw APIError.badRequest("Enter the verification code.")
        }
        let response = try await client.auth.verifyOTP(
            email: email,
            token: token,
            type: .signup
        )
        guard let session = response.session else {
            throw APIError.badRequest("Verification failed. Check the code and try again.")
        }
        return authResult(from: session, fallbackEmail: email)
    }

    func resendSignupConfirmation(email: String) async throws {
        try await client.auth.resend(email: email, type: .signup)
    }

    func submitOnboarding(_ payload: OnboardingPayload, accessToken: String) async throws {
        let url = SupabaseConfig.submitOnboardingURL
        let _: SubmitOnboardingResponse = try await APIClient.shared.post(
            url,
            body: payload,
            accessToken: accessToken
        )
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digits = code.filter { $0.isNumber }
        guard digits.count == 6 else {
            throw APIError.badRequest("Enter the 6-digit recovery code.")
        }
        guard newPassword.count >= 8 else {
            throw APIError.badRequest("Password must be at least 8 characters.")
        }
        let _: ConfirmPasswordResetResponse = try await APIClient.shared.postPublic(
            SupabaseConfig.confirmPasswordResetURL,
            body: ConfirmPasswordResetPayload(
                email: trimmedEmail,
                code: digits,
                password: newPassword,
                confirmPassword: newPassword
            )
        )
    }

    func requestEmailChange(newEmail: String) async throws {
        let trimmed = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.badRequest("Enter your new email address.")
        }
        // `auth.update(user:)` dispatches the confirmation email when an
        // email field is supplied. By default Supabase requires
        // confirmation on both the old and new addresses, but the
        // 6-digit OTP that ships with the change-email template lets us
        // gate everything off a single verifyOTP call against the new
        // address (see `confirmEmailChange` below).
        try await client.auth.update(user: UserAttributes(email: trimmed))
    }

    func confirmEmailChange(newEmail: String, code: String) async throws -> AuthResult {
        let trimmedEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw APIError.badRequest("Enter your new email address.")
        }
        guard !token.isEmpty else {
            throw APIError.badRequest("Enter the verification code.")
        }
        let response = try await client.auth.verifyOTP(
            email: trimmedEmail,
            token: token,
            type: .emailChange
        )
        guard let session = response.session else {
            throw APIError.badRequest("That code doesn’t match. Please try the 6-digit verification code again.")
        }
        return authResult(from: session, fallbackEmail: trimmedEmail)
    }

    func getUserProfile(accessToken: String) async throws -> UserProfile {
        try await APIClient.shared.get(
            SupabaseConfig.getUserProfileURL,
            accessToken: accessToken
        )
    }

    func refreshSession() async throws -> RefreshedSession {
        // `refreshSession()` on supabase-swift forces a refresh-token exchange
        // and writes the new session back to its Keychain storage. We don't
        // need to manage the refresh token by hand.
        let session = try await client.auth.refreshSession()
        return RefreshedSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userId: session.user.id.uuidString,
            email: session.user.email ?? ""
        )
    }

    func restoreSession() async throws -> RefreshedSession? {
        // `session` getter throws if no session is persisted. supabase-swift
        // automatically refreshes a near-expired access token on access, so
        // a successful return is always usable immediately.
        do {
            let session = try await client.auth.session
            return RefreshedSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                userId: session.user.id.uuidString,
                email: session.user.email ?? ""
            )
        } catch {
            return nil
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func isOAuthSignIn() async -> Bool {
        guard let session = try? await client.auth.session else { return false }
        return Self.isOAuthSignIn(identities: session.user.identities)
    }

    /// OAuth-only accounts have a `google` or `apple` identity and no `email`
    /// identity (email/password users always carry an `email` provider row).
    static func isOAuthSignIn(identities: [UserIdentity]?) -> Bool {
        let providers = Set((identities ?? []).map(\.provider))
        let hasOAuth = providers.contains("google") || providers.contains("apple")
        return hasOAuth && !providers.contains("email")
    }

    private func authResult(from session: Session, fallbackEmail: String) -> AuthResult {
        AuthResult(
            userId: session.user.id.uuidString,
            email: session.user.email ?? fallbackEmail,
            accessToken: session.accessToken
        )
    }
}
