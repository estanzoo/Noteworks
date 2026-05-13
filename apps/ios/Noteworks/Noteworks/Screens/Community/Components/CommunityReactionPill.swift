//
//  CommunityReactionPill.swift
//  Noteworks
//
//  The like pill (detail popup) and the compact heart button (post card).
//  Both follow the accent style; tap toggles the like state. The backend
//  only models likes — there is no dislike endpoint — so this file is now
//  intentionally single-purpose.
//

import SwiftUI

/// The pill used in the detail popup: "Like 6". Active state fills with
/// the accent color; inactive state is white-on-glass.
struct CommunityReactionPill: View {
    let label: String
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: active ? "heart.fill" : "heart")
                Text(label)
                if count >= 0 {
                    Text("\(count)")
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(active ? CommunityTheme.accent : CommunityTheme.textMuted)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                Capsule()
                    .fill(active ? CommunityTheme.accent.opacity(0.10) : Color.white.opacity(0.56))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        active
                            ? CommunityTheme.accent.opacity(0.26)
                            : Color(red: 220/255, green: 228/255, blue: 236/255).opacity(0.9),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(CommunityReactionPressStyle())
    }
}

/// Compact heart button used on the post card itself — same heart icon
/// plus a count, no label.
struct CommunityCardReactionButton: View {
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: active ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? CommunityTheme.accent : CommunityTheme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(active ? CommunityTheme.accent.opacity(0.08) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(active ? CommunityTheme.accent.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(CommunityReactionPressStyle())
    }
}

struct CommunityReactionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
