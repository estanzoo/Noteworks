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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(
                eyebrow: "Security Settings",
                title: "Email and password",
                copy: "Manage how you sign in to NoteWorks. Third-party provider links will return in a later release."
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
                        viewModel.openPasswordPopup()
                    }
                    .frame(maxWidth: 120)
                }
                .profileRowCard()
            }

            Text(viewModel.securityHint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ProfileTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}
