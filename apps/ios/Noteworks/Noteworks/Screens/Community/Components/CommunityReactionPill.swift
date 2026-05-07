//
//  CommunityReactionPill.swift
//  Noteworks
//
//  Mirrors CommunityReactionPill (JSX L4490–L4509) and the small reaction
//  buttons on PostCard (JSX L5100–L5114).
//

import SwiftUI

/// The pill used in the detail popup + comments: "Like 6" / "Dislike 0".
struct CommunityReactionPill: View {
    let label: String
    let count: Int
    let kind: ReactionKind
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                if count >= 0 {
                    Text("\(count)")
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(active ? activeColor : CommunityTheme.textMuted)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                Capsule()
                    .fill(active ? activeColor.opacity(0.10) : Color.white.opacity(0.56))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        active
                            ? activeColor.opacity(0.26)
                            : Color(red: 220/255, green: 228/255, blue: 236/255).opacity(0.9),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(CommunityReactionPressStyle())
    }

    private var activeColor: Color {
        switch kind {
        case .like:    return CommunityTheme.accent
        case .dislike: return CommunityTheme.dislike
        }
    }
}

/// Compact reaction button used on the PostCard itself (JSX L5100–L5114).
struct CommunityCardReactionButton: View {
    let kind: ReactionKind
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? activeColor : CommunityTheme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(active ? activeColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(active ? activeColor.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(CommunityReactionPressStyle())
    }

    private var iconName: String {
        switch kind {
        case .like:    return active ? "heart.fill" : "heart"
        case .dislike: return active ? "hand.thumbsdown.fill" : "hand.thumbsdown"
        }
    }

    private var activeColor: Color {
        switch kind {
        case .like:    return CommunityTheme.accent
        case .dislike: return CommunityTheme.dislike
        }
    }
}

struct CommunityReactionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
