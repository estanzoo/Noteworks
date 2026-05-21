//
//  NoteEditorToolStrip.swift
//  Noteworks
//
//  The bottom row of the chrome card. Three clusters that mirror the JSX
//  `note-tool-strip` (L3755):
//
//    Left   : undo / redo
//    Center : select, pen, eraser, highlighter, lasso, shape, text, image
//    Right  : (reserved)
//
//  Renders without its own glass card so the parent `NoteEditorView` can
//  wrap the entire chrome (header + divider + tool strip) in a single
//  rounded surface, matching the JSX's `note-chrome-shell`.
//

import SwiftUI
import PencilKit

/// Identifier for the dropdown currently expanded in the chrome. Lives at
/// the editor view layer so tapping a different tool collapses the
/// previous panel.
enum NoteEditorPanel: Equatable, Hashable {
    case pen
    case highlighter
    case eraser
    case shape
    case text
    case more
    case background
    case rotate
    case bookmark
    case share
    /// AI Enhancements dropdown anchored under the pill in the header.
    case ai
}

// MARK: - Tool button anchor key

/// Reports the full frame (in a shared coordinate space named
/// `NoteEditorCoord`) of each panel-bearing trigger so the editor view
/// can pop the matching dropdown directly underneath it — using
/// `frame.midX` to center horizontally and `frame.maxY` to position it
/// right below the button rather than below the entire chrome.
struct ToolButtonAnchorKey: PreferenceKey {
    static var defaultValue: [NoteEditorPanel: CGRect] = [:]
    static func reduce(value: inout [NoteEditorPanel: CGRect], nextValue: () -> [NoteEditorPanel: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct NoteEditorToolStrip: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    @Binding var openPanel: NoteEditorPanel?
    var canUndo: Bool = false
    var canRedo: Bool = false
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onOpenThumbnails: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            // Left cluster — undo / redo
            HStack(spacing: 4) {
                ChromeIconButton(symbol: "arrow.uturn.backward") {
                    onUndo()
                }
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.35)

                ChromeIconButton(symbol: "arrow.uturn.forward") {
                    onRedo()
                }
                .disabled(!canRedo)
                .opacity(canRedo ? 1 : 0.35)
            }

            Spacer(minLength: 8)

            // Center cluster — write tools.
            HStack(spacing: 4) {
                toolButton(.pen, symbol: "pencil.tip", panel: .pen)
                toolButton(.eraser, symbol: "eraser", panel: .eraser)
                toolButton(.highlighter, symbol: "highlighter", panel: .highlighter)
                toolButton(.lasso, symbol: "lasso", panel: nil)
                toolButton(.shape, symbol: "square.on.circle", panel: .shape)
                toolButton(.text, symbol: "textformat", panel: .text)
                toolButton(.image, symbol: "photo", panel: nil)
            }

            Spacer(minLength: 8)

            // Right cluster — page thumbnails (NoteWorks_UI 4 tool strip).
            HStack(spacing: 4) {
                ChromeIconButton(
                    symbol: "rectangle.grid.2x2",
                    size: 14,
                    isActive: false,
                    action: onOpenThumbnails
                )
                Color.clear.frame(width: 38, height: 34)
            }
        }
    }

    @ViewBuilder
    private func toolButton(_ tool: NoteEditorTool, symbol: String, panel: NoteEditorPanel?) -> some View {
        let isActive = viewModel.activeTool == tool
        let isComing = !tool.isImplemented
        ChromeIconButton(
            symbol: symbol,
            isActive: isActive,
            tint: isComing ? NoteEditorTheme.textMuted : NoteEditorTheme.textPrimary
        ) {
            // Tap behaviour:
            //   • inactive tool    → just activate it, close panels
            //   • active + has panel → toggle that panel
            //   • active + no panel  → no-op
            //   • coming-soon tool   → flash status, leave activeTool alone
            if isComing {
                viewModel.selectTool(tool)
                return
            }
            if !isActive {
                viewModel.selectTool(tool)
                openPanel = nil
                return
            }
            if let panel {
                openPanel = (openPanel == panel) ? nil : panel
            }
        }
        .background(anchorReporter(for: panel))
    }

    /// Publishes this button's frame to `ToolButtonAnchorKey` so the editor
    /// view can pop the matching dropdown directly underneath. Only buttons
    /// that own a panel report (pen / eraser / highlighter); others return
    /// `EmptyView` so they cost nothing.
    @ViewBuilder
    private func anchorReporter(for panel: NoteEditorPanel?) -> some View {
        if let panel {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("NoteEditorCoord"))
                Color.clear.preference(
                    key: ToolButtonAnchorKey.self,
                    value: [panel: frame]
                )
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Pen panel

struct PenDropdownPanel: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    var body: some View {
        ChromeDropdownPanel(width: 308) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionHeader(
                    title: "Ink color",
                    detail: viewModel.penColorLabel,
                    detailColor: viewModel.penColor
                )

                InkColorPaletteRow(
                    swatches: NoteColorSwatch.penInkPalette,
                    selectedId: viewModel.penSwatchId,
                    usingCustom: viewModel.penUsesCustomColor,
                    customColor: viewModel.penCustomColor,
                    onSelect: { viewModel.selectPenSwatch($0.id) },
                    onCustomColor: { viewModel.setPenCustomColor($0) }
                )

                Divider().padding(.horizontal, 12)

                DropdownSectionHeader(
                    title: "Stroke",
                    detail: viewModel.penThicknessLabel,
                    detailColor: viewModel.penColor
                )

                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { viewModel.penThickness },
                        set: { viewModel.setPenThickness($0) }
                    ), in: 2...12)
                    .tint(viewModel.penColor)

                    HStack {
                        Text("Fine")
                        Spacer()
                        Text("Bold")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.04 * 11)
                    .textCase(.uppercase)
                    .foregroundStyle(NoteEditorTheme.textSecondary.opacity(0.85))

                    PenThicknessPreview(
                        thickness: viewModel.penThickness,
                        color: viewModel.penColor
                    )
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Highlighter panel

