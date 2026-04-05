//
//  ResetPasswordView.swift
//  Noteworks
//
//  Created on 2026-04-05.
//

import SwiftUI

struct ResetPasswordView: View {
    @Binding var code: [String]
    @Binding var newPassword: String
    @Binding var confirmPassword: String
    let email: String
    let onReset: () -> Void
    let onBack: () -> Void
    let onResend: () -> Void
    @State private var visible = false
    @FocusState private var focusedIndex: Int?

    private var codeComplete: Bool {
        code.allSatisfy { !$0.isEmpty }
    }

    private var pwTooShort: Bool {
        !newPassword.isEmpty && newPassword.count < 8
    }

    private var pwMismatch: Bool {
        !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    private var isValid: Bool {
        codeComplete && newPassword.count >= 8 && newPassword == confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Reset Password", onBack: onBack)

                        OnboardingRow(disabled: !isValid, onNext: onReset) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("We've sent a reset code to ")
                                    .foregroundStyle(OnboardingTheme.textSecondary)
                                +
                                Text(email.isEmpty ? "your email" : email)
                                    .foregroundStyle(OnboardingTheme.accent)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .padding(.bottom, 28)

                            HStack(spacing: 8) {
                                ForEach(0..<6, id: \.self) { i in
                                    TextField("", text: $code[i])
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(OnboardingTheme.textPrimary)
                                        .frame(width: 48, height: 68)
                                        .background(OnboardingTheme.glassBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    !code[i].isEmpty
                                                        ? OnboardingTheme.accent.opacity(0.6)
                                                        : OnboardingTheme.glassBorder,
                                                    lineWidth: 1.5
                                                )
                                        }
                                        .focused($focusedIndex, equals: i)
                                        .onChange(of: code[i]) { _, newVal in
                                            let filtered = newVal.filter { $0.isNumber }
                                            if filtered != newVal {
                                                code[i] = filtered
                                                return
                                            }
                                            if newVal.count > 1 {
                                                code[i] = String(newVal.suffix(1))
                                            }
                                            if !code[i].isEmpty && i < 5 {
                                                focusedIndex = i + 1
                                            }
                                        }
                                }
                            }
                            .padding(.bottom, 24)

                            Button("Resend code", action: onResend)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OnboardingTheme.accent)
                                .buttonStyle(.plain)
                                .padding(.bottom, 24)

                            OnboardingField(
                                label: "New Password",
                                placeholder: "Min. 8 characters",
                                isSecure: true,
                                text: $newPassword
                            )
                            OnboardingError(show: pwTooShort, text: "Password must be at least 8 characters")

                            OnboardingField(
                                label: "Confirm Password",
                                placeholder: "Re-enter password",
                                isSecure: true,
                                text: $confirmPassword
                            )
                            OnboardingError(show: pwMismatch, text: "Passwords don't match")
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
            focusedIndex = 0
        }
    }
}
