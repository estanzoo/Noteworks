//
//  NoteEditorToolStrip.swift
//  Noteworks
//
//  The bottom row of the chrome card. Three clusters that mirror the JSX
//  `note-tool-strip` (L3755):
//
//    Left   : undo / redo
//    Center : pen, eraser, highlighter, lasso, shape, text, image
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
    case more
    case background
    case rotate
    case bookmark
    case share
    /// AI Enhancements dropdown anchored under the pill in the header.
    case ai
}

// MARK: - Tool button anchor key

/// Reports the global midX (in a shared coordinate space named
/// `NoteEditorCoord`) of each panel-bearing tool button so the editor view
/// can pop the matching dropdown directly underneath it.
struct ToolButtonAnchorKey: PreferenceKey {
    static var defaultValue: [NoteEditorPanel: CGFloat] = [:]
    static func reduce(value: inout [NoteEditorPanel: CGFloat], nextValue: () -> [NoteEditorPanel: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct NoteEditorToolStrip: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    @Binding var openPanel: NoteEditorPanel?
    /// Wired up to the live `PKCanvasView.undoManager` so undo/redo work
    /// against PencilKit's own stack.
    var undoManager: UndoManager?

    var body: some View {
        HStack(spacing: 0) {
            // Left cluster — undo / redo
            HStack(spacing: 4) {
                ChromeIconButton(symbol: "arrow.uturn.backward") {
                    undoManager?.undo()
                    viewModel.flashStatus("Undo")
                }
                .disabled(!(undoManager?.canUndo ?? false))
                .opacity((undoManager?.canUndo ?? false) ? 1 : 0.35)

                ChromeIconButton(symbol: "arrow.uturn.forward") {
                    undoManager?.redo()
                    viewModel.flashStatus("Redo")
                }
                .disabled(!(undoManager?.canRedo ?? false))
                .opacity((undoManager?.canRedo ?? false) ? 1 : 0.35)
            }

            Spacer(minLength: 8)

            // Center cluster — the seven tools, mirroring JSX order.
            HStack(spacing: 4) {
                toolButton(.pen, symbol: "pencil.tip", panel: .pen)
                toolButton(.eraser, symbol: "eraser", panel: .eraser)
                toolButton(.highlighter, symbol: "highlighter", panel: .highlighter)
                toolButton(.lasso, symbol: "lasso", panel: nil)
                toolButton(.shape, symbol: "square.on.circle", panel: nil)
                toolButton(.text, symbol: "textformat", panel: nil)
                toolButton(.image, symbol: "photo", panel: nil)
            }

            Spacer(minLength: 8)

            // Right cluster reserved (kept as an invisible mirror of the
            // left cluster's width so the tool row stays visually
            // centered relative to the chrome).
            HStack(spacing: 4) {
                Color.clear.frame(width: 38, height: 34)
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

    /// Publishes this button's midX to `ToolButtonAnchorKey` so the editor
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
                    value: [panel: frame.midX]
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
        ChromeDropdownPanel(width: 240) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionTitle(text: "Color")
                PaletteSwatchRow(
                    swatches: NoteColorSwatch.palette,
                    selectedId: viewModel.penSwatchId,
                    usingCustom: viewModel.penUsesCustomColor
                ) { swatch in
                    viewModel.selectPenSwatch(swatch.id)
                }
                .padding(.horizontal, 12)

                HStack {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { viewModel.penCustomColor },
                            set: { viewModel.setPenCustomColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    Text("Custom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.penUsesCustomColor
                                         ? NoteEditorTheme.accent
                                         : NoteEditorTheme.textSecondary)
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                DropdownSectionTitle(text: "Stroke")
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { viewModel.penThickness },
                        set: { viewModel.setPenThickness($0) }
                    ), in: 2...12)
                    .tint(NoteEditorTheme.accent)
                    Text("\(Int(viewModel.penThickness))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                        .frame(width: 24, alignment: .trailing)
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
        ChromeDropdownPanel(width: 240) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionTitle(text: "Color")
                PaletteSwatchRow(
                    swatches: NoteColorSwatch.palette,
                    selectedId: viewModel.highlighterSwatchId,
                    usingCustom: viewModel.highlighterUsesCustomColor
                ) { swatch in
                    viewModel.selectHighlighterSwatch(swatch.id)
                }
                .padding(.horizontal, 12)

                HStack {
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { viewModel.highlighterCustomColor },
                            set: { viewModel.setHighlighterCustomColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    Text("Custom")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.highlighterUsesCustomColor
                                         ? NoteEditorTheme.accent
                                         : NoteEditorTheme.textSecondary)
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Eraser panel

struct EraserDropdownPanel: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    var body: some View {
        ChromeDropdownPanel(width: 240) {
            VStack(alignment: .leading, spacing: 10) {
                DropdownSectionTitle(text: "Mode")
                HStack(spacing: 8) {
                    eraserModeButton(.regular, label: "Regular")
                    eraserModeButton(.object, label: "Object")
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                DropdownSectionTitle(text: "Size")
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { viewModel.eraserSize },
                        set: { viewModel.setEraserSize($0) }
                    ), in: 10...34)
                    .tint(NoteEditorTheme.accent)
                    Text("\(Int(viewModel.eraserSize))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                        .frame(width: 28, alignment: .trailing)
                }
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12)

                Button {
                    viewModel.handleClearPage()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                        Text(viewModel.clearPageArmed ? "Tap again to clear" : "Clear page")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(NoteEditorTheme.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(viewModel.clearPageArmed
                                  ? NoteEditorTheme.danger.opacity(0.12)
                                  : Color.white.opacity(0.001))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(NoteEditorTheme.danger.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private func eraserModeButton(_ mode: NoteEraserMode, label: String) -> some View {
        let isActive = viewModel.eraserMode == mode
        Button {
            viewModel.setEraserMode(mode)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? NoteEditorTheme.accent : NoteEditorTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isActive ? NoteEditorTheme.accent.opacity(0.14) : Color.white.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(isActive ? NoteEditorTheme.accent.opacity(0.5)
                                              : Color.black.opacity(0.06),
                                      lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
