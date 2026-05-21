//
//  ProfileProgressBar.swift
//  Noteworks
//
//  Thin capsule progress bar used in Credits and Storage sections.
//

import SwiftUI

struct ProfileProgressBar: View {
    var progress: Double // 0...1
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.05))
                Capsule()
                    .fill(ProfileTheme.accentGradientHorizontal)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Section header helper

struct ProfileSectionHeader: View {
    let eyebrow: String
    let title: String
    let copy: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.08 * 12)
                .foregroundStyle(ProfileTheme.textMuted)

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.02 * 24)
                .foregroundStyle(ProfileTheme.textPrimary)

            if !copy.isEmpty {
                Text(copy)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 18)
    }
}
