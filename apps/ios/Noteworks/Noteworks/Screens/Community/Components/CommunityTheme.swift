//
//  CommunityTheme.swift
//  Noteworks
//
//  Shared colors + glass styling for the Community screen, mirroring
//  the constants in others/noteworks-library(2).jsx (L4–L10) and the
//  GlassCard body used on PostCard / PostNewCard / detail popup.
//

import SwiftUI

enum CommunityTheme {
    static let textPrimary   = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    static let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
    static let textMuted     = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
    static let glassBorder   = Color.white.opacity(0.5)
    static let accent        = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)
    static let accentSoft    = Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)

    /// The red used by the dislike reaction in the JSX (#E46464).
    static let dislike       = Color(red: 0xE4/255, green: 0x64/255, blue: 0x64/255)

    static let accentGradient = LinearGradient(
        colors: [accent, accentSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Avatar initials badge

/// Circular glass avatar showing initials (JSX L4730–L4732, L4567–L4583).
struct CommunityAvatar: View {
    let name: String
    var size: CGFloat = 40
    var nested: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(nested ? CommunityTheme.accent.opacity(0.1) : Color(red: 222/255, green: 233/255, blue: 242/255).opacity(0.94))
            Circle()
                .strokeBorder(
                    nested ? CommunityTheme.accent.opacity(0.12) : CommunityTheme.glassBorder,
                    lineWidth: 1
                )
            Text(nameToInitials(name))
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(CommunityTheme.accent)
        }
        .frame(width: size, height: size)
    }
}
