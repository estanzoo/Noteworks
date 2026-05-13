//
//  GeneralSection.swift
//  Noteworks
//
//  Mirrors the "general" case in renderDetail() from
//  others/noteworks-library(2).jsx L6143–L6291, including the
//  overview + language / migration / referral / storage sub-panes.
//
//  Sign Out is added at the bottom of the overview since the old
//  AccountView housed it and the iOS app can't lose that affordance.
//

import SwiftUI

struct GeneralSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                switch viewModel.generalPanel {
                case .overview:   overviewPanel
                case .language:   languagePanel
                case .migration:  migrationPanel
                case .referral:   referralPanel
                case .storage:    storagePanel
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
            .animation(.easeOut(duration: 0.18), value: viewModel.generalPanel)
        }
    }

    // MARK: - Overview

    private var overviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionHeader(
                eyebrow: "General",
                title: "App-wide preferences and utilities",
                copy: "Keep language, storage, referral, migration, and version tools together in one quieter settings group."
            )

            ProfileOverviewRow(
                title: "Language Selection",
                detail: viewModel.profile.language
            ) { withAnimation { viewModel.generalPanel = .language } }

            ProfileOverviewRow(
                title: "Data Migration",
                detail: viewModel.queuedCount > 0 ? "\(viewModel.queuedCount) imports queued" : "Import from other apps"
            ) { withAnimation { viewModel.generalPanel = .migration } }

            ProfileOverviewRow(
                title: "Referral Program",
                detail: "Invite friend link and rewards"
            ) { withAnimation { viewModel.generalPanel = .referral } }

            ProfileOverviewRow(
                title: "Storage",
                detail: "\(viewModel.totalStorageUsage) MB stored on this device"
            ) { withAnimation { viewModel.generalPanel = .storage } }

            // Version number card
            VStack(alignment: .leading, spacing: 4) {
                Text("Version Number")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ProfileTheme.textPrimary)
                Text(viewModel.profile.version)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .profileRowCard()
            .padding(.top, 6)

            // Sign out (iOS-only affordance carried over from AccountView).
            Button {
                Task { await appState.signOut() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Sign Out")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(PillPressStyle())
            .padding(.top, 8)
        }
    }

    // MARK: - Sub-pane header helper

    @ViewBuilder
    private func subHeader(title: String, copy: String) -> some View {
        HStack {
            ProfileSecondaryButton(title: "Back to General", compact: true) {
                withAnimation { viewModel.generalPanel = .overview }
            }
            .frame(maxWidth: 160)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)

        ProfileSectionHeader(eyebrow: "General", title: title, copy: copy)
    }

    // MARK: - Language

    private var languagePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            subHeader(
                title: "Language Selection",
                copy: "Switch the product language without losing your current profile or study setup."
            )

            FlowLayout(spacing: 8) {
                ForEach(LANGUAGE_OPTIONS, id: \.self) { option in
                    ProfileChoicePill(
                        label: option,
                        active: viewModel.profile.language == option
                    ) {
                        viewModel.profile.language = option
                    }
                }
            }
        }
    }

    // MARK: - Migration

    private var migrationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            subHeader(
                title: "Data Migration",
                copy: "Queue a guided import without filling the main profile screen with every migration row by default."
            )

            VStack(spacing: 10) {
                ForEach(Array(viewModel.migrationStatus.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.source)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(ProfileTheme.textPrimary)
                            Text("Status \(entry.status.rawValue)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ProfileTheme.textSecondary)
                        }
                        Spacer(minLength: 8)

                        Group {
                            if entry.status == .queued {
                                ProfilePrimaryButton(title: "Queued") {
                                    viewModel.queueMigration(entry.source)
                                }
                            } else {
                                ProfileSecondaryButton(title: "Import") {
                                    viewModel.queueMigration(entry.source)
                                }
                            }
                        }
                        .frame(maxWidth: 120)
                    }
                    .profileRowCard()
                }
            }
        }
    }

    // MARK: - Referral

    private var referralPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            subHeader(
                title: "Referral Program",
                copy: "Keep your invite link and reward summary together in one lighter utility screen."
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("INVITE FRIEND LINK")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ProfileTheme.textMuted)

                Text(viewModel.profile.referral.rewardCopy)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
                    .lineSpacing(4)

                InlineLinkAction(
                    label: viewModel.copied ? "Link copied" : viewModel.inviteLink
                ) {
                    viewModel.copyInviteLink()
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ProfileTheme.accent.opacity(0.14),
                                Color.white.opacity(0.38),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ProfileTheme.accent.opacity(0.18), lineWidth: 1)
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ProfileStatCard(
                        label: "Invited",
                        value: "\(viewModel.profile.referral.invited)",
                        detail: "Friends already onboarded"
                    )
                    ProfileStatCard(
                        label: "Pending",
                        value: "\(viewModel.profile.referral.pending)",
                        detail: "Invites still waiting to activate"
                    )
                }
                VStack(spacing: 12) {
                    ProfileStatCard(
                        label: "Invited",
                        value: "\(viewModel.profile.referral.invited)",
                        detail: "Friends already onboarded"
                    )
                    ProfileStatCard(
                        label: "Pending",
                        value: "\(viewModel.profile.referral.pending)",
                        detail: "Invites still waiting to activate"
                    )
                }
            }

            inviteHistoryCard
        }
    }

    private var inviteHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Invite History")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ProfileTheme.textPrimary)
                Text("See who was invited and when each invite was sent.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
            }

            // Header row
            HStack(alignment: .center, spacing: 12) {
                Text("INVITED USER")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("INVITED ON")
                    .frame(width: 120, alignment: .leading)
                Text("STATUS")
                    .frame(width: 110, alignment: .leading)
            }
            .font(.system(size: 11, weight: .bold))
            .tracking(0.08 * 11)
            .foregroundStyle(ProfileTheme.textMuted)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
            }

            ForEach(Array(viewModel.profile.referral.invites.enumerated()), id: \.element.id) { index, invite in
                let active = invite.status == "Activated"
                HStack(alignment: .center, spacing: 12) {
                    Text(invite.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ProfileTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(invite.invitedOn)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ProfileTheme.textSecondary)
                        .frame(width: 120, alignment: .leading)

                    Text(invite.status)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(active ? ProfileTheme.positive : ProfileTheme.warning)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 26)
                        .background(
                            Capsule().fill(
                                active
                                    ? Color(red: 79/255, green: 213/255, blue: 122/255).opacity(0.14)
                                    : Color(red: 246/255, green: 175/255, blue: 72/255).opacity(0.14)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                active
                                    ? Color(red: 79/255, green: 213/255, blue: 122/255).opacity(0.2)
                                    : Color(red: 246/255, green: 175/255, blue: 72/255).opacity(0.2),
                                lineWidth: 1
                            )
                        )
                        .frame(width: 110, alignment: .leading)
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    if index < viewModel.profile.referral.invites.count - 1 {
                        Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .profileInsetCard()
    }

    // MARK: - Storage

    private var storagePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            subHeader(
                title: "Storage",
                copy: "Review what stays on-device so note previews, imports, and media feel fast without letting cached data sprawl."
            )

            // Total card
            VStack(alignment: .leading, spacing: 6) {
                Text("LOCAL USAGE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ProfileTheme.textMuted)
                Text("\(viewModel.totalStorageUsage) MB")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.03 * 28)
                    .foregroundStyle(ProfileTheme.textPrimary)
                Text(viewModel.storageHint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .profileInsetCard()

            VStack(spacing: 10) {
                ForEach(Array(viewModel.storageUsage.enumerated()), id: \.offset) { _, item in
                    let percent = viewModel.totalStorageUsage == 0
                        ? 0.0
                        : Double(item.value) / Double(viewModel.totalStorageUsage)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.label)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(ProfileTheme.textPrimary)
                                Text(item.detail)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ProfileTheme.textSecondary)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text("\(item.value) MB")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ProfileTheme.accent)
                        }
                        ProfileProgressBar(progress: percent)
                    }
                    .profileInsetCard()
                }
            }

            FlowLayout(spacing: 10) {
                ProfileSecondaryButton(title: "Clear Preview Cache") {
                    viewModel.storageHint = "Preview cache cleared. Core note files stay available offline."
                }
                ProfileSecondaryButton(title: "Remove Unused Files") {
                    viewModel.storageHint = "Unused offline files removed. Only pinned study assets remain on-device."
                }
            }
        }
    }
}
