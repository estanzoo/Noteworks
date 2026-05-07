//
//  SecuritySection.swift
//  Noteworks
//
//  Mirrors the "security" case in renderDetail() from
//  others/noteworks-library(2).jsx L6101–L6142.
//

import SwiftUI

struct SecuritySection: View {
    @ObservedObject var viewModel: ProfileViewModel

    private struct LinkedProvider: Identifiable {
        let id: String
        let label: String
        let detail: String
        let keyPath: WritableKeyPath<SecurityLinks, Bool>
    }

    private let providers: [LinkedProvider] = [
        LinkedProvider(id: "google",  label: "Google",   detail: "Quick sign-in and recovery",                  keyPath: \.googleLinked),
        LinkedProvider(id: "apple",   label: "Apple ID", detail: "Private sign-in across devices",              keyPath: \.appleLinked),
        LinkedProvider(id: "notion",  label: "Notion",   detail: "Connected workspace and shared import access", keyPath: \.notionLinked),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                eyebrow: "Security Settings",
                title: "Password and third-party links",
                copy: "Each item behaves like a deeper settings screen instead of expanding the whole page at once."
            )

            VStack(spacing: 10) {
                // Email row
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email Address")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ProfileTheme.textPrimary)
                        Text("\(viewModel.profile.email)\(viewModel.academicEmailVerified ? " · Verified educational email" : " · Standard account email")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ProfileTheme.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    ProfileSecondaryButton(title: "Change Email") { viewModel.openEmailPopup() }
                        .frame(maxWidth: 140)
                }
                .profileRowCard()

                // Change password row
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Change Password")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ProfileTheme.textPrimary)
                        Text("Refresh your password and recovery method.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ProfileTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    ProfileSecondaryButton(title: "Update") {
                        viewModel.securityHint = "Password reset flow would open in a secure modal here."
                    }
                    .frame(maxWidth: 120)
                }
                .profileRowCard()

                // Linked providers
                ForEach(providers) { provider in
                    let linked = viewModel.profile.security[keyPath: provider.keyPath]
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.label)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ProfileTheme.textPrimary)
                            Text(provider.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ProfileTheme.textSecondary)
                        }
                        Spacer(minLength: 8)

                        Group {
                            if linked {
                                ProfilePrimaryButton(title: "Linked") {
                                    toggle(keyPath: provider.keyPath)
                                }
                            } else {
                                ProfileSecondaryButton(title: "Connect") {
                                    toggle(keyPath: provider.keyPath)
                                }
                            }
                        }
                        .frame(maxWidth: 130)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(linked ? ProfileTheme.accent.opacity(0.08) : Color.white.opacity(0.34))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                linked ? ProfileTheme.accent.opacity(0.22) : ProfileTheme.glassBorder,
                                lineWidth: 1
                            )
                    )
                }
            }

            Text(viewModel.securityHint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ProfileTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func toggle(keyPath: WritableKeyPath<SecurityLinks, Bool>) {
        var next = viewModel.profile.security
        next[keyPath: keyPath].toggle()
        viewModel.profile.security = next
    }
}
