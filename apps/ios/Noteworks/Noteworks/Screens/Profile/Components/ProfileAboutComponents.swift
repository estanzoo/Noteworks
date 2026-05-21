//
//  ProfileAboutComponents.swift
//  Noteworks
//
//  Shared row chrome for Profile → About You, mirroring rowStyle and
//  TinyEditIconButton from others/NoteWorks_UI 4/noteworks-library.jsx
//  L9817–L9845 and L10594–L10603.
//

import SwiftUI

// MARK: - Tiny edit button

struct ProfileTinyEditButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ProfileTheme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.52)))
                .overlay(Circle().strokeBorder(ProfileTheme.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Name / Bio display row

struct ProfileAboutTextRow: View {
    let label: String
    let value: String
    let multiline: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(displayText)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ProfileTheme.textPrimary)
                .lineLimit(multiline ? nil : 1)
                .lineSpacing(multiline ? 4 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProfileTinyEditButton(label: "Edit \(label)", action: onEdit)
        }
        .frame(minHeight: 58, alignment: .center)
        .profileRowCard()
    }

    private var displayText: AttributedString {
        var result = AttributedString()
        var prefix = AttributedString("\(label): ")
        prefix.foregroundColor = ProfileTheme.textMuted
        result.append(prefix)
        var body = AttributedString(value.isEmpty ? "Not set" : value)
        body.foregroundColor = ProfileTheme.textPrimary
        result.append(body)
        return result
    }
}

// MARK: - School / Major / Grade meta row

struct ProfileAboutMetaRow: View {
    let label: String
    let value: String
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ProfileTheme.textMuted)

                Text(value.isEmpty ? "Not set" : value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ProfileTheme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProfileTinyEditButton(label: "Edit \(label)", action: onEdit)
        }
        .frame(minHeight: 74, alignment: .center)
        .profileRowCard()
    }
}
