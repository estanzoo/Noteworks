//
//  BubbleEditorDialog.swift
//  Noteworks
//
//  Mirrors `BubbleEditorDialog` in NoteWorks_UI 5 (noteworks-library.jsx L1779).
//  Create mode: course code/name form with display toggle + preview.
//  Rename mode: simple name field.
//

import SwiftUI

enum BubbleEditorMode: Equatable {
    case create
    case rename(originalName: String)

    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .create: return "Create bubble"
        case .rename: return "Rename bubble"
        }
    }

    var subtitle: String {
        switch self {
        case .create:
            return "Add a fresh space to your home screen."
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

enum BubbleEditorResult {
    case success
    case failure(message: String)
}

struct BubbleEditorDialog: View {
    @Binding var isPresented: Bool
    let mode: BubbleEditorMode
    let defaultDisplayMode: CourseDisplayMode
    let onSubmit: (_ name: String, _ courseDraft: CourseDraft?, _ displayMode: CourseDisplayMode?) -> BubbleEditorResult

    @AppStorage("courseBubbleDisplayMode") private var storedDisplayModeRaw = CourseDisplayMode.code.rawValue

    @State private var renameValue = ""
    @State private var courseDraft = CourseDraft.empty()
    @State private var displayMode: CourseDisplayMode = .code
    @State private var error = ""
    @FocusState private var renameFocused: Bool

    private var codeRequired: Bool {
        mode.isCreate && !courseDraft.noCode && displayMode == .code
    }

    private var previewLabel: String {
        courseDraft.bubbleLabel(for: displayMode) ?? NotesStore.initialGuestBubbleName
    }

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 28/255, blue: 38/255)
                .opacity(0.18)
                .background(.ultraThinMaterial.opacity(0.6))
                .ignoresSafeArea()
                .onTapGesture { close() }

            card
                .frame(
                    width: min(mode.isCreate ? 560 : 420, UIScreen.main.bounds.width - 32),
                    height: mode.isCreate ? min(520, UIScreen.main.bounds.height - 48) : nil
                )
                .frame(maxHeight: UIScreen.main.bounds.height - 48)
                .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .onAppear { resetForm() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if mode.isCreate {
                createForm
            } else {
                renameForm
            }
            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC6/255, green: 0x6B/255, blue: 0x6B/255))
            }
            footer
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
        .shadow(color: .black.opacity(0.14), radius: 64, x: 0, y: 24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(HomeTheme.textPrimary)
            Text(mode.subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(HomeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var renameForm: some View {
        TextField("Bubble name", text: $renameValue)
            .focused($renameFocused)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit { submit() }
            .onChange(of: renameValue) { _, _ in
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
    }

    private var createForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                displayModeCard
                courseFieldsCard
            }
        }
        .scrollIndicators(.hidden)
    }

    private var displayModeCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bubble naming")
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(HomeTheme.textPrimary)
                Text("Default follows your onboarding choice.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(HomeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            HStack(spacing: 7) {
                displayToggle("Use course code", active: displayMode == .code) {
                    displayMode = .code
                    storedDisplayModeRaw = CourseDisplayMode.code.rawValue
                }
                displayToggle("Use course name", active: displayMode == .name) {
                    displayMode = .name
                    storedDisplayModeRaw = CourseDisplayMode.name.rawValue
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .overlay(Capsule().strokeBorder(HomeTheme.glassBorder, lineWidth: 1))
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.34))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(HomeTheme.glassBorder, lineWidth: 1))
        )
    }

    private var courseFieldsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                courseField(
                    label: codeRequired ? "Course Code *" : "Course Code",
                    text: $courseDraft.code,
                    placeholder: "ECON101",
                    caps: .characters,
                    disabled: courseDraft.noCode
                )
                .frame(maxWidth: .infinity)
                courseField(
                    label: "Course Name *",
                    text: $courseDraft.name,
                    placeholder: "Microeconomic Theory",
                    caps: .words,
                    disabled: false,
                    maxLength: CourseDraft.nameMaxChars
                )
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                Toggle(isOn: $courseDraft.noCode) {
                    Text("No course code")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(HomeTheme.textSecondary)
                }
                .toggleStyle(BubbleCheckboxToggleStyle())
                .onChange(of: courseDraft.noCode) { _, isOn in
                    if isOn { courseDraft.code = "" }
                    if !error.isEmpty { error = "" }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text("PREVIEW")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.08 * 11)
                        .foregroundStyle(HomeTheme.textMuted)
                    Text(previewLabel)
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(HomeTheme.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.62))
                                .overlay(Capsule().strokeBorder(HomeTheme.glassBorder, lineWidth: 1))
                        )
                }
            }

            Text("Course names are limited to \(CourseDraft.nameMaxChars) characters so Home bubbles stay readable.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(HomeTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.46))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HomeTheme.glassBorder, lineWidth: 1))
        )
    }

    private func courseField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        caps: TextInputAutocapitalization,
        disabled: Bool,
        maxLength: Int? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.08 * 11)
                .foregroundStyle(HomeTheme.textMuted)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(caps)
                .autocorrectionDisabled(false)
                .disabled(disabled)
                .onChange(of: text.wrappedValue) { _, newValue in
                    if let maxLength, newValue.count > maxLength {
                        text.wrappedValue = String(newValue.prefix(maxLength))
                    }
                    if !error.isEmpty { error = "" }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HomeTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(disabled ? Color.black.opacity(0.03) : Color.white.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
                )
        }
        .opacity(disabled ? 0.5 : 1)
    }

    private func displayToggle(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .heavy))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(active ? HomeTheme.accent : HomeTheme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(active ? HomeTheme.accent.opacity(0.13) : Color.white.opacity(0.44))
                        .overlay(Capsule().strokeBorder(active ? HomeTheme.accent.opacity(0.34) : Color.white.opacity(0.55), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("Cancel", action: close)
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
                .buttonStyle(BubbleDialogPressStyle())

            Button(mode.actionLabel, action: submit)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(HomeTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(HomeTheme.accent.opacity(0.16))
                )
                .buttonStyle(BubbleDialogPressStyle())
        }
    }

    private func resetForm() {
        error = ""
        switch mode {
        case .create:
            courseDraft = CourseDraft.empty()
            if let stored = CourseDisplayMode(rawValue: storedDisplayModeRaw) {
                displayMode = stored
            } else {
                displayMode = defaultDisplayMode
            }
        case .rename(let original):
            renameValue = original
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                renameFocused = true
            }
        }
    }

    private func submit() {
        let result: BubbleEditorResult
        switch mode {
        case .create:
            result = onSubmit("", courseDraft, displayMode)
        case .rename:
            result = onSubmit(renameValue, nil, nil)
        }

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

private struct BubbleCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            configuration.isOn ? HomeTheme.accent.opacity(0.6) : Color.black.opacity(0.15),
                            lineWidth: 1.5
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(configuration.isOn ? HomeTheme.accent.opacity(0.15) : Color.white.opacity(0.5))
                        )
                        .frame(width: 15, height: 15)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(HomeTheme.accent)
                    }
                }
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BubbleDialogPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
