//
//  OnboardingTheme.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

enum OnboardingTheme {
    static let accent = Color(red: 94/255, green: 173/255, blue: 211/255)         // #5EADD3
    static let accentDark = Color(red: 58/255, green: 143/255, blue: 176/255)     // #3A8FB0
    static let textPrimary = Color(red: 28/255, green: 28/255, blue: 30/255)      // #1C1C1E
    static let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
    static let textLabel = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.8)
    static let glassBg = Color.white.opacity(0.5)
    static let glassBorder = Color.white.opacity(0.5)
    static let errorColor = Color(red: 212/255, green: 96/255, blue: 77/255)      // #D4604D

    static let accentGradient = LinearGradient(
        colors: [Color(red: 94/255, green: 173/255, blue: 211/255),
                 Color(red: 124/255, green: 196/255, blue: 228/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