struct HighlighterDropdownPanel: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    var body: some View {
        ChromeDropdownPanel(width: 304) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionHeader(
                    title: "Marker color",
                    detail: viewModel.highlighterColorLabel,
                    detailColor: viewModel.highlighterColor
                )

                InkColorPaletteRow(
                    swatches: NoteColorSwatch.highlighterPalette,
                    selectedId: viewModel.highlighterSwatchId,
                    usingCustom: viewModel.highlighterUsesCustomColor,
                    customColor: viewModel.highlighterCustomColor,
                    onSelect: { viewModel.selectHighlighterSwatch($0.id) },
                    onCustomColor: { viewModel.setHighlighterCustomColor($0) }
                )
            }
        }
    }
}

// MARK: - Eraser panel

struct EraserDropdownPanel: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    private var modeLabel: String {
        viewModel.eraserMode == .object ? "Object" : "Regular"
    }

    var body: some View {
        ChromeDropdownPanel(width: 300) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionHeader(
                    title: "Eraser type",
                    detail: modeLabel,
                    detailColor: NoteEditorTheme.textPrimary
                )

                HStack(spacing: 8) {
                    NoteOptionChip(
                        label: "Regular eraser",
                        isActive: viewModel.eraserMode == .regular,
                        accentColor: NoteEditorTheme.textPrimary
                    ) { viewModel.setEraserMode(.regular) }
                    NoteOptionChip(
                        label: "Object eraser",
                        isActive: viewModel.eraserMode == .object,
                        accentColor: NoteEditorTheme.textPrimary
                    ) { viewModel.setEraserMode(.object) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                DropdownSectionHeader(
                    title: "Size",
                    detail: "\(Int(viewModel.eraserSize)) px",
                    detailColor: NoteEditorTheme.textPrimary
                )

                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { viewModel.eraserSize },
                        set: { viewModel.setEraserSize($0) }
                    ), in: 10...34)
                    .tint(NoteEditorTheme.textPrimary)

                    HStack {
                        Text("Small")
                        Spacer()
                        Text("Large")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.04 * 11)
                    .textCase(.uppercase)
                    .foregroundStyle(NoteEditorTheme.textSecondary.opacity(0.85))

                    EraserSizePreview(
                        size: viewModel.eraserSize,
                        isObjectMode: viewModel.eraserMode == .object
                    )
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                Button {
                    viewModel.handleClearPage()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                        Text(viewModel.clearPageArmed ? "Tap again to clear page" : "Clear page")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(viewModel.clearPageArmed ? NoteEditorTheme.danger : NoteEditorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(viewModel.clearPageArmed
                                  ? NoteEditorTheme.danger.opacity(0.10)
                                  : Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(viewModel.clearPageArmed
                                          ? NoteEditorTheme.danger.opacity(0.55)
                                          : Color.black.opacity(0.08),
                                          lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Shape panel

struct ShapeDropdownPanel: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    private let shapeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ChromeDropdownPanel(width: 304) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionHeader(
                    title: "Insert shape",
                    detail: viewModel.shapeType.label,
                    detailColor: viewModel.shapeColor
                )

                LazyVGrid(columns: shapeColumns, spacing: 8) {
                    ForEach(NoteShapeType.allCases) { shape in
                        ShapeTypeIconChip(
                            shape: shape,
                            isActive: viewModel.shapeType == shape,
                            accentColor: viewModel.shapeColor
                        ) {
                            viewModel.selectShapeType(shape)
                        }
                    }
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                DropdownSectionHeader(
                    title: "Color",
                    detail: viewModel.shapeColorLabel,
                    detailColor: viewModel.shapeColor
                )

                InkColorPaletteRow(
                    swatches: NoteColorSwatch.penInkPalette,
                    selectedId: viewModel.shapeSwatchId,
                    usingCustom: viewModel.shapeUsesCustomColor,
                    customColor: viewModel.shapeCustomColor,
                    onSelect: { viewModel.selectShapeSwatch($0.id) },
                    onCustomColor: { viewModel.setShapeCustomColor($0) }
                )
            }
        }
    }
}

// MARK: - Shape icon chip (compact grid — labels live in header + a11y)

private struct ShapeTypeIconChip: View {
    let shape: NoteShapeType
    let isActive: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: shape.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? accentColor : NoteEditorTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? accentColor.opacity(0.14) : Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isActive ? accentColor.opacity(0.45) : Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shape.label)
    }
}

