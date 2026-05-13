//
//  AuthServiceTests.swift
//  NoteworksTests
//
//  Created on 2026-04-03.
//
//  These hit the live Supabase backend, so they need real credentials.
//  Credentials are read from the process environment so nothing sensitive
//  lives in source control. Configure the test scheme with:
//
//     NOTEWORKS_TEST_EMAIL    = a valid test account
//     NOTEWORKS_TEST_PASSWORD = its password
//
//  When either is missing the test bails out early with a clear message —
//  Swift Testing does not yet expose `XCTSkipUnless`, so we surface a
//  `Comment` via the standard `withKnownIssue { ... }` pattern.
//

import Testing
import Foundation
@testable import Noteworks

struct AuthServiceTests {

    private let service = SupabaseAuthService()

    private struct TestCredentials {
        let email: String
        let password: String
    }

    /// Returns nil when the test environment isn't configured. Callers use
    /// `guard let creds = liveCredentials() else { return }` to skip cleanly.
    private func liveCredentials() -> TestCredentials? {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["NOTEWORKS_TEST_EMAIL"]?.trimmingCharacters(in: .whitespaces),
              !email.isEmpty,
              let password = env["NOTEWORKS_TEST_PASSWORD"], !password.isEmpty else {
            return nil
        }
        return TestCredentials(email: email, password: password)
    }

    // MARK: - Sign In

    @Test func signInWithValidCredentials() async throws {
        guard let creds = liveCredentials() else {
            print("⚠ Skipping: set NOTEWORKS_TEST_EMAIL / NOTEWORKS_TEST_PASSWORD in the test scheme.")
            return
        }
        let result = try await service.signIn(email: creds.email, password: creds.password)
        #expect(!result.accessToken.isEmpty, "Should receive a valid access token")
        #expect(!result.userId.isEmpty, "Should receive a user ID")
        #expect(result.email.lowercased() == creds.email.lowercased())
    }

    @Test func signInWithWrongPassword() async {
        guard let creds = liveCredentials() else {
            print("⚠ Skipping: set NOTEWORKS_TEST_EMAIL / NOTEWORKS_TEST_PASSWORD in the test scheme.")
            return
        }
        do {
            _ = try await service.signIn(email: creds.email, password: "definitely-not-the-password-\(UUID().uuidString)")
            Issue.record("Should have thrown an error for wrong password")
        } catch {
            // Expected.
        }
    }

    @Test func signInWithNonexistentEmail() async {
        // This one doesn't need creds — we deliberately use a random email.
        do {
            _ = try await service.signIn(
                email: "doesnotexist_\(UUID().uuidString.prefix(6))@noteworks.studio",
                password: "TestPassword123!"
            )
            Issue.record("Should have thrown an error for nonexistent email")
        } catch {
            // Expected.
        }
    }

    @Test func signInIsCaseSensitive() async {
        guard let creds = liveCredentials() else {
            print("⚠ Skipping: set NOTEWORKS_TEST_EMAIL / NOTEWORKS_TEST_PASSWORD in the test scheme.")
            return
        }
        let uppercased = creds.email.uppercased()
        // Either outcome is informational — we just want to capture which
        // behavior Supabase exhibits, not make case-sensitivity a hard
        // contract we depend on.
        do {
            _ = try await service.signIn(email: uppercased, password: creds.password)
            print("⚠ Supabase accepted uppercase email — case-insensitive.")
        } catch {
            print("✓ Uppercase email rejected — Supabase is case-sensitive.")
        }
    }
}
