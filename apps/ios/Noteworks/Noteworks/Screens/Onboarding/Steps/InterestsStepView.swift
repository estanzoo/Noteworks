//
//  InterestsStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct InterestsStepView: View {
    @ObservedObject var data: OnboardingData
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var visible = false
    @State private var customInput = ""
    /// See `SignUpStepView.attemptedNext`.
    @State private var attemptedNext = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 5, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Any Field of Interests?", onBack: onBack)

                        OnboardingRow(disabled: false, onNext: handleNext) {
                            interestFormFields
                        }

                        SkipButton(action: onNext)
                    }
                }
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { visible = true }
        }
    }

    @ViewBuilder
    private var interestFormFields: some View {
        Text("Select topics you're passionate about.")
            .font(.system(size: 15))
            .foregroundStyle(OnboardingTheme.textSecondary)
            .lineSpacing(4)
            .padding(.bottom, 20)

        OnboardingError(
            show: attemptedNext && data.interestsError != nil,
            text: data.interestsError ?? ""
        )

        FlowLayout(spacing: 10) {
            ForEach(OnboardingData.presetInterests, id: \.self) { interest in
                InterestChip(
                    label: interest,
                    isSelected: data.interests.contains(interest),
                    action: { toggleInterest(interest) }
                )
            }
            ForEach(data.customInterests, id: \.self) { interest in
                InterestChip(
                    label: interest,
                    isSelected: true,
                    action: {
                        data.customInterests.removeAll { $0 == interest }
                    }
                )
            }
        }
        .padding(.bottom, 20)

        HStack(spacing: 10) {
            Text("Other")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(OnboardingTheme.textSecondary)

            ZStack(alignment: .trailing) {
                TextField("Type & press Enter...", text: $customInput)
                    .font(.system(size: 15))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(OnboardingTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1.5)
                    }
                    .onSubmit { addCustom() }

                if !customInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: addCustom) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(OnboardingTheme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
        }
    }

    private func toggleInterest(_ interest: String) {
        if data.interests.contains(interest) {
            data.interests.removeAll { $0 == interest }
        } else {
            data.interests.append(interest)
        }
    }

    private func addCustom() {
        let trimmed = customInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !data.customInterests.contains(trimmed) else { return }
        data.customInterests.append(trimmed)
        customInput = ""
    }

    private func handleNext() {
        if data.isInterestsValid {
            onNext()
        } else {
            attemptedNext = true
        }
    }
}

// MARK: - Interest Chip

private struct InterestChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? OnboardingTheme.accentDark : Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.6))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(isSelected ? OnboardingTheme.accent.opacity(0.12) : Color.white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? OnboardingTheme.accent.opacity(0.5) : OnboardingTheme.glassBorder,
                            lineWidth: 1.5
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
