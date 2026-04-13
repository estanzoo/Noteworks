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

// MARK: - Onboarding API

struct OnboardingPayload: Encodable, Sendable {
    let name: String
    let yearOfGraduation: Int
    let schoolAffiliation: String
    let schoolEmail: String
    let courseCodes: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case yearOfGraduation = "year_of_graduation"
        case schoolAffiliation = "school_affiliation"
        case schoolEmail = "school_email"
        case courseCodes = "course_codes"
    }
}

private struct SubmitOnboardingResponse: Decodable, Sendable {
    let id: String
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
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw APIError.badRequest("Enter the verification code.")
        }
        let response = try await client.auth.verifyOTP(
            email: email,
            token: token,
            type: .recovery
        )
        guard response.session != nil else {
            throw APIError.badRequest("Invalid or expired code. Please try again.")
        }
        try await client.auth.update(user: UserAttributes(password: newPassword))
    }

    private func authResult(from session: Session, fallbackEmail: String) -> AuthResult {
        AuthResult(
            userId: session.user.id.uuidString,
            email: session.user.email ?? fallbackEmail,
            accessToken: session.accessToken
        )
    }
}
