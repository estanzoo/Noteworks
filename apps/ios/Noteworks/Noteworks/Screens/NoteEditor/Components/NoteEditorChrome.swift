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
    var size: CGFloat = 15
    var isActive: Bool = false
    var tint: Color = NoteEditorTheme.textPrimary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? NoteEditorTheme.accent : tint)
                // 36×30 keeps a comfortable 44pt slop-radius once 4pt of
                // row padding is included, while shaving 4pt off every
                // chrome row vs the previous 38×34. Two rows × 4pt × the
                // two buttons-tall chrome = noticeable canvas gain.
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isActive ? NoteEditorTheme.accent.opacity(0.16) : Color.white.opacity(0.001))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
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
    /// Maximum swatches to lay out in a single row. Once exceeded, the
    /// palette wraps to a second row. Pen palette (9 colors) needs this
    /// to wrap; highlighter (4 colors) fits on a single row regardless.
    var maxPerRow: Int = 6
    let onSelect: (NoteColorSwatch) -> Void

    /// Splits the palette into chunks of at most `maxPerRow` swatches so
    /// the row layout naturally wraps inside the 240pt dropdown without
    /// overflowing its bounds (which is what produced the original
    /// "color is out of bounds" bug after we widened the pen palette
    /// from 6 to 9 swatches).
    private var rows: [[NoteColorSwatch]] {
        guard maxPerRow > 0 else { return [swatches] }
        var result: [[NoteColorSwatch]] = []
        var remaining = swatches[...]
        while !remaining.isEmpty {
            let chunk = remaining.prefix(maxPerRow)
            result.append(Array(chunk))
            remaining = remaining.dropFirst(chunk.count)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { swatch in
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
                    // Pad the last row with invisible spacers so the
                    // wrapped row aligns leading with the row above it
                    // instead of recentering its fewer swatches.
                    if row.count < maxPerRow {
                        ForEach(0..<(maxPerRow - row.count), id: \.self) { _ in
                            Color.clear.frame(width: 24, height: 24)
                        }
                    }
                }
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

// MARK: - Share / upload menu (matches NoteWorks_UI 2 header dropdown)

/// Two-row panel opened from the share icon: community composer vs
/// system share sheet (PDF).
struct ShareUploadDropdown: View {
    let onUploadToCommunity: () -> Void
    let onUploadToOtherApps: () -> Void

    var body: some View {
        ChromeDropdownPanel(width: 272) {
            VStack(spacing: 8) {
                uploadRow(
                    title: "Share to Community",
                    detail: "Open a post composer with this note attached.",
                    action: onUploadToCommunity
                )
                uploadRow(
                    title: "Share to Other Apps",
                    detail: "Use the iOS share sheet with a PDF export.",
                    action: onUploadToOtherApps
                )
            }
            .padding(.horizontal, 8)
        }
    }

    private func uploadRow(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(NoteEditorTheme.chromeBorder.opacity(0.92), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
