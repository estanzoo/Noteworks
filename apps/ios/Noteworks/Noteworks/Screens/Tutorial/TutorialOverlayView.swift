//
//  TutorialOverlayView.swift
//  Noteworks
//
//  Coach-mark overlay mirroring TutorialOverlay in NoteWorks_UI 5.
//

import SwiftUI
import UIKit

struct TutorialOverlayView: View {
    @ObservedObject var coordinator: TutorialCoordinator
    let firstName: String
    let targetFrames: [TutorialTarget: CGRect]
    var showsBackdrop: Bool = true
    var showsCoachCard: Bool = true
    /// When true, blur the whole screen (for modals/dropdowns rendered above this layer).
    var forceFullScreenBackdrop: Bool = false
    /// When true, only the coach card receives touches — background UI is static.
    var blocksBackgroundInteraction: Bool = true

    var body: some View {
        if coordinator.isActive, !coordinator.showSkipConfirm, let step = coordinator.currentStep,
           showsBackdrop || showsCoachCard {
            GeometryReader { geo in
                let targetRect = step.target.flatMap { spotlightRect(for: $0, in: geo) }
                let spotlightRadius: CGFloat = {
                    guard let target = step.target, let targetRect else { return 24 }
                    return target.spotlightCornerRadius(in: targetRect)
                }()
                /// Frosted blur: welcome, modal underlays, and brief full-screen
                /// cover while a spotlight anchor is still measuring after a tab switch.
                /// Coach marks on real controls use flat dim + cutout (NoteWorks_UI 5).
                let anchorPending = step.target != nil && targetRect == nil && !forceFullScreenBackdrop
                let composerStep = step.id == "community-composer"
                let aiDropdownStep = step.id == "ai-gap" || step.id == "ai-smart"
                let usesFrostedBlur = forceFullScreenBackdrop || step.target == nil || (anchorPending && !composerStep)
                /// AI dropdown steps: flat dim under the panel — no cutout (panel + highlight sit above).
                let spotlightHole: CGRect? = {
                    if forceFullScreenBackdrop || (anchorPending && !composerStep) { return nil }
                    if aiDropdownStep { return nil }
                    return targetRect
                }()
                let fullScreenDim = spotlightHole == nil

                ZStack(alignment: .topLeading) {
                    if showsBackdrop {
                        TutorialBackdropRepresentable(
                            spotlightHole: spotlightHole,
                            spotlightCornerRadius: spotlightRadius,
                            dimOpacity: fullScreenDim && usesFrostedBlur ? 0.18 : 0.28,
                            usesDarkTint: fullScreenDim && usesFrostedBlur,
                            usesFrostedBlur: usesFrostedBlur
                        )
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.22), value: coordinator.stepIndex)
                        .animation(.easeInOut(duration: 0.22), value: targetRect)
                    }

                    if blocksBackgroundInteraction {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                    }

                    if showsCoachCard {
                        coachCard(step: step, targetRect: targetRect, container: geo.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .zIndex(500)
        }
    }

    @ViewBuilder
    private func coachCard(
        step: NoteWorksTutorialStep,
        targetRect: CGRect?,
        container: CGSize
    ) -> some View {
        let width: CGFloat = step.id == "welcome" ? 288 : 232
        let pos = coachPosition(step: step, targetRect: targetRect, cardWidth: width, container: container)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Text("\(coordinator.stepIndex + 1) / \(coordinator.steps.count)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.38))
            }
            .padding(.bottom, 7)

            Text(coordinator.displayTitle(firstName: firstName))
                .font(.system(size: step.id == "welcome" ? 20 : 18, weight: .heavy))
                .foregroundStyle(TutorialTheme.textPrimary)
                .tracking(-0.04 * 18)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.body)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TutorialTheme.textSecondary)
                .lineSpacing(2)
                .padding(.top, 6)

            HStack(spacing: 4) {
                ForEach(Array(coordinator.steps.enumerated()), id: \.offset) { index, _ in
                    Capsule()
                        .fill(index <= coordinator.stepIndex
                              ? TutorialTheme.accent.opacity(0.72)
                              : Color(red: 154/255, green: 171/255, blue: 188/255).opacity(0.16))
                        .frame(height: 3)
                }
            }
            .padding(.top, 11)

            HStack {
                Button("Skip") {
                    coordinator.requestSkip()
                }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.42))
                .buttonStyle(.plain)

