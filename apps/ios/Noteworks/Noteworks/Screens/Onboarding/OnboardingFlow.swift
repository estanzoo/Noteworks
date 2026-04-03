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
    case done = 8
    case skipped = 9
}

struct OnboardingFlow: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var data = OnboardingData()
    @State private var step: OnboardingStep = .welcome
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var signInEmail = ""
    @State private var signInPassword = ""

    var body: some View {
        ZStack {
            OnboardingBackground()
                .ignoresSafeArea()

            // Beta badge (visible on form steps, not sign-in or welcome)
            if step.rawValue >= OnboardingStep.signUp.rawValue && step.rawValue <= OnboardingStep.interests.rawValue {
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
                        onSkip: { step = .skipped }
                    )
                case .signIn:
                    SignInStepView(
                        email: $signInEmail,
                        password: $signInPassword,
                        onSignIn: { handleSignIn() },
                        onBack: { step = .welcome }
                    )
                case .signInDone:
                    SignInDoneView(
                        email: signInEmail,
                        onContinue: { appState.isAuthenticated = true }
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
                    CollegeStepView(data: data, onNext: { step = .major }, onBack: { step = .verifyEmail })
                case .major:
                    MajorStepView(data: data, onNext: { step = .interests }, onBack: { step = .college })
                case .interests:
                    InterestsStepView(data: data, onNext: { handleSubmitOnboarding() }, onBack: { step = .major })
                case .done:
                    DoneView(name: data.name, onExplore: { appState.isAuthenticated = true })
                case .skipped:
                    SkippedView(onComplete: { appState.isAuthenticated = true })
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
                step = .signInDone
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
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
                let payload = OnboardingPayload(
                    name: data.name,
                    yearOfGraduation: data.resolvedYearOfGraduation,
                    schoolAffiliation: data.schoolAffiliationForSubmit,
                    schoolEmail: data.email.trimmingCharacters(in: .whitespacesAndNewlines),
                    courseCodes: []
                )
                try await appState.authService.submitOnboarding(
                    payload,
                    accessToken: appState.accessToken ?? ""
                )
                step = .done
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    OnboardingFlow()
        .environmentObject(AppState())
}
