//
//  ProfileTheme.swift
//  Noteworks
//
//  Mirrors SF / ACCENT / TEXT_* / GLASS_BORDER constants from
//  others/noteworks-library(2).jsx L4–L10.
//

import SwiftUI

enum ProfileTheme {
    // Colors
    static let accent       = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)
    static let accentSoft   = Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)
    static let textPrimary  = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    static let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
    static let textMuted     = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
    static let glassBorder   = Color.white.opacity(0.5)

    // Semantic colors used in a few spots
    static let positive = Color(red: 46/255,  green: 139/255, blue: 87/255) // #2E8B57
    static let warning  = Color(red: 199/255, green: 133/255, blue: 47/255) // #C7852F
    static let negative = Color(red: 193/255, green: 96/255,  blue: 96/255) // #C16060

    // Fonts
    static func sf(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // Accent gradient used on primary buttons / progress bars.
    static let accentGradient = LinearGradient(
        colors: [accent, accentSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradientHorizontal = LinearGradient(
        colors: [accent, accentSoft],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Small shared modifiers

extension View {
    /// Rounded container used for section rows (JSX rowStyle, L5936–L5945).
    func profileRowCard() -> some View {
        self.padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
            )
    }

    /// 18pt radius lightly tinted container used for inset info cards.
    func profileInsetCard(tinted: Bool = false) -> some View {
        self.padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(tinted ? ProfileTheme.accent.opacity(0.08) : Color.white.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        tinted ? ProfileTheme.accent.opacity(0.18) : ProfileTheme.glassBorder,
                        lineWidth: 1
                    )
            )
    }
}