// MARK: - Text panel

struct TextDropdownPanel: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    var body: some View {
        ChromeDropdownPanel(width: 324) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionHeader(
                    title: "Font",
                    detail: viewModel.textFont.label,
                    detailColor: viewModel.textColor
                )

                HStack(spacing: 8) {
                    ForEach(NoteTextFont.allCases) { font in
                        NoteOptionChip(
                            label: font.label,
                            customLabelFont: font.displayFont(size: 12, weight: .semibold),
                            isActive: viewModel.textFont == font,
                            accentColor: viewModel.textColor
                        ) { viewModel.selectTextFont(font) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                DropdownSectionHeader(
                    title: "Size",
                    detail: "\(Int(viewModel.textSize)) pt",
                    detailColor: viewModel.textColor
                )

                VStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { viewModel.textSize },
                        set: { viewModel.setTextSize($0) }
                    ), in: 14...44)
                    .tint(viewModel.textColor)

                    HStack {
                        Text("Small")
                        Spacer()
                        Text("Large")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.04 * 11)
                    .textCase(.uppercase)
                    .foregroundStyle(NoteEditorTheme.textSecondary.opacity(0.85))
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                DropdownSectionHeader(
                    title: "Color",
                    detail: viewModel.textColorLabel,
                    detailColor: viewModel.textColor
                )

                InkColorPaletteRow(
                    swatches: NoteColorSwatch.penInkPalette,
                    selectedId: viewModel.textSwatchId,
                    usingCustom: viewModel.textUsesCustomColor,
                    customColor: viewModel.textCustomColor,
                    onSelect: { viewModel.selectTextSwatch($0.id) },
                    onCustomColor: { viewModel.setTextCustomColor($0) }
                )

                Divider().padding(.horizontal, 12)

                Button {
                    viewModel.triggerTextInsert()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Insert text")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Compose")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.06 * 11)
                            .textCase(.uppercase)
                            .foregroundStyle(viewModel.textColor.opacity(0.85))
                    }
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(viewModel.textColor.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
    }
}
