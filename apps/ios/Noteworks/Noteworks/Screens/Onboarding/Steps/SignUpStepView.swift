//
//  SignUpStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct SignUpStepView: View {
    @ObservedObject var data: OnboardingData
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var visible = false
    /// Becomes true the first time the user taps the Next arrow with an
    /// invalid form. Once flipped, every field's error renders live so the
    /// user can watch them clear as they type. Until then we suppress
    /// "Please enter your name." etc. so the screen isn't pre-shouting at
    /// users who just arrived.
    @State private var attemptedNext = false

    /// Password errors that are *always* live (not gated on
    /// `attemptedNext`) so the existing "Min. 8 characters" /
    /// "Passwords don't match" UX still kicks in as soon as the user
    /// types something. The empty-field variant is gated on
    /// `attemptedNext`.
    private var liveOnlyPasswordError: String? {
        guard !data.password.isEmpty, data.password.count < 8 else { return nil }
        return "Password must be at least 8 characters."
    }

    private var liveOnlyVerifyError: String? {
        guard !data.verifyPassword.isEmpty, data.password != data.verifyPassword else { return nil }
        return "Passwords don't match."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 1, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Sign Up", onBack: onBack)

                        OnboardingRow(disabled: false, onNext: handleNext) {
                            OnboardingField(label: "Name", placeholder: "Your name", text: $data.name)
                            OnboardingError(
                                show: attemptedNext && data.signUpNameError != nil,
                                text: data.signUpNameError ?? ""
                            )

                            OnboardingField(label: "Email", placeholder: "name@university.edu", isEmail: true, text: $data.email)
                            OnboardingError(
                                show: data.signUpEmailServerError != nil
                                    || (attemptedNext && data.signUpEmailError != nil),
                                text: data.signUpEmailServerError
                                    ?? data.signUpEmailError
                                    ?? ""
                            )

                            OnboardingField(label: "Password", placeholder: "Min. 8 characters", isSecure: true, text: $data.password)
                            OnboardingError(
                                show: liveOnlyPasswordError != nil || (attemptedNext && data.signUpPasswordError != nil),
                                text: liveOnlyPasswordError ?? data.signUpPasswordError ?? ""
                            )

                            OnboardingField(label: "Verify Password", placeholder: "Re-enter password", isSecure: true, text: $data.verifyPassword)
                            OnboardingError(
                                show: liveOnlyVerifyError != nil || (attemptedNext && data.signUpVerifyPasswordError != nil),
                                text: liveOnlyVerifyError ?? data.signUpVerifyPasswordError ?? ""
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { visible = true }
        }
        // Clear the "email already exists" server error the moment the
        // user edits the email field, so they're not staring at a stale
        // error while typing the corrected address.
        .onChange(of: data.email) { _, _ in
            if data.signUpEmailServerError != nil {
                data.signUpEmailServerError = nil
            }
        }
    }

    private func handleNext() {
        if data.isSignUpValid {
            onNext()
        } else {
            attemptedNext = true
        }
    }
}
