//
//  NoteEditorMoreMenu.swift
//  Noteworks
//
//  Three glass dropdown variants triggered from the chrome's "more"
//  button: top-level menu, background-format submenu, rotate submenu.
//  Mirrors the JSX `MoreOptionsMenu` (L4400ish) without features that
//  require shape/text/image (deferred for v1).
//

import SwiftUI

struct MoreOptionsDropdown: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    /// Closures the editor view passes in to swap the panel kind. Keeps
    /// the view-tree shallow.
    var openBackgroundPanel: () -> Void
    var openRotatePanel: () -> Void
    var dismiss: () -> Void

    var body: some View {
        ChromeDropdownPanel(width: 240) {
            VStack(spacing: 0) {
                ChromeMenuRow(
                    icon: "rectangle.grid.2x2",
                    title: "Background format",
                    detail: viewModel.currentPageBackground.label
                ) { openBackgroundPanel() }

                ChromeMenuRow(
                    icon: "arrow.clockwise",
                    title: "Rotate page",
                    detail: "\(viewModel.currentPageRotation)°"
                ) { openRotatePanel() }

                Divider().padding(.horizontal, 12).padding(.vertical, 4)

                ChromeMenuRow(
                    icon: "doc.on.doc",
                    title: "Copy page",
                    detail: "Duplicates page \(viewModel.currentPage)"
                ) {
                    viewModel.copyCurrentPage()
                    dismiss()
                }

                ChromeMenuRow(
                    icon: "trash",
                    title: "Delete page",
                    detail: viewModel.totalPages > 1
                        ? "Removes page \(viewModel.currentPage)"
                        : "Can't delete the only page",
                    tint: viewModel.totalPages > 1 ? NoteEditorTheme.danger : NoteEditorTheme.textMuted,
                    disabled: viewModel.totalPages <= 1
                ) {
                    viewModel.deleteCurrentPage()
                    dismiss()
                }
            }
        }
    }
}

struct BackgroundDropdown: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    var dismiss: () -> Void

    var body: some View {
        ChromeDropdownPanel(width: 220) {
            VStack(spacing: 0) {
                DropdownSectionTitle(text: "Background")
                    .padding(.bottom, 4)
                ForEach(NotePageBackground.allCases, id: \.self) { option in
                    let isActive = viewModel.currentPageBackground == option
                    ChromeMenuRow(
                        icon: backgroundIcon(option),
                        title: option.label,
                        trailing: isActive
                            ? AnyView(Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NoteEditorTheme.accent))
                            : nil,
                        tint: isActive ? NoteEditorTheme.accent : NoteEditorTheme.textPrimary
                    ) {
                        viewModel.setBackground(option)
                        dismiss()
                    }
                }
            }
        }
    }

    private func backgroundIcon(_ option: NotePageBackground) -> String {
        switch option {
        case .blank: return "rectangle"
        case .dots: return "circle.grid.3x3"
        case .singleColumn: return "rectangle.split.3x1"
        }
    }
}

struct RotateDropdown: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    var dismiss: () -> Void

    private let rotations = [0, 90, 180, 270]

    var body: some View {
        ChromeDropdownPanel(width: 200) {
            VStack(spacing: 0) {
                DropdownSectionTitle(text: "Rotate page")
                    .padding(.bottom, 4)
                ForEach(rotations, id: \.self) { angle in
                    let isActive = viewModel.currentPageRotation == angle
                    ChromeMenuRow(
                        icon: angle == 0 ? "rectangle" : "arrow.clockwise",
                        title: "\(angle)°",
                        trailing: isActive
                            ? AnyView(Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NoteEditorTheme.accent))
                            : nil,
                        tint: isActive ? NoteEditorTheme.accent : NoteEditorTheme.textPrimary
                    ) {
                        viewModel.rotateCurrentPage(to: angle)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Page footer (prev / page-x-of-y / next + add)

struct NotePageFooter: View {
    @ObservedObject var viewModel: NoteEditorViewModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPage <= 1)
            .opacity(viewModel.currentPage <= 1 ? 0.4 : 1)

            Text("Page \(viewModel.currentPage) of \(viewModel.totalPages)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .padding(.horizontal, 8)

            Button {
                viewModel.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 18).padding(.horizontal, 4)

            Button {
                viewModel.addPage()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Page")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(NoteEditorTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(NoteEditorTheme.chromeFill)
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
    }
}
