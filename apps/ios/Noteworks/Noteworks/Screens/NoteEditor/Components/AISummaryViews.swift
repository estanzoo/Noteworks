//
//  AISummaryViews.swift
//  Noteworks
//
//  Gap / Smart side panels and unified AI summary history popup.
//

import SwiftUI

// MARK: - Gap summary side panel

struct GapSummarySidePanel: View {
    let entry: AISummaryEntry
    let onClose: () -> Void

    var body: some View {
        AISummarySidePanelChrome(
            eyebrow: "Gap Detection Summary",
            title: entry.sourceTitle,
            subtitle: "\(entry.createdAtLabel) · \(entry.historyMeta)",
            onClose: onClose
        ) {
            ForEach(entry.templates) { template in
                summaryTemplateCard(template)
            }
        }
    }
}

// MARK: - Smart summary side panel

struct SmartSummarySidePanel: View {
    let entry: AISummaryEntry
    let onClose: () -> Void

    var body: some View {
        AISummarySidePanelChrome(
            eyebrow: "Smart Organization Summary",
            title: entry.sourceTitle,
            subtitle: entry.createdAtLabel,
            onClose: onClose
        ) {
            ForEach(entry.sections) { section in
                summarySectionCard(section, accent: NoteEditorTheme.accent)
            }
        }
    }
}

// MARK: - Shared side panel chrome

private struct AISummarySidePanelChrome<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.1 * 10)
                        .foregroundStyle(NoteEditorTheme.textMuted)
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NoteEditorTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NoteEditorTheme.textMuted)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)
            Divider().overlay(NoteEditorTheme.chromeBorder.opacity(0.7))

            ScrollView {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .frame(width: min(420, UIScreen.main.bounds.width - 48))
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.78),
                            Color(red: 233/255, green: 241/255, blue: 247/255).opacity(0.7),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 64, x: 0, y: 24)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

@ViewBuilder
private func summaryTemplateCard(_ template: AISummaryTemplate) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.badge.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.1 * 10)
                .foregroundStyle(NoteEditorTheme.accent)
            Text(template.title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(NoteEditorTheme.textPrimary)
        }
        ForEach(template.sections) { section in
            summarySectionBlock(section)
        }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.6))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
    )
}

@ViewBuilder
private func summarySectionCard(_ section: AISummarySection, accent: Color) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(section.heading.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.08 * 11)
            .foregroundStyle(accent)
        summarySectionBlock(section)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.6))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
    )
}

@ViewBuilder
private func summarySectionBlock(_ section: AISummarySection) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        if !section.heading.isEmpty {
            Text(section.heading.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.08 * 11)
                .foregroundStyle(NoteEditorTheme.textSecondary)
        }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, line in
                Text(formatBullet(line))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private func formatBullet(_ line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("-") {
        return "• " + trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
    }
    if trimmed.hasPrefix("•") { return trimmed }
    return "• \(trimmed)"
}

// MARK: - History popup

