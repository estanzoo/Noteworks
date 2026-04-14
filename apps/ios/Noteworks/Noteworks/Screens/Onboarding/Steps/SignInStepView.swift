//
//  SignInStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct SignInStepView: View {
    @Binding var email: String
    @Binding var password: String
    let onSignIn: () -> Void
    let onBack: () -> Void
    let onForgotPassword: () -> Void

    @State private var visible = false

    private var isValid: Bool {
        !email.isEmpty && password.count >= 8
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Welcome Back", onBack: onBack)

                        Text("Sign in with your email and password.")
                            .font(.system(size: 15))
                            .foregroundStyle(OnboardingTheme.textSecondary)
                            .lineSpacing(4)
                            .padding(.bottom, 24)

                        OnboardingRow(disabled: !isValid, onNext: onSignIn) {
                            OnboardingField(
                                label: "Email",
                                placeholder: "name@university.edu",
                                isEmail: true,
                                text: $email
                            )

                            OnboardingField(
                                label: "Password",
                                placeholder: "Min. 8 characters",
                                isSecure: true,
                                text: $password
                            )
                        }

                        HStack {
                            HStack(spacing: 4) {
                                Text("Don't have an account?")
                                    .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.4))
                                Button("Sign up") { onBack() }
                                    .foregroundStyle(OnboardingTheme.accent)
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            Button("Forgot password?", action: onForgotPassword)
                                .foregroundStyle(OnboardingTheme.accent)
                                .fontWeight(.medium)
                                .buttonStyle(.plain)
                        }
                        .font(.system(size: 14))
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { visible = true }
        }
    }
}
