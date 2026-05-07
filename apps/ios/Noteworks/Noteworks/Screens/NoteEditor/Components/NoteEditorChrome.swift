//
//  NoteEditorChrome.swift
//  Noteworks
//
//  Reusable chrome primitives shared by the header bar, tool strip, and
//  More menu. Kept in one file so the editor view file stays focused on
//  layout.
//

import SwiftUI

// MARK: - Chrome icon button (single-glyph, glass)

struct ChromeIconButton: View {
    let symbol: String
    var size: CGFloat = 17
    var isActive: Bool = false
    var tint: Color = NoteEditorTheme.textPrimary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? NoteEditorTheme.accent : tint)
                .frame(width: 38, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? NoteEditorTheme.accent.opacity(0.16) : Color.white.opacity(0.001))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isActive ? NoteEditorTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(ChromeIconPressStyle())
    }
}

// MARK: - Chrome label button (icon + label) used in dropdown rows

struct ChromeMenuRow: View {
    let icon: String?
    let title: String
    var detail: String? = nil
    var trailing: AnyView? = nil
    var tint: Color = NoteEditorTheme.textPrimary
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(NoteEditorTheme.textSecondary)
                    }
                }
                Spacer(minLength: 4)
                if let trailing { trailing }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

// MARK: - Chrome dropdown panel (glass card)

struct ChromeDropdownPanel<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: width, alignment: .leading)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .background(NoteEditorTheme.dropdownFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Color palette grid

struct PaletteSwatchRow: View {
    let swatches: [NoteColorSwatch]
    let selectedId: String?
    let usingCustom: Bool
    let onSelect: (NoteColorSwatch) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(swatches) { swatch in
                Button {
                    onSelect(swatch)
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().strokeBorder(
                                (!usingCustom && swatch.id == selectedId)
                                    ? NoteEditorTheme.accent
                                    : Color.black.opacity(0.08),
                                lineWidth: (!usingCustom && swatch.id == selectedId) ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Section header used inside dropdowns

struct DropdownSectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.08 * 10)
            .foregroundStyle(NoteEditorTheme.textSecondary)
            .padding(.horizontal, 12)
    }
}
