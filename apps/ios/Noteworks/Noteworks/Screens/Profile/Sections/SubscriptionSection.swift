//
//  SubscriptionSection.swift
//  Noteworks
//
//  Mirrors the "subscription" case in renderDetail() from
//  others/noteworks-library(2).jsx L6023–L6052.
//

import SwiftUI

struct SubscriptionSection: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileSectionHeader(
                eyebrow: "Subscription",
                title: "Plan details",
                copy: "Billing and monthly credit behavior live here, separate from the main profile editing area."
            )

            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Plan")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ProfileTheme.textPrimary)
                        Text(viewModel.profile.subscription.plan)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ProfileTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(viewModel.profile.subscription.status)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ProfileTheme.accent)
                }
                .profileRowCard()

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Renewal Date")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(ProfileTheme.textPrimary)
                        Text("Your next billing cycle starts here.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ProfileTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(viewModel.profile.subscription.renewsOn)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ProfileTheme.textPrimary)
                }
                .profileRowCard()
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ProfileStatCard(
                        label: "Monthly Refill",
                        value: "+120",
                        detail: "Credits added at the start of every active billing cycle"
                    )
                    ProfileStatCard(
                        label: "Member Tier",
                        value: "Pro",
                        detail: "Priority access to premium study workflows and new beta features"
                    )
                }
                VStack(spacing: 12) {
                    ProfileStatCard(
                        label: "Monthly Refill",
                        value: "+120",
                        detail: "Credits added at the start of every active billing cycle"
                    )
                    ProfileStatCard(
                        label: "Member Tier",
                        value: "Pro",
                        detail: "Priority access to premium study workflows and new beta features"
                    )
                }
            }

            Text(viewModel.subscriptionHint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ProfileTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                ProfilePrimaryButton(title: "Manage Subscription") {
                    viewModel.subscriptionHint = "Subscription management would open in a secure modal or your App Store account."
                }
                .frame(maxWidth: 220)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }
}
