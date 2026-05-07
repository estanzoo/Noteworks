//
//  ProfileStatCard.swift
//  Noteworks
//
//  Mirrors ProfileStatCard from others/noteworks-library(2).jsx L446–L460.
//

import SwiftUI

struct ProfileStatCard: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.08 * 11)
                .foregroundStyle(ProfileTheme.textMuted)

            Text(value)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.03 * 28)
                .foregroundStyle(ProfileTheme.textPrimary)

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ProfileTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
        )
    }
}
