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

// MARK: - Image select mode indicator (cursor + dashed marquee)

/// Status glyph in the tool strip: highlights while an image sticker is
/// selected on the page. Matches `ChromeIconButton` chrome (36×30) but
/// is not tappable — it reflects overlay selection, not a separate tool.
struct ImageSelectModeChromeIcon: View {
    var isActive: Bool

    var body: some View {
        ImageSelectModeGlyph()
            .foregroundStyle(isActive ? NoteEditorTheme.accent : NoteEditorTheme.textPrimary)
            .frame(width: 36, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isActive ? NoteEditorTheme.accent.opacity(0.16) : Color.white.opacity(0.001))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isActive ? NoteEditorTheme.accent.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
            )
            .accessibilityLabel("Image select")
            .accessibilityValue(isActive ? "On" : "Off")
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Mouse cursor inside a dashed selection rectangle.
private struct ImageSelectModeGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(
                    style: StrokeStyle(lineWidth: 1.25, dash: [2.5, 2.2])
                )
                .frame(width: 15, height: 15)

            Image(systemName: "cursorarrow")
                .font(.system(size: 10, weight: .medium))
                .offset(x: 2.5, y: 3.5)
        }
        .frame(width: 18, height: 18)
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
            .clipped()
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

/// Section header with a trailing value tinted by the active tool color.
struct DropdownSectionHeader: View {
    let title: String
    let detail: String
    var detailColor: Color = NoteEditorTheme.accent

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.08 * 11)
                .foregroundStyle(NoteEditorTheme.textSecondary.opacity(0.95))
            Spacer(minLength: 8)
            Text(detail)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(detailColor)
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Capsule option chip (NoteWorks_UI 3 `NoteOptionChip`)

/// Pill toggle used inside the shape / text / eraser dropdowns. Tinted
/// to whatever accent the surrounding tool uses (ink color, shape color,
/// etc.) so the chip color animates with the live selection.
struct NoteOptionChip: View {
    let label: String
    var symbol: String? = nil
    var customLabelFont: Font? = nil
    let isActive: Bool
    var accentColor: Color = NoteEditorTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(customLabelFont ?? .system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isActive ? accentColor : NoteEditorTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? accentColor.opacity(0.14) : Color.white.opacity(0.55))
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive ? accentColor.opacity(0.45) : Color.black.opacity(0.08),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Eraser preview (NoteWorks_UI 3 size preview)

struct EraserSizePreview: View {
    let size: CGFloat
    let isObjectMode: Bool

    var body: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: isObjectMode ? 9 : size / 2, style: .continuous)
                .fill(Color(red: 0xC2/255, green: 0xDB/255, blue: 0xEB/255).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: isObjectMode ? 9 : size / 2, style: .continuous)
                        .strokeBorder(Color(red: 0x8E/255, green: 0xAA/255, blue: 0xC0/255).opacity(0.46), lineWidth: 1)
                )
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0x76/255, green: 0x8F/255, blue: 0xA6/255).opacity(0.16), radius: 8, x: 0, y: 6)
            Spacer()
        }
        .frame(minHeight: 42)
        .animation(.easeOut(duration: 0.12), value: size)
        .animation(.easeOut(duration: 0.18), value: isObjectMode)
    }
}

// MARK: - Pen stroke preview (NoteWorks_UI 3 `PenThicknessPreview`)

struct PenThicknessPreview: View {
    let thickness: CGFloat
    let color: Color

    private var diameter: CGFloat {
        let minThickness: CGFloat = 2
        let maxThickness: CGFloat = 12
        let normalized = (thickness - minThickness) / (maxThickness - minThickness)
        let clamped = Swift.min(1, Swift.max(0, normalized))
        return 8 + clamped * 38
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.17), color.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 34
                    )
                )
                .frame(width: 68, height: 68)

            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .shadow(color: color.opacity(0.20), radius: 13, x: 0, y: 10)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 78)
        .padding(.top, 4)
        .animation(.easeOut(duration: 0.14), value: diameter)
        .animation(.easeOut(duration: 0.14), value: color)
    }
}

// MARK: - Single-line ink palette (pen / highlighter dropdowns)

struct InkColorPaletteRow: View {
    let swatches: [NoteColorSwatch]
    let selectedId: String?
    let usingCustom: Bool
    let customColor: Color
    var swatchSize: CGFloat = 30
    let onSelect: (NoteColorSwatch) -> Void
    let onCustomColor: (Color) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(swatches) { swatch in
                inkSwatchButton(swatch)
            }

            if usingCustom {
                Circle()
                    .fill(customColor)
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(
                        Circle().strokeBorder(NoteEditorTheme.accent, lineWidth: 2)
                    )
            }

            ColorPicker(
                "",
                selection: Binding(
                    get: { customColor },
                    set: onCustomColor
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: swatchSize, height: swatchSize)
            .background(
                Circle()
                    .strokeBorder(
                        usingCustom ? NoteEditorTheme.accent.opacity(0.55) : Color.black.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            )
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func inkSwatchButton(_ swatch: NoteColorSwatch) -> some View {
        let isSelected = !usingCustom && swatch.id == selectedId
        Button {
            onSelect(swatch)
        } label: {
            Circle()
                .fill(swatch.color)
                .frame(width: swatchSize, height: swatchSize)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.white : Color.black.opacity(0.08),
                        lineWidth: isSelected ? 2.5 : 1
                    )
                )
                .shadow(
                    color: isSelected ? swatch.color.opacity(0.35) : .clear,
                    radius: isSelected ? 6 : 0,
                    x: 0,
                    y: isSelected ? 2 : 0
                )
        }
        .buttonStyle(.plain)
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
