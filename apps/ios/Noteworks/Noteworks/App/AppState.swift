//
//  AppState.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI
import Combine
import Supabase

class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?

    /// The Supabase access token for the current session.
    /// Set after sign-in; cleared on sign-out.
    @Published var accessToken: String?

    let authService: AuthServiceProtocol = SupabaseAuthService()

    /// Exposes the underlying Supabase client for `.onOpenURL` (Google OAuth redirect).
    var supabaseClient: SupabaseClient {
        (authService as! SupabaseAuthService).client
    }

    init() {
        checkAuthStatus()
    }

    func checkAuthStatus() {
        isAuthenticated = false
        accessToken = nil
    }

    func handleAuthResult(_ result: AuthResult) {
        accessToken = result.accessToken
        currentUser = User(id: result.userId, email: result.email)
    }

    func signOut() {
        accessToken = nil
        currentUser = nil
        isAuthenticated = false
    }
}

// Placeholder User model - move to Shared/Models/User.swift later
struct User {
    let id: String
    let email: String
}

