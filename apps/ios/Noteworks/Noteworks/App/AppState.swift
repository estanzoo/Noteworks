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

    /// True when the user tapped "Skip, set up later" on Welcome and is
    /// browsing without an account. There's no Supabase session, no
    /// access token, and no `profile` — every server-backed feature is
    /// effectively read-only/disabled — but the local-only surfaces
    /// (Home, Library, Profile placeholder) work against the on-device
    /// `notesStore` so the user can poke around. Cleared by `signOut()`
    /// (and by any successful real sign-in).
    @Published var isGuestMode: Bool = false

    /// Set by `bootstrap()` when a returning user has a valid session but
    /// `onboarding_completed_at` is still null (e.g. OAuth first run or a
    /// previously interrupted submission). `ContentView` uses this to pick
    /// the starting step on first render — it is intentionally a one-shot
    /// decision so that sign-up flows triggered from the welcome screen
    /// continue to drive their own `.welcome -> .signUp -> .college` path
    /// without `isAuthenticated` flipping them sideways.
    @Published var resumeOnboardingAtCollege: Bool = false

    /// True when the Supabase session has Google/Apple identities only (no
    /// email-password provider). Profile hides Security Settings for these users.
    @Published private(set) var isOAuthSignIn: Bool = false

    /// True while the user is inside the note editor. `MainTabView`
    /// watches this to hide the floating Home/Library/Community tab bar
    /// — when you're writing on a page, the tab pill at the bottom of
    /// the screen just steals canvas room (and visually clashes with the
    /// page card). The editor flips this on `.onAppear` and back off on
    /// `.onDisappear` so the bar slides back in when you tap the back
    /// chevron.
    @Published var isImmersiveEditing: Bool = false

    /// One-shot inbox used to hand a community post off to
    /// `CommunityView`. Search popups on Home / CourseSpace / Profile
    /// set this when the user taps a community hit, then switch the
    /// active tab to `.people`. `CommunityView` consumes the value on
    /// the next `.onChange` and clears it back to `nil`.
    @Published var pendingCommunityPost: CommunityPost?

    /// Post-onboarding product tour (NoteWorks_UI 5).
    let tutorialCoordinator = TutorialCoordinator()

    // MARK: - Dependencies

    let notesStore: NotesStore
    let creditsStore: CreditsStore
    let authService: AuthServiceProtocol
    /// Shared bell-icon inbox. Lives at app level so every tab reads the
    /// same `items` array — previously each screen owned its own
    /// `@State` empty list that reset on every tab switch.
    let notifications: NotificationsStore

    /// Exposes the underlying Supabase client for `.onOpenURL` (Google OAuth redirect).
    var supabaseClient: SupabaseClient {
        (authService as! SupabaseAuthService).client
    }

    // MARK: - Internal

    private var sessionExpiredObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        notesStore: NotesStore,
        creditsStore: CreditsStore? = nil,
        authService: AuthServiceProtocol = SupabaseAuthService(),
        notifications: NotificationsStore? = nil
    ) {
        self.notesStore = notesStore
        self.creditsStore = creditsStore ?? CreditsStore.shared
        self.authService = authService
        // `NotificationsStore` is `@MainActor`, so we can't use a
        // `NotificationsStore()` default on the parameter (the default
        // expression is evaluated at the nonisolated call site). Instead
        // take an optional and construct one here — `AppState` itself is
        // `@MainActor`, so this call is allowed.
        self.notifications = notifications ?? NotificationsStore()

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
            creditsStore.activate(userId: restored.userId)
            notifications.activate(userId: restored.userId)

            isOAuthSignIn = await authService.isOAuthSignIn()

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
        // Drop the guest flag if a guest just signed in — the real
        // session takes over and `notesStore` is re-scoped to the
        // signed-in user below.
        isGuestMode = false
        notesStore.activate(userId: result.userId)
        creditsStore.activate(userId: result.userId)
        notifications.activate(userId: result.userId, freshSession: true)
        Task { isOAuthSignIn = await authService.isOAuthSignIn() }
    }

    /// Re-reads Supabase Auth identities (google / apple / email providers).
    func refreshSignInMethod() async {
        guard isAuthenticated else {
            isOAuthSignIn = false
            return
        }
        isOAuthSignIn = await authService.isOAuthSignIn()
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
        creditsStore.deactivate()
        notifications.deactivate()
        clearSessionState()
    }

    /// Routes the user into `MainTabView` without a real Supabase session.
    /// Used by the Welcome → "Skip, set up later" affordance so first-time
    /// visitors can poke around the local-only surfaces (Home, Library,
    /// Profile placeholder) before deciding to sign up. Activates the
    /// notes store with a `guest` sentinel id so `notesStore.isReady`
    /// flips and the Home bubble field renders instead of the
    /// "still loading" placeholder.
    func enterGuestMode() {
        isGuestMode = true
        // Make sure no stale session lingers — guests are deliberately
        // signed out as far as the app is concerned.
        accessToken = nil
        currentUser = nil
        profile = nil
        isAuthenticated = false
        resumeOnboardingAtCollege = false

        let guestId = NotesStore.guestUserId
        let isFirstGuestVisit = !notesStore.hasPersistedSnapshot(forUserId: guestId)
        notesStore.activate(userId: guestId)
        creditsStore.activate(userId: guestId)

        // First-time skip → one centred Untitled Bubble (JSX L2048). If a
        // returning guest somehow has an empty snapshot, heal it the same way.
        if isFirstGuestVisit || notesStore.bubbleNames.isEmpty {
            notesStore.applyInitialGuestHome()
        }

        notifications.activate(userId: guestId, freshSession: true)
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
        isGuestMode = false
        isOAuthSignIn = false
        tutorialCoordinator.tutorialNoteId = nil
        tutorialCoordinator.isActive = false
        tutorialCoordinator.showComplete = false
    }
}