struct AISummaryHistoryPopup: View {
    let entries: [AISummaryEntry]
    let onSelect: (AISummaryEntry) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color(red: 16/255, green: 24/255, blue: 36/255)
                .opacity(0.18)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PAST SUMMARIES")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.1 * 10)
                            .foregroundStyle(NoteEditorTheme.textMuted)
                        Text("AI summary history")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(NoteEditorTheme.textPrimary)
                        Text("Gap Detection and Smart Organization runs for this note. Tap one to open it next to your note.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NoteEditorTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NoteEditorTheme.textMuted)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.black.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 14)
                Divider().overlay(NoteEditorTheme.chromeBorder.opacity(0.7))

                ScrollView {
                    VStack(spacing: 10) {
                        if entries.isEmpty {
                            emptyHistory
                        } else {
                            ForEach(entries) { entry in
                                Button {
                                    onSelect(entry)
                                } label: {
                                    historyRow(entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .frame(width: min(540, UIScreen.main.bounds.width - 32))
            .frame(maxHeight: min(UIScreen.main.bounds.height * 0.8, 720))
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.78),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 60, x: 0, y: 24)
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: 6) {
            Text("No summaries yet")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
            Text("Run Gap Detection or Smart Organization for this note to see it here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(red: 160/255, green: 177/255, blue: 194/255).opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    private func historyRow(_ entry: AISummaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.kind == .gap ? "GAP DETECTION" : "SMART ORGANIZATION")
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.06 * 10)
                    .foregroundStyle(entry.kind == .gap ? NoteEditorTheme.accent : Color(red: 0x8A/255, green: 0x4F/255, blue: 0x0E/255))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            entry.kind == .gap
                                ? NoteEditorTheme.accent.opacity(0.14)
                                : Color(red: 246/255, green: 175/255, blue: 72/255).opacity(0.18)
                        )
                    )
                Text(entry.createdAtLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
            }
            Text(entry.historyMeta)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - Smart Organization modal

struct SmartOrganizationPopup: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    @ObservedObject var creditsStore: CreditsStore
    let noteTitle: String
    let accessToken: String
    let onClose: () -> Void

    private var estimatedCost: Int { viewModel.estimatedSmartOrganizationCredits }
    private var canConfirm: Bool { estimatedCost <= creditsStore.balance }

    var body: some View {
        ZStack {
            Color(red: 16/255, green: 24/255, blue: 36/255)
                .opacity(0.18)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    if !viewModel.smartJob.isRunning { onClose() }
                }

            VStack(spacing: 0) {
                header
                Divider().overlay(NoteEditorTheme.chromeBorder.opacity(0.7))
                content
                    .padding(24)
            }
            .frame(width: min(560, UIScreen.main.bounds.width - 32))
            .frame(maxHeight: min(UIScreen.main.bounds.height * 0.8, 720))
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.84),
                                Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.66),
                                Color(red: 233/255, green: 241/255, blue: 247/255).opacity(0.56),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 70, x: 0, y: 28)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SMART ORGANIZATION")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.1 * 11)
                    .foregroundStyle(NoteEditorTheme.textMuted)
                Text(headerTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if viewModel.smartJob.isRunning {
                Button("Minimize") {
                    viewModel.minimizeSmartOrganizationPopup()
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
        if viewModel.smartJob.isRunning || viewModel.smartJob.isCompleted {
            smartProgressContent
        } else {
            smartConfigContent
        }
    }

    private var smartConfigContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Smart Organization does:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                bullet("Reorders sections so related ideas sit together.")
                bullet("Renames headings to match what's underneath.")
                bullet("Tightens long paragraphs and standardizes bullet style.")
            }

            if !viewModel.aiEnhancementNotice.isEmpty {
                Text(viewModel.aiEnhancementNotice)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC1/255, green: 0x60/255, blue: 0x60/255))
            }

            HStack {
                Text("Estimated cost")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                Spacer()
                Text("\(estimatedCost) Credits")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.accent)
            }

            if !canConfirm {
                Text("You only have \(creditsStore.balance) credits available right now.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC1/255, green: 0x60/255, blue: 0x60/255))
            }

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.78)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NoteEditorTheme.chromeBorder, lineWidth: 1))
                    .buttonStyle(.plain)

                Button("Confirm") {
                    Task {
                        await viewModel.confirmSmartOrganization(accessToken: accessToken)
                    }
                }
                .disabled(!canConfirm)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(canConfirm ? .white : NoteEditorTheme.textMuted)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
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
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [NoteEditorTheme.accent.opacity(0.12), Color.white.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(NoteEditorTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var smartProgressContent: some View {
        VStack(spacing: 20) {
            notePreviewCard
            AIEnhancementProgressBar(
                progress: viewModel.smartJob.progress,
                isCompleted: viewModel.smartJob.isCompleted,
                inProgressLabel: "Organizing",
                completedLabel: "Finished"
            )
            if viewModel.smartJob.isCompleted {
                HStack {
                    Spacer()
                    Button("Done") {
                        viewModel.finishSmartOrganizationPopup()
                        onClose()
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 14).fill(NoteEditorTheme.accent))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
        )
    }

    private var notePreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 255/255, green: 253/255, blue: 241/255),
                            Color(red: 255/255, green: 251/255, blue: 232/255),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 240, height: 300)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Color(red: 228/255, green: 229/255, blue: 220/255), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 12) {
                Capsule().fill(NoteEditorTheme.accent.opacity(0.55)).frame(height: 10)
                Capsule().fill(Color.black.opacity(0.08)).frame(height: 8)
                Capsule().fill(Color.black.opacity(0.08)).frame(width: 160, height: 8)
                Capsule().fill(NoteEditorTheme.accent.opacity(0.55)).frame(height: 10)
                Capsule().fill(Color.black.opacity(0.08)).frame(height: 8)
                Capsule().fill(NoteEditorTheme.accent.opacity(0.55)).frame(height: 10)
                Capsule().fill(Color.black.opacity(0.08)).frame(height: 8)
            }
            .padding(24)
            .frame(width: 240, height: 300)
        }
        .frame(maxWidth: .infinity)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NoteEditorTheme.textSecondary)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerTitle: String {
        if viewModel.smartJob.isRunning { return "Organizing your note" }
        if viewModel.smartJob.isCompleted { return "Your note is organized" }
        return "Tidy this note's structure"
    }

    private var headerSubtitle: String {
        if viewModel.smartJob.isRunning {
            return "Reorganizing sections and bringing related ideas closer together."
        }
        if viewModel.smartJob.isCompleted {
            return "A summary of what changed is opening beside your note."
        }
        return "AI will reorder sections, tidy headings, and tighten paragraphs in \(noteTitle). Your original is preserved."
    }
}
