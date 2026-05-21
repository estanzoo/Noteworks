//
//  ProfileButtons.swift
//  Noteworks
//
//  Shared primary / secondary button styles + a small glass icon button used
//  in the profile header, mirroring the inline styles in
//  others/noteworks-library(2).jsx (primaryBtn, secondaryBtn, GlassIconBtn).
//

import SwiftUI

// MARK: - Primary button

struct ProfilePrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(minHeight: 46)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(ProfileTheme.accentGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: ProfileTheme.accent.opacity(0.28), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(PillPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - Secondary button

struct ProfileSecondaryButton: View {
    let title: String
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 12 : 14, weight: compact ? .bold : .semibold))
                .foregroundStyle(ProfileTheme.textPrimary)
                .padding(.horizontal, compact ? 12 : 14)
                .padding(.vertical, compact ? 0 : 11)
                .frame(minHeight: compact ? 34 : 46)
                .frame(maxWidth: compact ? nil : .infinity)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 12 : 15, style: .continuous)
                        .fill(Color.white.opacity(0.42))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 12 : 15, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1.5)
                )
        }
        .buttonStyle(PillPressStyle())
        .frame(maxWidth: compact ? nil : .infinity)
    }
}

// MARK: - Glass icon button (back button on the header)

struct ProfileGlassIconButton: View {
    let systemName: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ProfileTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.35))
                )
                .background(
                    Circle().fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle().strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PillPressStyle())
    }
}

// MARK: - Summary pill

struct ProfileSummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.03 * 12)
                .foregroundStyle(ProfileTheme.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ProfileTheme.textSecondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.white.opacity(0.42))
        )
        .overlay(
            Capsule().strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - Accent chip (plan / credits)

struct ProfileAccentChip: View {
    let text: String
    var emphasized: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: emphasized ? .bold : .semibold))
            .tracking(0.04 * 12)
            .foregroundStyle(emphasized ? ProfileTheme.accent : ProfileTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(emphasized ? ProfileTheme.accent.opacity(0.12) : Color.white.opacity(0.48))
            )
            .overlay(
                Capsule().strokeBorder(
                    emphasized ? ProfileTheme.accent.opacity(0.18) : ProfileTheme.glassBorder,
                    lineWidth: 1
                )
            )
    }
}
