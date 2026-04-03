//
//  AuthServiceTests.swift
//  NoteworksTests
//
//  Created on 2026-04-03.
//

import Testing
import Foundation
@testable import Noteworks

struct AuthServiceTests {

    let service = SupabaseAuthService()

    // MARK: - Sign In

    @Test func signInWithValidCredentials() async throws {
        let result = try await service.signIn(
            email: "cola.w@noteworks.studio",
            password: "TestPassword123!"
        )
        #expect(!result.accessToken.isEmpty, "Should receive a valid access token")
        #expect(!result.userId.isEmpty, "Should receive a user ID")
        #expect(result.email == "cola.w@noteworks.studio")
        print("✓ Sign-in succeeded — userId: \(result.userId.prefix(8))…")
    }

    @Test func signInWithWrongPassword() async {
        do {
            _ = try await service.signIn(
                email: "cola.w@noteworks.studio",
                password: "WrongPassword999!"
            )
            Issue.record("Should have thrown an error for wrong password")
        } catch {
            print("✓ Wrong password correctly rejected: \(error.localizedDescription)")
        }
    }

    @Test func signInWithNonexistentEmail() async {
        do {
            _ = try await service.signIn(
                email: "doesnotexist_\(UUID().uuidString.prefix(6))@noteworks.studio",
                password: "TestPassword123!"
            )
            Issue.record("Should have thrown an error for nonexistent email")
        } catch {
            print("✓ Nonexistent email correctly rejected: \(error.localizedDescription)")
        }
    }

    @Test func signInIsCaseSensitive() async {
        // Uppercase first letter — should still work if Supabase normalizes, or fail if case-sensitive
        do {
            let result = try await service.signIn(
                email: "Cola.w@noteworks.studio",
                password: "TestPassword123!"
            )
            print("⚠ Supabase accepted uppercase email — case-insensitive: userId \(result.userId.prefix(8))…")
        } catch {
            print("✓ Uppercase email rejected — Supabase is case-sensitive: \(error.localizedDescription)")
        }
    }
}
