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

    private var pwTooShort: Bool {
        !data.password.isEmpty && data.password.count < 8
    }

    private var pwMismatch: Bool {
        !data.verifyPassword.isEmpty && data.password != data.verifyPassword
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 1, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Sign Up", onBack: onBack)

                        OnboardingRow(disabled: !data.isSignUpValid, onNext: onNext) {
                            OnboardingField(label: "Name", placeholder: "Your name", text: $data.name)
                            OnboardingField(label: "Email", placeholder: "name@university.edu", isEmail: true, text: $data.email)
                            OnboardingField(label: "Password", placeholder: "Min. 8 characters", isSecure: true, text: $data.password)
                            OnboardingError(show: pwTooShort, text: "Password must be at least 8 characters")
                            OnboardingField(label: "Verify Password", placeholder: "Re-enter password", isSecure: true, text: $data.verifyPassword)
                            OnboardingError(show: pwMismatch, text: "Passwords don't match")
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
    }
}
