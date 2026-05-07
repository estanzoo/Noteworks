//
//  BubbleEditorDialog.swift
//  Noteworks
//
//  Mirrors `BubbleEditorDialog` (others/noteworks-library(2).jsx L1196–L1336).
//  Dimmed glass overlay with a 28pt-radius popover surface that hosts a
//  Create/Rename bubble form: title, subtitle, name input, and
//  Cancel + Create/Save action buttons.
//

import SwiftUI

enum BubbleEditorMode: Equatable {
    case create
    case rename(originalName: String)

    var title: String {
        switch self {
        case .create:  return "Create bubble"
        case .rename:  return "Rename bubble"
        }
    }

    var subtitle: String {
        switch self {
        case .create:
            return "Add a fresh thought bubble to your home screen."
        case .rename:
            return "Update the bubble name on home and in linked notes."
        }
    }

    var actionLabel: String {
        switch self {
        case .create: return "Create"
        case .rename: return "Save"
        }
    }
}

/// Result returned by the dialog's `onSubmit` callback. Returning `.failure`
/// surfaces the error string under the input without closing the dialog —
/// matching `result?.ok === false` in JSX L1268.
enum BubbleEditorResult {
    case success
    case failure(message: String)
}

struct BubbleEditorDialog: View {
    @Binding var isPresented: Bool
    let mode: BubbleEditorMode
    /// Closure that validates + commits the bubble name. Return `.failure(...)`
    /// to surface an inline error and keep the dialog open.
    let onSubmit: (_ name: String) -> BubbleEditorResult

    @State private var value: String = ""
    @State private var error: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            // Dimmed backdrop (JSX L1233): rgba(18,28,38,0.18) + blur(8px).
            Color(red: 18/255, green: 28/255, blue: 38/255)
                .opacity(0.18)
                .background(.ultraThinMaterial.opacity(0.6))
                .ignoresSafeArea()
                .onTapGesture { close() }

            card
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onAppear {
            value = initialValue
            error = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                inputFocused = true
            }
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(HomeTheme.textPrimary)

                Text(mode.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(HomeTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Bubble name", text: $value)
                    .focused($inputFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                    .onSubmit { submit() }
                    .onChange(of: value) { _, _ in
                        if !error.isEmpty { error = "" }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
                    )

                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0xC6/255, green: 0x6B/255, blue: 0x6B/255))
                        .transition(.opacity)
                }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                cancelButton
                submitButton
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 250/255, green: 252/255, blue: 254/255).opacity(0.98),
                            Color(red: 241/255, green: 246/255, blue: 250/255).opacity(0.97),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 60, x: 0, y: 24)
    }

    // MARK: - Buttons

    private var cancelButton: some View {
        Button(action: close) {
            Text("Cancel")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HomeTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.68))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(BubbleDialogPressStyle())
    }

    private var submitButton: some View {
        Button(action: submit) {
            Text(mode.actionLabel)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(HomeTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(HomeTheme.accent.opacity(0.16))
                )
        }
        .buttonStyle(BubbleDialogPressStyle())
        .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(value.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
    }

    // MARK: - Helpers

    private var initialValue: String {
        if case .rename(let name) = mode { return name }
        return ""
    }

    private func submit() {
        let result = onSubmit(value)
        switch result {
        case .success:
            close()
        case .failure(let message):
            withAnimation(.easeOut(duration: 0.15)) {
                error = message
            }
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) {
            isPresented = false
        }
    }
}

// MARK: - Press style

private struct BubbleDialogPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
