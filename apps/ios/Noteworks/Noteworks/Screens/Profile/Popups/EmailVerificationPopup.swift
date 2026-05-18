//
//  EmailVerificationPopup.swift
//  Noteworks
//
//  Mirrors EmailVerificationPopup from
//  others/noteworks-library(2).jsx L619–L800 (two-step flow).
//

import SwiftUI

struct EmailVerificationPopup: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        if viewModel.editingEmail {
            ZStack {
                Color(red: 19/255, green: 29/255, blue: 42/255)
                    .opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.closeEmailPopup() }

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
            Text(isVerifyStep ? "EMAIL VERIFICATION" : "CHANGE EMAIL")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.08 * 12)
                .foregroundStyle(ProfileTheme.textMuted)

            Text(isVerifyStep ? "Enter your verification code." : "Use a new email for your account.")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.03 * 28)
                .foregroundStyle(ProfileTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                isVerifyStep
                    ? "We sent a verification code to \(viewModel.emailDraft). Confirm it here before we update your account email."
                    : "We'll send a verification code to the new address before saving any changes."
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(ProfileTheme.textSecondary)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)

            if !isVerifyStep {
                ProfileField(
                    label: "New Email",
                    value: Binding(
                        get: { viewModel.emailDraft },
                        set: { viewModel.updateEmailDraft($0) }
                    ),
                    placeholder: "name@school.edu",
                    keyboardType: .emailAddress,
                    autocapitalization: .never
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ProfileField(
                        label: "Verification Code",
                        value: Binding(
                            get: { viewModel.emailVerificationCode },
                            set: { viewModel.updateVerificationCode($0) }
                        ),
                        placeholder: "Enter 6-digit code",
                        keyboardType: .numberPad
                    )

                    if !viewModel.emailVerificationError.isEmpty {
                        Text(viewModel.emailVerificationError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ProfileTheme.negative)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !isVerifyStep, !viewModel.emailVerificationError.isEmpty {
                Text(viewModel.emailVerificationError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ProfileTheme.negative)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ProfileSecondaryButton(title: "Cancel") { viewModel.closeEmailPopup() }
                    .frame(maxWidth: .infinity)

                if isVerifyStep {
                    ProfilePrimaryButton(
                        title: viewModel.emailVerificationBusy ? "Verifying…" : "Verify",
                        enabled: !viewModel.emailVerificationBusy
                            && viewModel.emailVerificationCode.count == 6
                    ) {
                        viewModel.saveEmail(using: appState)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ProfilePrimaryButton(
                        title: viewModel.emailVerificationBusy ? "Sending…" : "Continue",
                        enabled: !viewModel.emailVerificationBusy
                            && !viewModel.emailDraft.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        viewModel.sendEmailVerificationCode(using: appState)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
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

    private var isVerifyStep: Bool { viewModel.emailVerificationStep == .verify }
}
