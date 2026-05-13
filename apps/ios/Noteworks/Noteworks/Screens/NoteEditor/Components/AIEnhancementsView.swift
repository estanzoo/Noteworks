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
            ) { viewModel.startGapDetection() }

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
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Organization")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
            Text("Organize this note into cleaner sections and improve its structure.")
                .font(.system(size: 12))
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
