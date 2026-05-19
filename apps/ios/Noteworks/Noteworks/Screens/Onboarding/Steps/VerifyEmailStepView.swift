//
//  VerifyEmailStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct VerifyEmailStepView: View {
    @ObservedObject var data: OnboardingData
    let onNext: () -> Void
    let onBack: () -> Void
    let onResend: () -> Void
    @State private var visible = false
    /// See `SignUpStepView.attemptedNext` — flipped on the first invalid
    /// Next tap so the page-level error appears and stays live.
    @State private var attemptedNext = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 2, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Verify your Email", onBack: onBack)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("We've sent a verification code to ")
                                .foregroundStyle(OnboardingTheme.textSecondary)
                            +
                            Text(data.email.isEmpty ? "your email" : data.email)
                                .foregroundStyle(OnboardingTheme.accent)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .padding(.bottom, 28)

                        OnboardingOTPInput(digits: $data.verificationCode)
                            .padding(.bottom, 12)

                        OnboardingError(
                            show: attemptedNext && data.verifyCodeError != nil,
                            text: data.verifyCodeError ?? ""
                        )

                        Button("Resend code", action: onResend)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.accent)
                            .buttonStyle(.plain)
                            .padding(.bottom, 20)

                        HStack {
                            Spacer()
                            ArrowButton(disabled: false, action: handleNext)
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

    private func handleNext() {
        if data.isVerifyValid {
            onNext()
        } else {
            attemptedNext = true
        }
    }
}
