//
//  ForgotPasswordView.swift
//  Noteworks
//
//  Created on 2026-04-05.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Binding var email: String
    let onSendCode: () -> Void
    let onBack: () -> Void
    @State private var visible = false

    private var isValid: Bool {
        !email.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Forgot Password", onBack: onBack)

                        Text("Enter your email and we'll send you a code to reset your password.")
                            .font(.system(size: 15))
                            .foregroundStyle(OnboardingTheme.textSecondary)
                            .lineSpacing(4)
                            .padding(.bottom, 24)

                        OnboardingRow(disabled: !isValid, onNext: onSendCode) {
                            OnboardingField(
                                label: "Email",
                                placeholder: "you@example.com",
                                isEmail: true,
                                text: $email
                            )
                        }
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
