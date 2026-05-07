//
//  CreditsSection.swift
//  Noteworks
//
//  Mirrors the "credits" case in renderDetail() from
//  others/noteworks-library(2).jsx L6053–L6100.
//

import SwiftUI

struct CreditsSection: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileSectionHeader(
                eyebrow: "Credits",
                title: "Balance, history, and usage",
                copy: "This behaves like a deeper settings pane instead of living expanded on the main profile page."
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    availableCard
                    usedCard
                }
                VStack(spacing: 12) {
                    availableCard
                    usedCard
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    historyCard
                    usageCard
                }
                VStack(spacing: 12) {
                    historyCard
                    usageCard
                }
            }
        }
    }

    private var availableCard: some View {
        ProfileStatCard(
            label: "Available Now",
            value: "\(viewModel.profile.credits.balance)",
            detail: "Ready for summaries, quizzes, and citation workflows"
        )
    }

    private var usedCard: some View {
        ProfileStatCard(
            label: "Used This Month",
            value: "\(viewModel.usageTotal)",
            detail: "Tracked across every currently enabled AI tool"
        )
    }

    // MARK: - Credit History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credit History")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ProfileTheme.textPrimary)

            VStack(spacing: 10) {
                ForEach(viewModel.profile.credits.history) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ProfileTheme.textPrimary)
                            Text(item.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ProfileTheme.textSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(item.delta >= 0 ? "+\(item.delta)" : "\(item.delta)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(item.delta >= 0 ? ProfileTheme.positive : ProfileTheme.negative)
                    }
                    .padding(.bottom, 10)
                    .overlay(alignment: .bottom) {
                        if item.id != viewModel.profile.credits.history.last?.id {
                            Rectangle()
                                .fill(Color.black.opacity(0.05))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .profileInsetCard()
    }

    // MARK: - Credit Usage

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credit Usage")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ProfileTheme.textPrimary)

            VStack(spacing: 12) {
                ForEach(viewModel.profile.credits.usage) { item in
                    let percent = item.total == 0 ? 0.0 : Double(item.used) / Double(item.total)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.label)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(ProfileTheme.textPrimary)
                                Text(item.detail)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ProfileTheme.textSecondary)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text("\(item.used)/\(item.total)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ProfileTheme.accent)
                        }
                        ProfileProgressBar(progress: percent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .profileInsetCard()
    }
}
