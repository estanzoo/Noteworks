//
//  NoteEditorTheme.swift
//  Noteworks
//
//  Shared colors + small reusable styles for the canvas chrome. Mirrors
//  the JSX `NOTE_CHROME_*` constants.
//

import SwiftUI

enum NoteEditorTheme {
    static let textPrimary   = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    static let textSecondary = Color(red: 60/255,   green: 60/255,   blue: 67/255).opacity(0.55)
    static let textMuted     = Color(red: 60/255,   green: 60/255,   blue: 67/255).opacity(0.32)
    static let glassBorder   = Color.white.opacity(0.5)
    static let chromeBorder  = Color.white.opacity(0.6)
    static let accent        = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)
    static let danger        = Color(red: 0xC1/255, green: 0x60/255, blue: 0x60/255)
    static let chromeFill    = Color.white.opacity(0.42)
    static let dropdownFill  = Color.white.opacity(0.92)
}

/// Small press-feedback style used on glass icon buttons in the chrome.
struct ChromeIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
