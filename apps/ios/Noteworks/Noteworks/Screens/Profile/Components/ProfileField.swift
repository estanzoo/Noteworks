//
//  ProfileField.swift
//  Noteworks
//
//  Mirrors the ProfileField component from others/noteworks-library(2).jsx L395–L444.
//

import SwiftUI

struct ProfileField: View {
    let label: String
    @Binding var value: String
    var placeholder: String = ""
    var multiline: Bool = false
    /// When true, shows non-editable text with the same chrome as a
    /// single-line `TextField` (used for Grade derived from onboarding).
    var readOnly: Bool = false
    /// When true, renders a `SecureField` instead of a `TextField` so
    /// password input is masked. Ignored when `multiline` is true.
    var secure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.04 * 12)
                .foregroundStyle(ProfileTheme.textMuted)

            Group {
                if multiline {
                    TextEditor(text: $value)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 112)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .font(.system(size: 14))
                        .foregroundStyle(ProfileTheme.textPrimary)
                        .focused($focused)
                        .overlay(alignment: .topLeading) {
                            if value.isEmpty {
                                Text(placeholder)
                                    .font(.system(size: 14))
                                    .foregroundStyle(ProfileTheme.textMuted)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }
                } else if readOnly {
                    Text(value.isEmpty ? placeholder : value)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .font(.system(size: 14))
                        .foregroundStyle(
                            value.isEmpty ? ProfileTheme.textMuted : ProfileTheme.textPrimary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                } else if secure {
                    SecureField(placeholder, text: $value)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .font(.system(size: 14))
                        .foregroundStyle(ProfileTheme.textPrimary)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(true)
                } else {
                    TextField(placeholder, text: $value)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .font(.system(size: 14))
                        .foregroundStyle(ProfileTheme.textPrimary)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(keyboardType == .emailAddress)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        focused ? ProfileTheme.accent.opacity(0.5) : Color.black.opacity(0.06),
                        lineWidth: 1.5
                    )
            )
            .shadow(
                color: focused ? ProfileTheme.accent.opacity(0.16) : .clear,
                radius: 3,
                x: 0,
                y: 0
            )
            .animation(.easeInOut(duration: 0.15), value: focused)
        }
    }
}
