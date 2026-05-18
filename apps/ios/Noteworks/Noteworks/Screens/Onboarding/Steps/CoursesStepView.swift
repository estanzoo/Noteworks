//
//  CoursesStepView.swift
//  Noteworks
//
//  Final onboarding step. Direct port of the JSX
//  `CourseSetupInterface` (others/NoteWorks_UI 2/noteworks-library.jsx
//  L1682–L2010): "Welcome to NoteWorks — tell us what classes you are
//  taking". The codes/names confirmed here seed Home's bubble field.
//

import SwiftUI

// MARK: - Step view

struct CoursesStepView: View {
    @ObservedObject var data: OnboardingData
    /// Called with the final list of bubble labels (already deduped /
    /// trimmed) once the user taps Continue.
    let onSave: ([String]) -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    @State private var rows: [CourseDraft] = []
    @State private var displayMode: CourseDisplayMode = .code
    @State private var visible = false
    /// Skip is two-step (matches the JSX `skipConfirm` modal at
    /// noteworks-library.jsx L2015–L2085). The user has to confirm,
    /// because the consequence ("only one Untitled Bubble on Home")
    /// isn't obvious from the button label alone.
    @State private var showSkipConfirm = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Derived

    private var showsSplitPreview: Bool { horizontalSizeClass == .regular }

    /// Bubble labels from the current draft rows (matches `handleContinue`).
    private var previewBubbleLabels: [String] {
        rowsWithContent.compactMap { $0.bubbleLabel(for: displayMode) }
    }

