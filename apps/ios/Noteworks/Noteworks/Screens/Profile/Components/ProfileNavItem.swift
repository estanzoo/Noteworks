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
    /// When true the row renders as a non-tappable placeholder: greyed
    /// chevron, muted title, and no press feedback. Used while the
    /// language / migration / storage / referral sub-pages are still
    /// under construction.
    var disabled: Bool = false
    /// Optional trailing copy shown next to the chevron (e.g. "Soon").
    var trailingLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: { if !disabled { action() } }) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(disabled ? ProfileTheme.textMuted : ProfileTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ProfileTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                Spacer(minLength: 8)
                if let trailingLabel {
                    Text(trailingLabel.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.08 * 10)
                        .foregroundStyle(ProfileTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.5)))
                        .overlay(Capsule().strokeBorder(ProfileTheme.glassBorder, lineWidth: 1))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProfileTheme.textMuted)
                    .opacity(disabled ? 0.5 : 1)
            }
            .profileRowCard()
            .contentShape(Rectangle())
            .opacity(disabled ? 0.7 : 1)
        }
        .buttonStyle(disabled ? AnyButtonStyle(NoPressStyle()) : AnyButtonStyle(PillPressStyle()))
        .disabled(disabled)
    }
}

/// Type-erased wrapper so `ProfileOverviewRow` can switch between two
/// concrete `ButtonStyle`s based on `disabled`. Using `.buttonStyle()`
/// directly with a `Group` of two different types causes a compile
/// error because the body's view tree depends on a runtime value.
struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { config in AnyView(style.makeBody(configuration: config)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}

/// A no-op button style used when an overview row is disabled — keeps
/// the layout identical to the active row but skips the press scale +
/// opacity feedback so the disabled state looks visually quiet.
private struct NoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