                Spacer()

                if !coordinator.isFirstStep {
                    Button("Back") {
                        coordinator.goToPreviousStep()
                    }
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(TutorialTheme.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }

                Button(coordinator.isLastStep ? "Finish" : (step.cta ?? "Next")) {
                    coordinator.primaryButtonTapped()
                }
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [TutorialTheme.accent, Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .buttonStyle(.plain)
            }
            .padding(.top, 11)
        }
        .padding(step.id == "welcome" ? 14 : 12)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 248/255, green: 252/255, blue: 255/255).opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: Color(red: 35/255, green: 55/255, blue: 76/255).opacity(0.16), radius: 17, y: 7)
        .position(x: pos.x + width / 2, y: pos.y + 86)
    }

    private func spotlightRect(for target: TutorialTarget, in geo: GeometryProxy) -> CGRect? {
        guard let global = targetFrames[target] else { return nil }
        let local = geo.frame(in: .global)
        return global.offsetBy(dx: -local.minX, dy: -local.minY)
    }

    private func coachPosition(
        step: NoteWorksTutorialStep,
        targetRect: CGRect?,
        cardWidth: CGFloat,
        container: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 18
        let gap: CGFloat = 14
        let estimatedHeight: CGFloat = step.id == "welcome" ? 164 : 172

        guard let targetRect else {
            return CGPoint(
                x: max(margin, (container.width - cardWidth) / 2),
                y: max(margin, (container.height - estimatedHeight) / 2)
            )
        }

        var left = targetRect.midX - cardWidth / 2
        var top = targetRect.maxY + gap

        switch step.placement {
        case .left, .leftBottom:
            left = targetRect.minX - cardWidth - gap
            top = step.placement == .leftBottom
                ? targetRect.maxY - estimatedHeight
                : targetRect.midY - estimatedHeight / 2
            if left < margin { left = targetRect.maxX + gap }
        case .right:
            left = targetRect.maxX + gap
            top = targetRect.midY - estimatedHeight / 2
            if left + cardWidth > container.width - margin {
                left = targetRect.minX - cardWidth - gap
            }
        case .top:
            left = targetRect.midX - cardWidth / 2
            top = targetRect.minY - estimatedHeight - gap
        case .bottom, .center:
            left = targetRect.midX - cardWidth / 2
            top = targetRect.maxY + gap
        }

        if top + estimatedHeight > container.height - margin {
            top = targetRect.minY - estimatedHeight - gap
        }
        top = min(max(margin, top), container.height - estimatedHeight - margin)
        left = min(max(margin, left), container.width - cardWidth - margin)

        return CGPoint(x: left, y: top)
    }
}

// MARK: - Blurred backdrop (UIKit for reliable spotlight masking)

private struct TutorialBackdropRepresentable: UIViewRepresentable {
    var spotlightHole: CGRect?
    var spotlightCornerRadius: CGFloat
    var dimOpacity: CGFloat
    var usesDarkTint: Bool
    var usesFrostedBlur: Bool

    func makeUIView(context: Context) -> TutorialBackdropUIView {
        TutorialBackdropUIView()
    }

    func updateUIView(_ uiView: TutorialBackdropUIView, context: Context) {
        uiView.spotlightHole = spotlightHole
        uiView.spotlightCornerRadius = spotlightCornerRadius
        uiView.dimOpacity = dimOpacity
        uiView.usesDarkTint = usesDarkTint
        uiView.usesFrostedBlur = usesFrostedBlur
        uiView.setNeedsLayout()
    }
}

