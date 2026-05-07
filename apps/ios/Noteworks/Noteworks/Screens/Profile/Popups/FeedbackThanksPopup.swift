//
//  FeedbackThanksPopup.swift
//  Noteworks
//
//  Mirrors FeedbackThanksPopup from others/noteworks-library(2).jsx L541–L617.
//

import SwiftUI

struct FeedbackThanksPopup: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        if viewModel.feedbackPopup.open {
            ZStack {
                Color(red: 19/255, green: 29/255, blue: 42/255)
                    .opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                popupCard
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .zIndex(70)
        }
    }

    private var popupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Check badge
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ProfileTheme.accent.opacity(0.2), Color.white.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ProfileTheme.accent.opacity(0.18), lineWidth: 1)
                    .frame(width: 56, height: 56)

                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ProfileTheme.accent)
            }
            .padding(.bottom, 16)

            Text("FEEDBACK SENT")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.08 * 12)
                .foregroundStyle(ProfileTheme.textMuted)

            Text("Thanks for helping shape NoteWorks.")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.03 * 28)
                .foregroundStyle(ProfileTheme.textPrimary)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)

            Text("We really appreciate the suggestion. Every beta report helps us tune the product faster and with more confidence.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ProfileTheme.textSecondary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.feedbackPopup.followUpEnabled {
                let email = viewModel.feedbackPopup.contactEmail
                let suffix = email.isEmpty ? "" : " at \(email)"
                Text("We'll get back to you within 48 hours\(suffix).")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ProfileTheme.textPrimary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(ProfileTheme.accent.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(ProfileTheme.accent.opacity(0.16), lineWidth: 1)
                    )
                    .padding(.top, 16)
            }

            HStack {
                Spacer()
                ProfilePrimaryButton(title: "Done") { close() }
                    .frame(maxWidth: 140)
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func close() {
        viewModel.feedbackPopup.open = false
    }
}
