//
//  ProfileChoicePill.swift
//  Noteworks
//
//  Mirrors ProfileChoicePill from others/noteworks-library(2).jsx L462–L478.
//

import SwiftUI

struct ProfileChoicePill: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? ProfileTheme.accent : ProfileTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(active ? ProfileTheme.accent.opacity(0.12) : Color.white.opacity(0.36))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            active ? ProfileTheme.accent.opacity(0.45) : Color.black.opacity(0.06),
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(PillPressStyle())
    }
}

struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