private final class TutorialBackdropUIView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let dimView = UIView()

    var spotlightHole: CGRect?
    var spotlightCornerRadius: CGFloat = 24
    var dimOpacity: CGFloat = 0.18
    var usesDarkTint = true
    var usesFrostedBlur = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        dimView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimView)
        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        blurView.isHidden = !usesFrostedBlur
        dimView.backgroundColor = usesDarkTint
            ? UIColor(red: 18 / 255, green: 28 / 255, blue: 38 / 255, alpha: dimOpacity)
            : UIColor.black.withAlphaComponent(dimOpacity)

        let maskLayer: CAShapeLayer? = {
            guard let spotlightHole else { return nil }
            let path = UIBezierPath(rect: bounds)
            path.append(UIBezierPath(roundedRect: spotlightHole, cornerRadius: spotlightCornerRadius))
            let mask = CAShapeLayer()
            mask.path = path.cgPath
            mask.fillRule = .evenOdd
            return mask
        }()

        blurView.layer.mask = nil
        dimView.layer.mask = usesFrostedBlur ? nil : maskLayer
    }
}

struct TutorialSkipConfirmPopup: View {
    @ObservedObject var coordinator: TutorialCoordinator

    var body: some View {
        if coordinator.showSkipConfirm {
            ZStack {
                TutorialBackdropRepresentable(
                    spotlightHole: nil,
                    spotlightCornerRadius: 24,
                    dimOpacity: 0.18,
                    usesDarkTint: true,
                    usesFrostedBlur: true
                )
                .ignoresSafeArea()
                .onTapGesture { coordinator.showSkipConfirm = false }

                VStack(alignment: .leading, spacing: 16) {
                    Text("SKIP TUTORIAL?")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.3))
                        .tracking(0.08 * 12)

                    Text("You can replay it later")
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(TutorialTheme.textPrimary)
                        .tracking(-0.04 * 25)

                    Text("If you skip now, we'll take you to the welcome screen. You can restart the tutorial anytime from Profile > General > Replay Tutorial.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TutorialTheme.textSecondary)
                        .lineSpacing(4)

                    HStack {
                        Spacer()
                        Button("Keep going") {
                            coordinator.showSkipConfirm = false
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TutorialTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        )
                        .buttonStyle(.plain)

                        Button("Skip tutorial") {
                            coordinator.confirmSkip()
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(TutorialTheme.accent)
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 250/255, green: 252/255, blue: 254/255).opacity(0.98),
                                    Color(red: 241/255, green: 246/255, blue: 250/255).opacity(0.97)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 32, y: 12)
                .padding(.horizontal, 24)
            }
            .zIndex(600)
            .transition(.opacity)
        }
    }
}

struct TutorialCompleteView: View {
    @ObservedObject var coordinator: TutorialCoordinator
    let firstName: String

    var body: some View {
        if coordinator.showComplete {
            ZStack {
                TutorialBackdropRepresentable(
                    spotlightHole: nil,
                    spotlightCornerRadius: 24,
                    dimOpacity: 0.18,
                    usesDarkTint: true,
                    usesFrostedBlur: true
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color(red: 189/255, green: 216/255, blue: 234/255).opacity(0.55),
                        Color(red: 232/255, green: 238/255, blue: 247/255).opacity(0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    Text("Welcome To NoteWorks, \(firstName.isEmpty ? "there" : firstName)")
                        .font(.system(size: 48, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(TutorialTheme.textPrimary)
                        .tracking(-0.05 * 48)
                        .minimumScaleFactor(0.6)
                        .lineLimit(3)

                    Text("Your workspace is ready. Start from Home, create a Bubble, or jump into Library whenever you need a note.")
                        .font(.system(size: 18, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(TutorialTheme.textSecondary)
                        .frame(maxWidth: 560)

                    Button("Tap to Start") {
                        coordinator.dismissCompleteScreen()
                    }
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [TutorialTheme.accent, Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
                .padding(.horizontal, 24)
            }
            .zIndex(550)
            .transition(.opacity)
        }
    }
}
