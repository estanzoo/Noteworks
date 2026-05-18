//
//  PasswordChangePopup.swift
//  Noteworks
//
//  Two-step modal that reuses the onboarding forgot-password OTP flow
//  for in-app password changes. Step 1 dispatches a recovery code to
//  the user's current email; step 2 takes the code + new password and
//  calls `confirmPasswordReset` (which `verifyOTP(.recovery)` →
//  `auth.update(user: UserAttributes(password:))` under the hood).
//

import SwiftUI

struct PasswordChangePopup: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        if viewModel.editingPassword {
            ZStack {
                Color(red: 19/255, green: 29/255, blue: 42/255)
                    .opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.closePasswordPopup() }

                popupCard
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .zIndex(70)
        }
    }

    private var popupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isResetStep ? "RESET PASSWORD" : "CHANGE PASSWORD")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.08 * 12)
                .foregroundStyle(ProfileTheme.textMuted)

            Text(isResetStep ? "Enter your code and choose a new password." : "We'll email you a recovery code.")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.03 * 28)
                .foregroundStyle(ProfileTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                isResetStep
                    ? "We sent a 6-digit recovery code to \(viewModel.profile.email). Enter it below along with your new password."
                    : "Tap Send Code and we'll deliver a 6-digit recovery code to \(viewModel.profile.email). Use it to confirm the change."
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(ProfileTheme.textSecondary)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)

            if isResetStep {
                resetFields
            }

            if !viewModel.passwordChangeError.isEmpty {
                Text(viewModel.passwordChangeError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ProfileTheme.negative)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buttonRow
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.8),
                            Color(red: 248/255, green: 251/255, blue: 254/255).opacity(0.64),
                            Color(red: 240/255, green: 246/255, blue: 250/255).opacity(0.56),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 49/255, green: 73/255, blue: 103/255).opacity(0.18), radius: 40, x: 0, y: 26)
    }

    private var resetFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileField(
                label: "Recovery Code",
                value: Binding(
                    get: { viewModel.passwordResetCode },
                    set: { viewModel.updatePasswordResetCode($0) }
                ),
                placeholder: "Enter 6-digit code",
                keyboardType: .numberPad
            )

            ProfileField(
                label: "New Password",
                value: Binding(
                    get: { viewModel.passwordNewValue },
                    set: { viewModel.passwordNewValue = $0; viewModel.passwordChangeError = "" }
                ),
                placeholder: "Min. 8 characters",
                secure: true,
                autocapitalization: .never
            )

            ProfileField(
                label: "Confirm Password",
                value: Binding(
                    get: { viewModel.passwordConfirmValue },
                    set: { viewModel.passwordConfirmValue = $0; viewModel.passwordChangeError = "" }
                ),
                placeholder: "Re-enter password",
                secure: true,
                autocapitalization: .never
            )

            if !viewModel.passwordNewValue.isEmpty, viewModel.passwordNewValue.count < 8 {
                inlineHint("Password must be at least 8 characters.")
            } else if !viewModel.passwordConfirmValue.isEmpty,
                      viewModel.passwordNewValue != viewModel.passwordConfirmValue {
                inlineHint("Passwords don't match.")
            }

            Button("Resend code") {
                viewModel.resendPasswordResetCode(using: appState)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ProfileTheme.accent)
            .buttonStyle(.plain)
            .disabled(viewModel.passwordChangeBusy)
        }
    }

    private func inlineHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ProfileTheme.negative)
    }

    private var buttonRow: some View {
        HStack(spacing: 10) {
            ProfileSecondaryButton(title: "Cancel") { viewModel.closePasswordPopup() }
                .frame(maxWidth: .infinity)

            if isResetStep {
                ProfilePrimaryButton(
                    title: viewModel.passwordChangeBusy ? "Updating…" : "Update Password",
                    enabled: viewModel.canSubmitPasswordReset
                ) {
                    viewModel.confirmPasswordChange(using: appState)
                }
                .frame(maxWidth: .infinity)
            } else {
                ProfilePrimaryButton(
                    title: viewModel.passwordChangeBusy ? "Sending…" : "Send Code",
                    enabled: viewModel.canSendPasswordResetCode
                ) {
                    viewModel.sendPasswordResetCode(using: appState)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private var isResetStep: Bool { viewModel.passwordChangeStep == .reset }
}