    /// Filter rows down to those with any meaningful input so blanks
    /// at the bottom don't disable Continue. Mirrors JSX
    /// `rowsWithContent` (L1731).
    private var rowsWithContent: [CourseDraft] {
        rows.filter {
            !$0.code.trimmingCharacters(in: .whitespaces).isEmpty ||
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// A row is invalid when the user wrote *something* but is missing
    /// the field we need to produce a bubble label. Matches JSX
    /// `hasInvalidRows` (L1732).
    private var hasInvalidRows: Bool {
        rowsWithContent.contains { row in
            let name = row.name.trimmingCharacters(in: .whitespaces)
            let code = row.code.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return true }
            if !row.noCode && displayMode == .code && code.isEmpty { return true }
            return false
        }
    }

    private var canContinue: Bool {
        !rowsWithContent.isEmpty && !hasInvalidRows
    }

    private var firstName: String {
        let raw = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        return raw.split(separator: " ").first.map(String.init) ?? raw
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent

            if showSkipConfirm {
                skipConfirmOverlay
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showSkipConfirm)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 6, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            OnboardingBackButton(action: onBack)
                            Spacer()
                        }
                        .padding(.bottom, 8)

                        if showsSplitPreview {
                            HStack(alignment: .top, spacing: 20) {
                                courseFormColumn
                                CourseHomePreviewPane(labels: previewBubbleLabels)
                                    .frame(width: 300)
                            }
                        } else {
                            courseFormColumn
                            CourseHomePreviewPane(labels: previewBubbleLabels)
                                .padding(.top, 12)
                        }

                        bottomActions
                            .padding(.top, 22)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 16)
        .onAppear {
            primeRowsIfNeeded()
            withAnimation(.easeOut(duration: 0.5)) { visible = true }
        }
    }

    @ViewBuilder
    private var courseFormColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)

            displayModeCard
                .padding(.bottom, 14)

            VStack(spacing: 12) {
                ForEach($rows) { $row in
                    CourseRowCard(
                        row: $row,
                        displayMode: displayMode,
                        canRemove: rows.count > 1,
                        onRemove: { removeRow(id: row.id) }
                    )
                }
            }

            if hasInvalidRows {
                Text("Add a course name for every course. If the bubble should use a course code, include the code too.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.errorColor)
                    .padding(.top, 10)
            }

            if displayMode == .name {
                Text("Course names are limited to \(CourseDraft.nameMaxChars) characters so Home bubbles stay readable.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textSecondary.opacity(0.85))
                    .padding(.top, 10)
            }

            addCourseButton
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WELCOME TO NOTEWORKS")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(OnboardingTheme.accent)

            Text(firstName.isEmpty
                 ? "Tell us what classes you are taking"
                 : "\(firstName), tell us what classes you are taking")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(OnboardingTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("We'll turn each class into a Home bubble. You can show the course code, like ECON101, or the course name, like Microeconomic Theory.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(OnboardingTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bubble naming")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                Text("Choose once for all courses. Courses without a code will use the course name.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                CourseDisplayToggle(
                    label: "Use course code",
                    active: displayMode == .code,
                    action: { displayMode = .code }
                )
                CourseDisplayToggle(
                    label: "Use course name",
                    active: displayMode == .name,
                    action: { displayMode = .name }
                )
            }
            .padding(4)
            .background(Color.white.opacity(0.46))
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
        }
    }

    private var addCourseButton: some View {
        Button(action: appendRow) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                Text("Add Course")
                    .font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(OnboardingTheme.accent)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OnboardingTheme.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(OnboardingTheme.accent.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button(action: { showSkipConfirm = true }) {
                Text("Skip for now")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 18)
                    .background(Color.white.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: handleContinue) {
                Text("Continue")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 22)
                    .background(OnboardingTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: OnboardingTheme.accent.opacity(canContinue ? 0.3 : 0), radius: 12, y: 4)
                    .opacity(canContinue ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
        }
    }

    // MARK: - Skip confirmation overlay

    /// Direct port of the JSX `skipConfirm` modal (L2015–L2085):
    /// centered glass card, backdrop tap dismisses, "Go back" /
    /// "Skip anyway" with the destructive button in JSX's red.
    private var skipConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { showSkipConfirm = false }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Skip course setup?")
                        .font(.system(size: 21, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(OnboardingTheme.textPrimary)

                    Text("Your Home will start with only one Untitled Bubble. You can add or edit courses later in Settings, About You, Edit Course List.")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button(action: { showSkipConfirm = false }) {
                        Text("Go back")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(OnboardingTheme.textSecondary)
                            .padding(.vertical, 11)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.58))
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showSkipConfirm = false
                        onSkip()
                    }) {
                        Text("Skip anyway")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color(red: 180/255, green: 91/255, blue: 91/255))
                            .padding(.vertical, 11)
                            .padding(.horizontal, 16)
                            .background(Color(red: 180/255, green: 91/255, blue: 91/255).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .overlay {
                                RoundedRectangle(cornerRadius: 15)
                                    .strokeBorder(Color(red: 180/255, green: 91/255, blue: 91/255).opacity(0.18), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
            .frame(maxWidth: 420)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.98).opacity(0.98), Color(white: 0.95).opacity(0.97)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - State helpers

    /// Hydrate rows the first time the step appears. Interests from the
    /// prior step are **not** copied here — they are not course codes.
    /// `submit-onboarding` already sent `course_codes` derived from
    /// interests for the profile wire format; this screen is only for
    /// real classes → Home bubbles. Start with one empty row (same as
    /// the JSX fallback when there is nothing to pre-seed).
    private func primeRowsIfNeeded() {
        guard rows.isEmpty else { return }
        rows = [CourseDraft.empty()]
    }

    private func appendRow() {
        rows.append(CourseDraft.empty())
    }

    private func removeRow(id: UUID) {
        guard rows.count > 1 else { return }
        rows.removeAll { $0.id == id }
    }

    private func handleContinue() {
        // Resolve every row to a bubble label using the same code/name
        // rules as the JSX `getCourseBubbleLabel`. Dedupe is handled
        // by `NotesStore.replaceBubbleNames` so we forward in row
        // order here.
        let labels: [String] = rowsWithContent.compactMap { row in
            row.bubbleLabel(for: displayMode)
        }
        onSave(labels)
    }
}

// MARK: - Home preview (course bubbles — NoteWorks_UI course-setup column)

private struct CourseHomePreviewPane: View {
    let labels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOME PREVIEW")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(OnboardingTheme.textSecondary.opacity(0.85))

            Text("Your course bubbles")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(OnboardingTheme.textPrimary)

            Text("These names become the bubbles on Home.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)

                if labels.isEmpty {
                    Text("Add at least one course on the left to preview your bubbles.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OnboardingTheme.textSecondary.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(20)
                } else if labels.count == 1, let label = labels.first {
                    let size = Self.bubbleDiameter(for: label)
                    BubbleView(
                        course: CourseBubble(
                            name: label,
                            noteCount: 0,
                            size: size,
                            offsetX: 0,
                            offsetY: 0
                        ),
                        showsNoteMeta: false
                    )
                    .modifier(PreviewBubbleFloatModifier(delay: 0))
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    FlowLayout(spacing: 14) {
                        ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                            let size = Self.bubbleDiameter(for: label)
                            BubbleView(
                                course: CourseBubble(
                                    name: label,
                                    noteCount: 0,
                                    size: size,
                                    offsetX: 0,
                                    offsetY: 0
                                ),
                                showsNoteMeta: false
                            )
                            .modifier(PreviewBubbleFloatModifier(delay: Double(index) * 0.24))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(18)
                }
            }
            .frame(minHeight: 200)
        }
        .padding(16)
        .background(Color.white.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
        }
    }

    private static func bubbleDiameter(for label: String) -> CGFloat {
        let base: CGFloat = 88
        let byLength = CGFloat(label.count) * 3.2
        return min(132, max(base, base + byLength - 18))
    }
}

/// Matches `NoteWorks_UI 3` / `noteworks-library.jsx` `bubbleFloat`:
/// `0%,100% { translateY(0) scale(1) }` / `50% { translateY(-8px) scale(1.018) }`
/// with `3.8s ease-in-out` and `index * 0.24s` delay per bubble.
private struct PreviewBubbleFloatModifier: ViewModifier {
    let delay: Double
    @State private var floating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(floating ? 1.018 : 1.0)
            .offset(y: floating ? -8 : 0)
            .task {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                    floating = true
                }
            }
    }
}

