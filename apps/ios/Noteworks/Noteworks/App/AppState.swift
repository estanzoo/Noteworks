//
//  AppState.swift
//  Noteworks
//
//  Owns "who is signed in" and how the rest of the app reacts to that:
//
//  - `isBootstrapping` is true while cold-launch session restore runs, so
//    `ContentView` can show a splash instead of flashing Welcome.
//  - `currentUser` is the minimal identity captured at sign-in time.
//  - `profile` is the full record from `GET /functions/v1/get-user-profile`
//    and determines whether the user finished onboarding.
//  - `notesStore` is owned here so sign-in / sign-out can scope the local
//    library per-user (Plan 2 fleshes out the per-user folder layout; Plan 3
//    just wires the lifecycle hooks).
//

import SwiftUI
import Supabase

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var isBootstrapping: Bool = true
    @Published var isAuthenticated = false
    @Published var currentUser: AuthenticatedUser?
    @Published var accessToken: String?
    @Published var profile: UserProfile?

    /// Set by `bootstrap()` when a returning user has a valid session but
    /// `onboarding_completed_at` is still null (e.g. OAuth first run or a
    /// previously interrupted submission). `ContentView` uses this to pick
    /// the starting step on first render — it is intentionally a one-shot
    /// decision so that sign-up flows triggered from the welcome screen
    /// continue to drive their own `.welcome -> .signUp -> .college` path
    /// without `isAuthenticated` flipping them sideways.
    @Published var resumeOnboardingAtCollege: Bool = false

    // MARK: - Dependencies

    let notesStore: NotesStore
    let authService: AuthServiceProtocol

    /// Exposes the underlying Supabase client for `.onOpenURL` (Google OAuth redirect).
    var supabaseClient: SupabaseClient {
        (authService as! SupabaseAuthService).client
    }

    // MARK: - Internal

    private var sessionExpiredObserver: NSObjectProtocol?

    // MARK: - Init

    init(notesStore: NotesStore, authService: AuthServiceProtocol = SupabaseAuthService()) {
        self.notesStore = notesStore
        self.authService = authService

        // Drop straight back to Welcome if `APIClient` exhausts its retry
        // (the user is genuinely signed out as far as Supabase is concerned).
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .authSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.signOut() }
        }
    }

    deinit {
        if let token = sessionExpiredObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Cold-launch bootstrap

    /// Called once from `NoteworksApp` on launch. Restores any persisted
    /// Supabase session, fetches the matching profile, and activates the
    /// per-user local store. `ContentView` waits on `isBootstrapping`
    /// before routing so we never flash Welcome under a logged-in user.
    func bootstrap() async {
        defer { isBootstrapping = false }

        // Install the 401-retry hook before any authenticated request so the
        // very first `getUserProfile` below benefits from it.
        await APIClient.shared.configure { [weak self] in
            await self?.refreshAccessToken()
        }

        do {
            guard let restored = try await authService.restoreSession() else {
                clearSessionState()
                return
            }

            accessToken = restored.accessToken
            currentUser = AuthenticatedUser(id: restored.userId, email: restored.email)
            isAuthenticated = true
            notesStore.activate(userId: restored.userId)

            do {
                let fetched = try await authService.getUserProfile(accessToken: restored.accessToken)
                profile = fetched
                // Capture the "resume incomplete onboarding" decision once,
                // here at cold-launch time — see `resumeOnboardingAtCollege`
                // for the full rationale.
                resumeOnboardingAtCollege = !fetched.hasCompletedOnboarding
            } catch APIError.unauthorized {
                // `APIClient` already retried once with a refreshed token
                // and still failed. Treat as a hard sign-out.
                await signOut()
            } catch {
                // Network blip or transient server error — keep the user
                // signed in; the Profile screen can surface a retry.
                profile = nil
            }
        } catch {
            clearSessionState()
        }
    }

    // MARK: - Auth events

    /// Called after sign-up / sign-in / OAuth succeeds. Captures the minimal
    /// identity and activates the per-user store. We deliberately do NOT
    /// refresh the profile here — the onboarding "Continue"/"Explore"
    /// buttons drive that, so the user always gets to read the celebration
    /// screen before `ContentView` routes them into `MainTabView`.
    func handleAuthResult(_ result: AuthResult) {
        accessToken = result.accessToken
        currentUser = AuthenticatedUser(id: result.userId, email: result.email)
        isAuthenticated = true
        notesStore.activate(userId: result.userId)
    }

    /// Re-fetches `profile`. Called after onboarding submit and whenever
    /// the user updates their account details.
    @discardableResult
    func refreshProfile() async -> UserProfile? {
        guard let token = accessToken else { return nil }
        do {
            let next = try await authService.getUserProfile(accessToken: token)
            self.profile = next
            return next
        } catch {
            return nil
        }
    }

    func signOut() async {
        try? await authService.signOut()
        notesStore.deactivate()
        clearSessionState()
    }

    /// Exposed to `APIClient`'s 401 retry hook. Returns the new access
    /// token on success, or `nil` if the refresh itself failed (caller
    /// should give up).
    func refreshAccessToken() async -> String? {
        do {
            let refreshed = try await authService.refreshSession()
            self.accessToken = refreshed.accessToken
            // Email may have changed (e.g. email confirmation flow); keep
            // it in sync so `currentUser` matches what's in Supabase.
            if let user = currentUser {
                self.currentUser = AuthenticatedUser(id: user.id, email: refreshed.email.isEmpty ? user.email : refreshed.email)
            }
            return refreshed.accessToken
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func clearSessionState() {
        accessToken = nil
        currentUser = nil
        profile = nil
        isAuthenticated = false
        resumeOnboardingAtCollege = false
    }
}
