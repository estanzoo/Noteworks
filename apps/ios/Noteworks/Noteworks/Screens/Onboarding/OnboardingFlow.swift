//
//  OnboardingFlow.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case signIn = 1
    case signInDone = 2
    case signUp = 3
    case verifyEmail = 4
    case college = 5
    case major = 6
    case interests = 7
    /// Post-submit initialization step. Mirrors the JSX
    /// `CourseSetupInterface` first-sign-in modal — confirms the
    /// course list and seeds Home's bubbles before the user sees it.
    case setupCourses = 8
    case done = 9
    case skipped = 10
    case forgotPassword = 11
    case resetPassword = 12
}

struct OnboardingFlow: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var data = OnboardingData()
    /// Owned at the flow level (instead of inside `CollegeStepView`) so the
    /// full schools list can start downloading the moment the user enters
    /// onboarding — by the time they reach the college step the cache is
    /// usually warm and the dropdown filters locally with no network round
    /// trip per keystroke.
    @StateObject private var schoolSearch = SchoolSearchService()
    @State private var step: OnboardingStep
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var signInEmail = ""
    @State private var signInPassword = ""
    @State private var resetEmail = ""
    @State private var resetCode = ["", "", "", "", "", ""]
    @State private var resetNewPassword = ""
    @State private var resetConfirmPassword = ""

    /// `startAt: .college` is the resume entry-point used by `ContentView`
    /// when a returning user has a valid session but `onboarding_completed_at`
    /// is still null (e.g. OAuth first run or a force-quit mid-flow).
    init(startAt: OnboardingStep = .welcome) {
        _step = State(initialValue: startAt)
    }

    var body: some View {
        ZStack {
            OnboardingBackground()
                .ignoresSafeArea()

            // Beta badge (visible on form steps, not sign-in or welcome)
            if step.rawValue >= OnboardingStep.signUp.rawValue && step.rawValue <= OnboardingStep.setupCourses.rawValue {
                VStack {
                    HStack {
                        BetaBadge()
                            .padding(.leading, 24)
                            .padding(.top, 20)
                        Spacer()
                    }
                    Spacer()
                }
                .zIndex(10)
            }

            // Step content
            Group {
                switch step {
                case .welcome:
                    WelcomeView(
                        onSignUp: { step = .signUp },
                        onSignIn: { step = .signIn },
                        onSkip: { step = .skipped },
                        onGoogleSignIn: { handleGoogleSignIn() },
                        onAppleSignIn: { handleAppleSignIn() }
                    )
                case .signIn:
                    SignInStepView(
                        email: $signInEmail,
                        password: $signInPassword,
                        onSignIn: { handleSignIn() },
                        onBack: { step = .welcome },
                        onForgotPassword: {
                            resetEmail = signInEmail
                            step = .forgotPassword
                        }
                    )
                case .signInDone:
                    SignInDoneView(
                        email: signInEmail,
                        onContinue: {
                            // `handleSignIn` only routes here once the
                            // profile reports `hasCompletedOnboarding`, so
                            // `ContentView` already has everything it needs
                            // to flip over to `MainTabView`. Re-fetch
                            // defensively in case the profile was cleared
                            // by a transient error while this view was
                            // visible.
                            Task {
                                let next = await appState.refreshProfile()
                                if let next, !next.hasCompletedOnboarding {
                                    step = .college
                                }
                            }
                        }
                    )
                case .signUp:
                    SignUpStepView(data: data, onNext: { handleSignUp() }, onBack: { step = .welcome })
                case .verifyEmail:
                    VerifyEmailStepView(
                        data: data,
                        onNext: { handleVerifyEmail() },
                        onBack: { step = .signUp },
                        onResend: { handleResendVerification() }
                    )
                case .college:
                    CollegeStepView(
                        data: data,
                        schoolSearch: schoolSearch,
                        onNext: { step = .major },
                        onBack: {
                            step = data.isOAuthUser ? .welcome : .verifyEmail
                        }
                    )
                case .major:
                    MajorStepView(data: data, onNext: { step = .interests }, onBack: { step = .college })
                case .interests:
                    InterestsStepView(data: data, onNext: { handleSubmitOnboarding() }, onBack: { step = .major })
                case .setupCourses:
                    // Final initialization step. Confirms the courses
                    // the user just submitted and seeds Home's bubble
                    // field locally — equivalent to the JSX
                    // `saveCourseList` -> `setBubbleCategories(...)`
                    // path (noteworks-library.jsx L9629–L9631). Skip
                    // seeds a single "Untitled Bubble" so Home isn't
                    // blank — matching the JSX `skipCourseSetup`
                    // behaviour (L9641–L9646) and the promise the
                    // confirm modal makes to the user. No back
                    // button — onboarding has already been submitted
                    // server-side, mirroring the JSX modal which only
                    // exposes Skip / Continue.
                    CoursesStepView(
                        data: data,
                        onSave: { codes in
                            let safe = codes.isEmpty ? ["Untitled Bubble"] : codes
                            appState.notesStore.replaceBubbleNames(safe)
                            step = .done
                        },
                        onSkip: {
                            appState.notesStore.replaceBubbleNames(["Untitled Bubble"])
                            step = .done
                        }
                    )
                case .done:
                    // `submit-onboarding` already set `onboarding_completed_at`
                    // and `handleSubmitOnboarding` refetched the profile, so
                    // tapping Explore just lets `ContentView` route to
                    // `MainTabView`. No need to flip a local flag.
                    DoneView(name: data.name, onExplore: {
                        Task { await appState.refreshProfile() }
                    })
                case .skipped:
                    // Skip is a demo / debug shortcut; keep the legacy
                    // "force-authenticated" toggle so the existing entry
                    // points still work, but real users land here only by
                    // bypassing onboarding intentionally.
                    SkippedView(onComplete: { appState.isAuthenticated = true })
                case .forgotPassword:
                    ForgotPasswordView(
                        email: $resetEmail,
                        onSendCode: { handleSendResetCode() },
                        onBack: { step = .signIn }
                    )
                case .resetPassword:
                    ResetPasswordView(
                        code: $resetCode,
                        newPassword: $resetNewPassword,
                        confirmPassword: $resetConfirmPassword,
                        email: resetEmail,
                        onReset: { handleConfirmReset() },
                        onBack: { step = .forgotPassword },
                        onResend: { handleResendResetCode() }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.35), value: step)

            // Loading overlay
            if isLoading {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        // Start downloading the full schools list as soon as we have a
        // valid session. On the `resumeOnboardingAtCollege` path the
        // token is already present at first render; for the sign-up /
        // sign-in / OAuth paths the `onChange` below catches the
        // transition from `nil` to a real token.
        .onAppear {
            if let token = appState.accessToken {
                schoolSearch.prefetchAll(accessToken: token)
            }
        }
        .onChange(of: appState.accessToken) { _, newToken in
            if let newToken {
                schoolSearch.prefetchAll(accessToken: newToken)
            }
        }
    }

    // MARK: - Auth actions (mock for now, real later)

    private func handleSignIn() {
        isLoading = true
        Task {
            do {
                let result = try await appState.authService.signIn(
                    email: signInEmail,
                    password: signInPassword
                )
                appState.handleAuthResult(result)
                // Fetch the profile BEFORE deciding where to send the user.
                // Returning users with `onboarding_completed_at` set should
                // see the "Welcome Back" splash (which then drops them into
                // `MainTabView` via `ContentView`); users with a valid
                // session but unfinished onboarding (e.g. interrupted
                // submission, or sign-up that was confirmed out-of-band)
                // should resume the onboarding form at `.college` instead
                // of being greeted as if they'd been here before.
                let refreshed = await appState.refreshProfile()
                if let refreshed, !refreshed.hasCompletedOnboarding {
                    data.email = refreshed.email
                    step = .college
                } else {
                    step = .signInDone
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleGoogleSignIn() {
        isLoading = true
        Task {
            do {
                let result = try await appState.authService.signInWithGoogle()
                appState.handleAuthResult(result)
                data.isOAuthUser = true
                data.email = result.email
                await routeAfterOAuth()
            } catch {
                if !isUserCancellation(error) {
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    private func handleAppleSignIn() {
        isLoading = true
        Task {
            do {
                let result = try await appState.authService.signInWithApple()
                appState.handleAuthResult(result)
                data.isOAuthUser = true
                data.email = result.email
                await routeAfterOAuth()
            } catch {
                if !isUserCancellation(error) {
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    /// After OAuth succeeds we refresh the profile and only drop the user
    /// into the onboarding form (`.college`) when `onboarding_completed_at`
    /// is still null. If the user has already onboarded, the profile fetch
    /// causes `ContentView` to flip over to `MainTabView` on the next
    /// render — no local step change required.
    private func routeAfterOAuth() async {
        let refreshed = await appState.refreshProfile()
        if let refreshed, refreshed.hasCompletedOnboarding {
            // ContentView will route to MainTabView; nothing to do locally.
            return
        }
        step = .college
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        // ASWebAuthenticationSessionError.canceledLogin (code 1)
        if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
           nsError.code == 1 { return true }
        // ASAuthorizationError.canceled (code 1001)
        if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError",
           nsError.code == 1001 { return true }
        return false
    }

    private func handleSignUp() {
        isLoading = true
        Task {
            do {
                let outcome = try await appState.authService.signUp(
                    name: data.name,
                    email: data.email,
                    password: data.password
                )
                if let token = outcome.accessToken {
                    appState.handleAuthResult(
                        AuthResult(userId: outcome.userId, email: outcome.email, accessToken: token)
                    )
                    step = .college
                } else {
                    step = .verifyEmail
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleVerifyEmail() {
        isLoading = true
        Task {
            do {
                let code = data.verificationCode.joined()
                let result = try await appState.authService.verifyEmail(code: code, email: data.email)
                appState.handleAuthResult(result)
                step = .college
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleResendVerification() {
        guard !data.email.isEmpty else {
            errorMessage = "Add your email on the sign-up step first."
            return
        }
        isLoading = true
        Task {
            do {
                try await appState.authService.resendSignupConfirmation(email: data.email)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleSubmitOnboarding() {
        isLoading = true
        Task {
            do {
                // `OnboardingData.email` / `.name` are only populated when the
                // user walked through the sign-up screen. Sign-in users and
                // some OAuth flows arrive here with those fields empty, so
                // we fall back through every source we know about before
                // the server has a chance to reject the payload with
                // "Name is required" / "school_email is required".
                let resolvedSchoolEmail: String = {
                    let typed = data.schoolEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !typed.isEmpty { return typed }
                    let signup = data.email.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !signup.isEmpty { return signup }
                    let session = appState.currentUser?.email
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let session, !session.isEmpty { return session }
                    return appState.profile?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }()

                let resolvedName: String = {
                    let typed = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !typed.isEmpty { return typed }
                    if let profileName = appState.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !profileName.isEmpty {
                        return profileName
                    }
                    // Last resort: derive a friendly name from the email so
                    // the server's `Name is required` check passes. The user
                    // can change this in the Profile screen afterwards.
                    let emailSource = appState.currentUser?.email ?? data.email
                    let local = emailSource.split(separator: "@").first.map(String.init) ?? emailSource
                    return local.isEmpty ? "Noteworks User" : local
                }()

                let payload = OnboardingPayload(
                    name: resolvedName,
                    yearOfGraduation: data.resolvedYearOfGraduation,
                    schoolAffiliation: data.schoolAffiliationForSubmit,
                    schoolId: data.notAStudent ? nil : data.selectedSchoolId,
                    schoolEmail: resolvedSchoolEmail,
                    courseCodes: data.selectedCourseCodes
                )
                try await appState.authService.submitOnboarding(
                    payload,
                    accessToken: appState.accessToken ?? ""
                )
                // Submit succeeded — surface the post-submit course
                // setup step so the user lands on Home with bubbles
                // already seeded. The submit-onboarding payload above
                // already wrote `course_codes` server-side; this step
                // is local-only and feeds `NotesStore.bubbleNames`.
                step = .setupCourses
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Forgot / Reset password

    private func handleSendResetCode() {
        guard !resetEmail.isEmpty else {
            errorMessage = "Enter your email address."
            return
        }
        isLoading = true
        Task {
            do {
                try await appState.authService.resetPassword(email: resetEmail)
                step = .resetPassword
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleConfirmReset() {
        isLoading = true
        Task {
            do {
                let code = resetCode.joined()
                try await appState.authService.confirmPasswordReset(
                    email: resetEmail,
                    code: code,
                    newPassword: resetNewPassword
                )
                resetCode = ["", "", "", "", "", ""]
                resetNewPassword = ""
                resetConfirmPassword = ""
                step = .signIn
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleResendResetCode() {
        guard !resetEmail.isEmpty else {
            errorMessage = "Go back and enter your email first."
            return
        }
        isLoading = true
        Task {
            do {
                try await appState.authService.resetPassword(email: resetEmail)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    OnboardingFlow()
        .environmentObject(AppState(notesStore: NotesStore.preview()))
}