// MARK: - Course Draft model

struct CourseDraft: Identifiable, Equatable {
    static let nameMaxChars = 32

    let id: UUID
    var code: String
    var name: String
    var noCode: Bool

    init(id: UUID = UUID(), code: String, name: String, noCode: Bool) {
        self.id = id
        self.code = code
        self.name = name
        self.noCode = noCode
    }

    static func empty() -> CourseDraft {
        CourseDraft(code: "", name: "", noCode: false)
    }

    /// JSX `getCourseBubbleLabel(course, displayMode)` parity:
    /// - `noCode` or `displayMode == .name`: prefer the name, fall back to the code.
    /// - Otherwise: prefer the code, fall back to the name.
    /// Returns nil if both fields are empty so the caller can filter
    /// the row out cleanly.
    func bubbleLabel(for displayMode: CourseDisplayMode) -> String? {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferName = noCode || displayMode == .name
        if preferName {
            if !trimmedName.isEmpty { return trimmedName }
            if !trimmedCode.isEmpty { return trimmedCode }
            return nil
        } else {
            if !trimmedCode.isEmpty { return trimmedCode }
            if !trimmedName.isEmpty { return trimmedName }
            return nil
        }
    }
}

enum CourseDisplayMode: String, Equatable {
    case code
    case name
}

// MARK: - Row Card

private struct CourseRowCard: View {
    @Binding var row: CourseDraft
    let displayMode: CourseDisplayMode
    let canRemove: Bool
    let onRemove: () -> Void

    private var codeRequired: Bool {
        !row.noCode && displayMode == .code
    }

    private var previewLabel: String {
        row.bubbleLabel(for: displayMode) ?? "Untitled Bubble"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 12) {
                    CourseFieldStack(
                        label: codeRequired ? "Course code *" : "Course code",
                        placeholder: "ECON101",
                        text: $row.code,
                        autoCaps: .characters,
                        disabled: row.noCode
                    )
                    CourseFieldStack(
                        label: "Course name *",
                        placeholder: "Microeconomic Theory",
                        text: $row.name,
                        autoCaps: .words,
                        disabled: false,
                        maxLength: CourseDraft.nameMaxChars
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(OnboardingTheme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Toggle(isOn: $row.noCode) {
                    Text("No course code")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(OnboardingTheme.textSecondary)
                }
                .toggleStyle(NoteworksCheckboxStyle())

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text("PREVIEW")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(OnboardingTheme.textSecondary.opacity(0.7))
                    Text(previewLabel)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(OnboardingTheme.textPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.5))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
                        }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
        }
    }
}

// MARK: - Helpers

/// One label-over-textfield column, used twice in `CourseRowCard`.
private struct CourseFieldStack: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let autoCaps: TextInputAutocapitalization
    var disabled: Bool = false
    var maxLength: Int? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(OnboardingTheme.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textPrimary)
                .textInputAutocapitalization(autoCaps)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(disabled ? Color.black.opacity(0.03) : OnboardingTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            focused && !disabled
                                ? OnboardingTheme.accent.opacity(0.55)
                                : OnboardingTheme.glassBorder,
                            lineWidth: 1.5
                        )
                }
                .focused($focused)
                .disabled(disabled)
                .onChange(of: text) { _, newValue in
                    if let maxLength, newValue.count > maxLength {
                        text = String(newValue.prefix(maxLength))
                    }
                }
        }
        .opacity(disabled ? 0.5 : 1)
    }
}

private struct CourseDisplayToggle: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(active ? OnboardingTheme.accent : OnboardingTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(active ? OnboardingTheme.accent.opacity(0.13) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct NoteworksCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            configuration.isOn ? OnboardingTheme.accent.opacity(0.6) : Color.black.opacity(0.15),
                            lineWidth: 1.5
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(configuration.isOn ? OnboardingTheme.accent.opacity(0.15) : Color.white.opacity(0.5))
                        )
                        .frame(width: 18, height: 18)

                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(OnboardingTheme.accent)
                    }
                }
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        OnboardingBackground()
            .ignoresSafeArea()
        CoursesStepView(
            data: {
                let d = OnboardingData()
                d.name = "Hao Guan Cheng"
                d.interests = ["CHEM-204", "BIO-220"]
                d.customInterests = ["MATH-202"]
                return d
            }(),
            onSave: { _ in },
            onSkip: {},
            onBack: {}
        )
    }
}
