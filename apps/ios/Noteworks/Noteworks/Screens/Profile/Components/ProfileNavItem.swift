//
//  ProfileNavItem.swift
//  Noteworks
//
//  Mirrors ProfileNavItem from others/noteworks-library(2).jsx L480–L510.
//

import SwiftUI

struct ProfileNavItem: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(active ? ProfileTheme.accent : ProfileTheme.textPrimary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? ProfileTheme.accent : ProfileTheme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? ProfileTheme.accent.opacity(0.1) : Color.white.opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        active ? ProfileTheme.accent.opacity(0.24) : Color.white.opacity(0.4),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: active ? ProfileTheme.accent.opacity(0.08) : .clear, radius: 10, x: 0, y: 3)
        }
        .buttonStyle(PillPressStyle())
    }
}

/// A lighter row used for overview lists (e.g. General > overview).
struct ProfileOverviewRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ProfileTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ProfileTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProfileTheme.textMuted)
            }
            .profileRowCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(PillPressStyle())
    }
}
