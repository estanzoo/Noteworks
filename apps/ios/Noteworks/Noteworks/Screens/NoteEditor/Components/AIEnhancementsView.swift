//
//  AIEnhancementsView.swift
//  Noteworks
//
//  Header-row "AI Enhancements" pill + the dropdown the pill opens.
//  Mirrors the JSX `AIEnhancementsAction` (others/NoteWorks_UI L2533) and
//  the popover content at L5118 — Gap Detection / Smart Organization rows,
//  Confirm + Progress + Done states, busy notice.
//
//  v1 is UI-only: the underlying jobs in `NoteEditorViewModel` are local
//  fake timers. The chrome plugs into the same job state shape so a real
//  backend can drop in later without touching this file.
//

import SwiftUI

// MARK: - Pill

/// Header-row trigger button. Renders one of three visual states based on
/// the running / completed status of the two jobs, matching the JSX.
struct AIEnhancementsPill: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.smartJob.isRunning {
            progressPill(label: "Smart Org", progress: viewModel.smartJob.progress)
        } else if viewModel.gapJob.isRunning {
            progressPill(label: "Gap Detection", progress: viewModel.gapJob.progress)
        } else if viewModel.smartJob.isCompleted || viewModel.gapJob.isCompleted {
            completedPill
        } else {
            idlePill
        }
    }

    // MARK: Pill variants

    private var idlePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
            Text("AI Enhancements")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(NoteEditorTheme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(NoteEditorTheme.accent.opacity(0.12)))
        .overlay(Capsule().strokeBorder(NoteEditorTheme.accent.opacity(0.35), lineWidth: 1))
    }

    private func progressPill(label: String, progress: Double) -> some View {
        let clamped = max(0.06, min(1, progress))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NoteEditorTheme.accent.opacity(0.16))
                    .frame(width: proxy.size.width * clamped)
                    .animation(.easeInOut(duration: 0.18), value: clamped)
                HStack(spacing: 6) {
                    Text("\(Int(clamped * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.accent)
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NoteEditorTheme.textPrimary.opacity(0.82))
                }
                .padding(.horizontal, 10)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(
                Capsule().fill(Color.white.opacity(0.7))
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .overlay(Capsule().strokeBorder(NoteEditorTheme.accent.opacity(0.18), lineWidth: 1))
        }
        .frame(width: 148, height: 26)
    }

    private var completedPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text(viewModel.smartJob.isCompleted ? "Organized!" : "Gap Ready")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(NoteEditorTheme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.85)))
        .overlay(Capsule().strokeBorder(NoteEditorTheme.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Dropdown

/// Glass dropdown the pill opens. Hosts the `root` / `taskStatus` /
/// `smartConfirm` / `smartOrganization` sub-panels.
struct AIEnhancementsDropdown: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    @ObservedObject var creditsStore: CreditsStore
    var dismiss: () -> Void

    var body: some View {
        ChromeDropdownPanel(width: 300) {
            VStack(alignment: .leading, spacing: 10) {
                Text("AI Enhancements")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.1 * 11)
                    .foregroundStyle(NoteEditorTheme.textMuted)
                    .padding(.horizontal, 14)

                if !viewModel.aiEnhancementNotice.isEmpty {
                    Text(viewModel.aiEnhancementNotice)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0xA6/255, green: 0x6E/255, blue: 0x2B/255))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0xFF/255, green: 0xF6/255, blue: 0xE8/255).opacity(0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(red: 0xC7/255, green: 0x85/255, blue: 0x2F/255).opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal, 12)
                }

                Group {
                    switch viewModel.aiEnhancementPanel {
                    case .root: rootPanel
                    case .taskStatus: taskStatusPanel
                    case .smartConfirm: smartConfirmPanel
                    case .smartOrganization: smartOrgPanel
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: Root — both feature buttons stacked

    private var rootPanel: some View {
        VStack(spacing: 10) {
            AIEnhancementFeatureCard(
                title: "Gap Detection",
                subtitle: "Compare this note with peer notes and class materials.",
                accent: viewModel.gapJob.isCompleted ? .ready : .neutral
            ) { viewModel.showGapDetectionConfigurator() }

            AIEnhancementFeatureCard(
                title: "Smart Organization",
                subtitle: "Tidy sections and bring related ideas closer together.",
                accent: viewModel.smartJob.isCompleted ? .ready : .neutral
            ) { viewModel.requestSmartOrganization() }
        }
    }

    // MARK: Task status — appears when at least one job is mid-run

    private var taskStatusPanel: some View {
        VStack(spacing: 8) {
            AIEnhancementStatusRow(
                title: "Gap Detection",
                job: viewModel.gapJob
            ) {
                if viewModel.gapJob.isRunning {
                    viewModel.selectAIEnhancementPanel(.taskStatus)
                } else if viewModel.gapJob.isCompleted {
                    viewModel.acknowledgeGapJobResult()
                    dismiss()
                } else {
                    viewModel.startGapDetection()
                }
            }

            AIEnhancementStatusRow(
                title: "Smart Organization",
                job: viewModel.smartJob
            ) {
                if viewModel.smartJob.isRunning || viewModel.smartJob.isCompleted {
                    viewModel.selectAIEnhancementPanel(.smartOrganization)
                } else {
                    viewModel.requestSmartOrganization()
                }
            }
        }
    }

    // MARK: Smart Organization confirmation

    private var smartConfirmPanel: some View {
        let cost = viewModel.estimatedSmartOrganizationCredits
        let balance = creditsStore.balance
        let canConfirm = cost <= balance

        return VStack(alignment: .leading, spacing: 12) {
            Text("Smart Organization")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
            Text("Organize this note into cleaner sections and improve its structure.")
                .font(.system(size: 12))
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Estimated cost")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                Spacer()
                Text("\(cost) Credits")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.accent)
            }

            if !canConfirm {
                Text("You only have \(balance) credits available right now.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC1/255, green: 0x60/255, blue: 0x60/255))
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.selectAIEnhancementPanel(.root)
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.78))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.confirmSmartOrganization()
                } label: {
                    Text("Confirm")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canConfirm ? .white : NoteEditorTheme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    canConfirm
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [NoteEditorTheme.accent, Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        : AnyShapeStyle(Color.black.opacity(0.06))
                                )
                        )
                }
                .disabled(!canConfirm)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Smart Organization in-progress / completed

    private var smartOrgPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Organization")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                    Text(viewModel.smartJob.isCompleted
                         ? "Your note structure has been tidied up."
                         : "Reorganizing sections and bringing related ideas closer together.")
                        .font(.system(size: 12))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button {
                    if viewModel.smartJob.isCompleted {
                        viewModel.selectAIEnhancementPanel(.root)
                    } else {
                        viewModel.selectAIEnhancementPanel(.taskStatus)
                    }
                } label: {
                    Image(systemName: viewModel.smartJob.isCompleted ? "chevron.left" : "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.92)))
                        .overlay(Circle().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            AIEnhancementProgressBar(progress: viewModel.smartJob.progress, isCompleted: viewModel.smartJob.isCompleted)

            if viewModel.smartJob.isCompleted {
                Button {
                    viewModel.dismissSmartOrganization()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [NoteEditorTheme.accent, Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Feature card (root panel)

private enum AIFeatureAccent { case neutral, ready }

private struct AIEnhancementFeatureCard: View {
    let title: String
    let subtitle: String
    let accent: AIFeatureAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                    if accent == .ready {
                        Text("READY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.08 * 9)
                            .foregroundStyle(NoteEditorTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(NoteEditorTheme.accent.opacity(0.14))
                            )
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status row (taskStatus panel)

private struct AIEnhancementStatusRow: View {
    let title: String
    let job: AIEnhancementJob
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                Spacer()
                Text(rightLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var rightLabel: String {
        switch job {
        case .running(let progress): return "\(Int(progress * 100))%"
        case .completed: return "Done"
        case .idle: return "Open"
        }
    }
}

// MARK: - Progress bar (smartOrg panel)

private struct AIEnhancementProgressBar: View {
    let progress: Double
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.05))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [NoteEditorTheme.accent, Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * max(0.06, min(1, isCompleted ? 1 : progress)))
                        .animation(.easeInOut(duration: 0.18), value: progress)
                }
            }
            .frame(height: 9)

            HStack {
                Text(isCompleted ? "Organized!" : "Organizing...")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isCompleted ? NoteEditorTheme.accent : NoteEditorTheme.textPrimary)
                Spacer()
                Text(isCompleted ? "Done" : "\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1)
        )
    }
}

// MARK: - Gap Detection Popup

struct GapDetectionPopup: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    @ObservedObject var creditsStore: CreditsStore
    let currentNote: Note?
    let notes: [Note]
    let accessToken: String
    let onClose: () -> Void

    private var selectedSources: Int { viewModel.selectedGapSourceIds.count }
    private var materialCount: Int { viewModel.gapClassMaterialNames.count }
    private var creditBalance: Int { creditsStore.balance }
    private var estimatedCredits: Int { viewModel.estimatedGapDetectionCredits(currentNote: currentNote) }
    private var yourNotesPrice: Int {
        let pages = (viewModel.gapSelectedOwnNoteId.flatMap { id in notes.first { $0.id == id } }
            ?? currentNote)?.pageSettings.count ?? 1
        return max(4, pages / 4 + 4)
    }
    private var otherNotesPrice: Int { selectedSources * 6 }
    private var classMaterialsPrice: Int { materialCount * 3 }
    private var canConfirm: Bool { estimatedCredits <= creditBalance }

    var body: some View {
        ZStack {
            Color(red: 16/255, green: 24/255, blue: 36/255)
                .opacity(0.18)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                header
                Divider().overlay(NoteEditorTheme.chromeBorder.opacity(0.7))
                content
            }
            .frame(maxWidth: 880)
            .frame(maxHeight: 860)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.84),
                                Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.66),
                                Color(red: 233/255, green: 241/255, blue: 247/255).opacity(0.56)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 70, x: 0, y: 28)
            .padding(.horizontal, 16)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gap Detection")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.1 * 11)
                    .foregroundStyle(NoteEditorTheme.textMuted)
                Text(headerTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if viewModel.gapDetectionMode == .running {
                Button("Minimize") {
                    viewModel.minimizeGapDetectionPopup()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.84)))
                .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                .buttonStyle(.plain)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textMuted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.gapDetectionMode {
        case .config:
            ScrollView {
                configContent
                    .padding(24)
            }
        case .running, .completed:
            resultContent
                .padding(24)
        }
    }

    private var configContent: some View {
        VStack(spacing: 18) {
            switch viewModel.gapDetectionConfigPanel {
            case .root:
                rootConfig
            case .communityBrowser:
                communityBrowser
            case .preview:
                previewPanel
            }
        }
    }

    private var rootConfig: some View {
        VStack(spacing: 18) {
            yourNotesSection
            othersNotesSection
            classMaterialsSection
            confirmSection
        }
    }

    private var yourNotesSection: some View {
        sectionCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionEyebrow("1. Your Notes")
                    Text("Starts with the note you launched from, but you can switch sources before the AI begins.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
                Spacer()
                Button(viewModel.gapOwnNotePickerOpen ? "Hide notes" : "Choose note") {
                    viewModel.gapOwnNotePickerOpen.toggle()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(Color.white.opacity(0.84)))
                .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                .buttonStyle(.plain)
            }

            gapNoteSourceCard(selectedOwnNote ?? currentNote, active: true)

            if viewModel.gapOwnNotePickerOpen {
                VStack(spacing: 10) {
                    ForEach(noteOptions) { note in
                        gapNoteSourceCard(
                            note,
                            active: note.id == (selectedOwnNote?.id ?? currentNote?.id),
                            action: {
                                viewModel.gapSelectedOwnNoteId = note.id
                                viewModel.gapOwnNotePickerOpen = false
                            }
                        )
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private var othersNotesSection: some View {
        sectionCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionEyebrow("2. Other's Notes")
                    Text("Recommended from community posts with similar school, course code, and study timing signals.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
                Spacer()
                Button("Browse in Community posts") {
                    viewModel.gapDetectionConfigPanel = .communityBrowser
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(Color.white.opacity(0.84)))
                .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                ForEach(recommendedNotes.prefix(4)) { note in
                    gapCommunityNoteCard(note)
                }
            }

            if !viewModel.selectedGapSourceIds.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(recommendedNotes.filter { viewModel.selectedGapSourceIds.contains($0.id) }) { note in
                        Text(note.title.isEmpty ? "Untitled Note" : note.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NoteEditorTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(NoteEditorTheme.accent.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(NoteEditorTheme.accent.opacity(0.18), lineWidth: 1))
                    }
                }
            }
        }
    }

    private var classMaterialsSection: some View {
        sectionCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionEyebrow("3. Class Materials (Optional)")
                    Text("Upload up to five files to give the AI more context before it summarizes the gaps.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
                Spacer()
                Button("Upload files") {
                    viewModel.toggleGapClassMaterialPlaceholder()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(Color.white.opacity(0.84)))
                .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                .buttonStyle(.plain)
            }

            if viewModel.gapClassMaterialNames.isEmpty {
                Text("No class materials attached yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.36)))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(red: 160/255, green: 177/255, blue: 194/255).opacity(0.76), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.gapClassMaterialNames, id: \.self) { name in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(NoteEditorTheme.textPrimary)
                                    .lineLimit(1)
                                Text("Class material")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(NoteEditorTheme.textSecondary)
                            }
                            Spacer()
                            Button {
                                viewModel.gapClassMaterialNames.removeAll { $0 == name }
                                viewModel.gapMaterialNotice = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NoteEditorTheme.textMuted)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.black.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.72)))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1))
                    }
                }
            }

            if !viewModel.gapMaterialNotice.isEmpty {
                Text(viewModel.gapMaterialNotice)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC7/255, green: 0x85/255, blue: 0x2F/255))
            }
        }
    }

    private var confirmSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sectionEyebrow("4. Confirm")
                Text("Price is based on the selected peer notes, the number of class materials, and the length of your note. Billing happens in credits.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .lineSpacing(4)
            }

            HStack(spacing: 10) {
                outputModeButton(.newNote)
                outputModeButton(.appendPages)
            }

            VStack(spacing: 10) {
                priceRow("Your note", value: yourNotesPrice)
                priceRow("Other's notes", value: otherNotesPrice)
                priceRow("Class materials", value: classMaterialsPrice)
                Divider().overlay(Color.black.opacity(0.06))
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(NoteEditorTheme.textPrimary)
                        Text("\(selectedSourceTitle) · \(selectedSources) peer note\(selectedSources == 1 ? "" : "s") · \(materialCount) class material\(materialCount == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NoteEditorTheme.textSecondary)
                    }
                    Spacer()
                    Text("\(estimatedCredits) Credits")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(NoteEditorTheme.accent)
                }
            }

            if !canConfirm {
                Text("You only have \(creditBalance) credits available right now.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC1/255, green: 0x60/255, blue: 0x60/255))
            }

            if let error = viewModel.gapDetectionError {
                Text(error)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC1/255, green: 0x60/255, blue: 0x60/255))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Available now: \(creditBalance) Credits")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                Spacer()
                Button("Confirm") {
                    Task {
                        await viewModel.confirmGapDetectionRun(accessToken: accessToken)
                    }
                }
                .disabled(!canConfirm)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(canConfirm ? .white : NoteEditorTheme.textMuted)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canConfirm
                              ? AnyShapeStyle(LinearGradient(colors: [NoteEditorTheme.accent, Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.black.opacity(0.06)))
                )
                .shadow(color: canConfirm ? NoteEditorTheme.accent.opacity(0.24) : .clear, radius: 12, y: 4)
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [NoteEditorTheme.accent.opacity(0.12), Color.white.opacity(0.58)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(NoteEditorTheme.accent.opacity(0.18), lineWidth: 1))
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Choose sources", subtitle: "Compare your note with related community posts and optional class materials.")
            currentNoteCard
            Button {
                viewModel.gapDetectionConfigPanel = .communityBrowser
            } label: {
                HStack {
                    Text("Browse Community posts")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NoteEditorTheme.accent)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                ForEach(recommendedNotes.prefix(3)) { note in
                    sourceNoteRow(note)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.56)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1))
    }

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Output", subtitle: "Choose where the AI gap map should land.")
            VStack(spacing: 10) {
                ForEach(GapDetectionOutputMode.allCases) { mode in
                    optionRow(
                        title: mode.label,
                        subtitle: mode == .newNote ? "Create a separate AI summary note." : "Append result pages to this note.",
                        selected: viewModel.gapOutputMode == mode
                    ) {
                        viewModel.gapOutputMode = mode
                    }
                }
            }

            Divider().overlay(NoteEditorTheme.chromeBorder)

            sectionHeader("Class materials", subtitle: "Attach syllabus, slides, or readings for extra context.")
            ForEach(viewModel.gapClassMaterialNames, id: \.self) { name in
                HStack {
                    Image(systemName: "doc")
                    Text(name).lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.gapClassMaterialNames.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.72)))
            }
            Button {
                let next = "Class material \(viewModel.gapClassMaterialNames.count + 1).pdf"
                viewModel.gapClassMaterialNames.append(next)
            } label: {
                Label("Upload materials", systemImage: "tray.and.arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.86)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.56)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1))
    }

    private var communityBrowser: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                circleBackButton {
                    viewModel.gapDetectionConfigPanel = .root
                }
                VStack(alignment: .leading, spacing: 6) {
                    sectionEyebrow("Browse in Community posts")
                    Text("Filter by school, course code, and time before choosing a peer note to compare.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
            }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    filterBox(title: "School", value: "All schools")
                    filterBox(title: "Course code", value: selectedOwnNote?.subject ?? currentNote?.subject ?? "e.g. CHEM-204")
                    filterBox(title: "Time", value: "Matching current note")
                }
            }

            if recommendedNotes.isEmpty {
                VStack(spacing: 8) {
                    Text("No posts match these filters.")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                    Text("Try widening school or time, or leave course code empty.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.42)))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color(red: 160/255, green: 177/255, blue: 194/255).opacity(0.72), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
            } else {
                VStack(spacing: 10) {
                    ForEach(recommendedNotes) { note in
                        gapCommunityNoteCard(note, compact: true)
                    }
                }
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 10) {
                circleBackButton {
                    viewModel.gapDetectionConfigPanel = .root
                }
                VStack(alignment: .leading, spacing: 6) {
                    sectionEyebrow("Other's Notes Preview")
                    Text("Review the note first, then decide whether to include it in this Gap Detection run.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
            }

            if let note = previewNote ?? recommendedNotes.first {
                sourcePreviewCard(note)
            }
        }
    }

    private var resultContent: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [Color(red: 255/255, green: 253/255, blue: 241/255), Color(red: 255/255, green: 251/255, blue: 232/255)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 260, height: 330)
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color(red: 228/255, green: 229/255, blue: 220/255), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 50, y: 24)
                VStack(alignment: .leading, spacing: 16) {
                    Capsule().fill(Color.pink.opacity(0.62)).frame(height: 12)
                    Capsule().fill(Color.black.opacity(0.08)).frame(height: 10)
                    Capsule().fill(Color.black.opacity(0.08)).frame(width: 180, height: 10)
                    RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.78), lineWidth: 3).frame(height: 88)
                    Spacer()
                    Capsule().fill(NoteEditorTheme.accent.opacity(0.16)).frame(height: 10)
                    Capsule().fill(NoteEditorTheme.accent.opacity(0.12)).frame(height: 10)
                }
                .padding(28)
                .frame(width: 260, height: 330)
            }

            AIEnhancementProgressBar(progress: viewModel.gapJob.progress, isCompleted: viewModel.gapJob.isCompleted)
                .frame(maxWidth: 520)

            if viewModel.gapJob.isCompleted {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.gapOutputMode == .newNote ? "A new note is ready to open." : "New pages were attached to the current note.")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(NoteEditorTheme.textPrimary)
                        Text("Gemini compared the two PDFs and Noteworks rendered the summary as a note image.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NoteEditorTheme.textSecondary)
                    }
                    Spacer()
                    Button("Later") { onClose() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.74)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                        .buttonStyle(.plain)
                    Button(viewModel.gapOutputMode == .newNote ? "Open generated note" : "Jump to attached page") {
                        viewModel.acknowledgeGapJobResult()
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 14).fill(NoteEditorTheme.accent))
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.54)))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1))
            }
        }
    }

    private var headerTitle: String {
        switch viewModel.gapDetectionMode {
        case .config: return "Choose sources for the scan"
        case .running: return "Analyzing your note"
        case .completed: return "AI output is ready"
        }
    }

    private var headerSubtitle: String {
        switch viewModel.gapDetectionMode {
        case .config:
            return "Compare your note with related community posts and optional class materials before the AI builds a gap map."
        case .running:
            return "Comparing your note against related materials."
        case .completed:
            return "Your gap summary has been generated. Open it now or come back from the toolbar later."
        }
    }

    private var recommendedNotes: [Note] {
        notes
            .filter { $0.id != currentNote?.id }
            .filter { note in
                guard let subject = currentNote?.subject, !subject.isEmpty else { return true }
                return note.subject == subject || note.tag == "Public" || note.tag == "Course"
            }
    }

    private var noteOptions: [Note] {
        var seen = Set<String>()
        return ([currentNote].compactMap { $0 } + notes).filter { note in
            guard !seen.contains(note.id) else { return false }
            seen.insert(note.id)
            return true
        }
    }

    private var selectedOwnNote: Note? {
        guard let id = viewModel.gapSelectedOwnNoteId else { return currentNote }
        return noteOptions.first { $0.id == id } ?? currentNote
    }

    private var previewNote: Note? {
        guard let id = viewModel.gapPreviewNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    private var selectedSourceTitle: String {
        let title = selectedOwnNote?.title ?? currentNote?.title ?? "Untitled Note"
        return title.isEmpty ? "Untitled Note" : title
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.54)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1))
    }

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black))
            .tracking(0.1 * 11)
            .textCase(.uppercase)
            .foregroundStyle(NoteEditorTheme.textMuted)
    }

    private func gapNoteSourceCard(_ note: Note?, active: Bool, action: (() -> Void)? = nil) -> some View {
        let title = note?.title.isEmpty == false ? note?.title ?? "Untitled Note" : "Untitled Note"
        let pageCount = note?.pageSettings.count ?? 1
        return Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                        .lineLimit(1)
                    Text([note?.subject, note?.tag, "\(pageCount) page\(pageCount == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if active {
                    Text("Source")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(NoteEditorTheme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(NoteEditorTheme.accent.opacity(0.12)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(active ? NoteEditorTheme.accent.opacity(0.08) : Color.white.opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(active ? NoteEditorTheme.accent.opacity(0.22) : NoteEditorTheme.chromeBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private var currentNoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current note")
                .font(.system(size: 11, weight: .black))
                .tracking(0.08 * 11)
                .foregroundStyle(NoteEditorTheme.textMuted)
            Text(currentNote?.title.isEmpty == false ? currentNote?.title ?? "Untitled Note" : "Untitled Note")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
            Text("\(currentNote?.pageSettings.count ?? 1) page\(currentNote?.pageSettings.count == 1 ? "" : "s") selected as your source")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
    }

    private func sourceNoteRow(_ note: Note) -> some View {
        let selected = viewModel.selectedGapSourceIds.contains(note.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(note.title.isEmpty ? "Untitled Note" : note.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                Text([note.subject, note.tag, "\(note.pageSettings.count) pages"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
            }
            Spacer()
            Button("Preview") {
                viewModel.gapDetectionConfigPanel = .preview
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(NoteEditorTheme.textMuted)
            .buttonStyle(.plain)
            Button(selected ? "Selected" : "Add") {
                if selected {
                    viewModel.selectedGapSourceIds.remove(note.id)
                } else {
                    viewModel.selectedGapSourceIds.insert(note.id)
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(selected ? .white : NoteEditorTheme.accent)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(selected ? NoteEditorTheme.accent : Color.white.opacity(0.86)))
            .overlay(Capsule().strokeBorder(NoteEditorTheme.accent.opacity(0.24), lineWidth: 1))
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(selected ? NoteEditorTheme.accent.opacity(0.10) : Color.white.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? NoteEditorTheme.accent.opacity(0.24) : NoteEditorTheme.chromeBorder, lineWidth: 1))
    }

    private func gapCommunityNoteCard(_ note: Note, compact: Bool = false) -> some View {
        let selected = viewModel.selectedGapSourceIds.contains(note.id)
        let price = max(4, min(12, note.pageSettings.count + 3))
        return Button {
            viewModel.gapPreviewNoteId = note.id
            viewModel.gapDetectionConfigPanel = .preview
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(note.title.isEmpty ? "Untitled Note" : note.title)
                            .font(.system(size: compact ? 14 : 15, weight: .bold))
                            .foregroundStyle(NoteEditorTheme.textPrimary)
                            .lineLimit(1)
                        Text("\(price) Credits")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(NoteEditorTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(NoteEditorTheme.accent.opacity(0.12)))
                    }
                    Text([note.subject, note.tag, note.formattedDate].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                        .lineLimit(1)
                    if !compact {
                        HStack(spacing: 6) {
                            gapChip(note.subject ?? "Same course")
                            gapChip("Recent")
                            gapChip("\(note.pageSettings.count) pages")
                        }
                    }
                }
                Spacer()
                Text(selected ? "Selected" : "Preview")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selected ? NoteEditorTheme.accent : NoteEditorTheme.textMuted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? NoteEditorTheme.accent.opacity(0.10) : Color.white.opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? NoteEditorTheme.accent.opacity(0.24) : NoteEditorTheme.chromeBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sourcePreviewCard(_ note: Note) -> some View {
        let selected = viewModel.selectedGapSourceIds.contains(note.id)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(note.title.isEmpty ? "Untitled Note" : note.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                    Text([note.subject, note.tag, note.formattedDate].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
                Spacer()
                Text("\(max(4, min(12, note.pageSettings.count + 3))) Credits")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(NoteEditorTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(NoteEditorTheme.accent.opacity(0.12)))
            }
            HStack(spacing: 8) {
                gapChip(note.subject ?? "Same course")
                gapChip(note.formattedDate)
                gapChip("Similar topic")
            }
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.72), lineWidth: 2)
                .background(Color(red: 255/255, green: 253/255, blue: 241/255), in: RoundedRectangle(cornerRadius: 20))
                .frame(height: 150)
            HStack {
                Text(selected ? "This peer note is already included." : "Preview first, then decide whether to include this source.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                Spacer()
                Button(viewModel.gapDetectionConfigPanel == .preview ? "Back to recommendations" : "Back") {
                    viewModel.gapDetectionConfigPanel = .root
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.78)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                .buttonStyle(.plain)
                Button(selected ? "Remove from this run" : "Use this note") {
                    if selected {
                        viewModel.selectedGapSourceIds.remove(note.id)
                    } else {
                        viewModel.selectedGapSourceIds.insert(note.id)
                    }
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? NoteEditorTheme.textPrimary : .white)
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(selected
                              ? AnyShapeStyle(Color.white.opacity(0.78))
                              : AnyShapeStyle(LinearGradient(colors: [NoteEditorTheme.accent, Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                )
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? NoteEditorTheme.chromeBorder : .clear, lineWidth: 1))
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.56)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1))
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func optionRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? NoteEditorTheme.accent : NoteEditorTheme.textMuted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .bold))
                    Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(NoteEditorTheme.textSecondary)
                }
                Spacer()
            }
            .foregroundStyle(NoteEditorTheme.textPrimary)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.84)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? NoteEditorTheme.accent.opacity(0.25) : NoteEditorTheme.chromeBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func outputModeButton(_ mode: GapDetectionOutputMode) -> some View {
        Button {
            viewModel.gapOutputMode = mode
        } label: {
            Text(mode.label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(viewModel.gapOutputMode == mode ? NoteEditorTheme.accent : NoteEditorTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(viewModel.gapOutputMode == mode ? NoteEditorTheme.accent.opacity(0.14) : Color.white.opacity(0.72)))
                .overlay(Capsule().strokeBorder(viewModel.gapOutputMode == mode ? NoteEditorTheme.accent.opacity(0.22) : NoteEditorTheme.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func priceRow(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
            Spacer()
            Text("\(value) Credits")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
        }
    }

    private func gapChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(NoteEditorTheme.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.72)))
            .overlay(Capsule().strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1))
    }

    private func circleBackButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.84)))
                .overlay(Circle().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func filterBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.08 * 11)
                .textCase(.uppercase)
                .foregroundStyle(NoteEditorTheme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.84)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func backButton(_ text: String) -> some View {
        Button {
            viewModel.gapDetectionConfigPanel = .root
        } label: {
            Label(text, systemImage: "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func filterPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(NoteEditorTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(0.78)))
            .overlay(Capsule().strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
    }
}
