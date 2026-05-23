//
//  HomeFAB.swift
//  Noteworks
//
//  Mirrors the floating "+" + ("Bubble" / "Note") action menu from
//  others/noteworks-library(2).jsx L1522–L1611. Tapping the plus rotates
//  it 45° (becomes an ×) and reveals two glass pill buttons that fade,
//  scale, and slide into place using the JSX `cubic-bezier(0.22,0.61,0.36,1)`
//  curve over ~0.24s.
//

import SwiftUI

struct HomeFAB: View {
    @Binding var isOpen: Bool
    let onAddBubble: () -> Void
    let onAddNote: () -> Void
    var onPlusTap: (() -> Bool)? = nil

    /// Same easing/duration as the JSX (`transition: transform 0.24s
    /// cubic-bezier(0.22,0.61,0.36,1)`).
    private var openAnimation: Animation {
        .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.24)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            bubbleButton
            noteButton
            plusButton
        }
        // 190×140 container from JSX L1525, expanded to bottom-right of HomeView.
        .frame(width: 190, height: 140, alignment: .bottomTrailing)
    }

    // MARK: - "Bubble" pill (above the plus)

    /// JSX L1526–L1562: position right:32 / bottom:86 → translate up & in
    /// from `translate(0, 14) scale(0.84)` when opening.
    private var bubbleButton: some View {
        Button {
            isOpen = false
            onAddBubble()
        } label: {
            FabPill(label: "Bubble")
        }
        .buttonStyle(FabPressStyle())
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.84, anchor: .bottomTrailing)
        .offset(x: -32, y: -86)
        .offset(y: isOpen ? 0 : 14)
        .allowsHitTesting(isOpen)
        .animation(openAnimation, value: isOpen)
    }

    // MARK: - "Note" pill (left of the plus)

    /// JSX L1564–L1600: position right:98 / bottom:32 → translate up-left & in
    /// from `translate(14, 14) scale(0.84)` when opening.
    private var noteButton: some View {
        Button {
            isOpen = false
            onAddNote()
        } label: {
            FabPill(label: "Note")
        }
        .buttonStyle(FabPressStyle())
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.84, anchor: .bottomTrailing)
        .offset(x: -98, y: -32)
        .offset(x: isOpen ? 0 : 14, y: isOpen ? 0 : 14)
        .allowsHitTesting(isOpen)
        .animation(openAnimation, value: isOpen)
    }

    // MARK: - Plus button (rotates to × when open)

    /// JSX L1602–L1608: same `GlassIconBtn` used elsewhere; we rotate just the
    /// icon glyph 45° so the glass shell stays square while the "+" becomes "×".
    private var plusButton: some View {
        Button {
            if onPlusTap?() == true {
                withAnimation(openAnimation) { isOpen = true }
                return
            }
            withAnimation(openAnimation) { isOpen.toggle() }
        } label: {
            Image("Icons/fluent_add-32-filled")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(isOpen ? HomeTheme.accent : HomeTheme.textPrimary)
                .rotationEffect(.degrees(isOpen ? 45 : 0))
                .animation(openAnimation, value: isOpen)
                .frame(width: 44, height: 44)
                .background(isOpen ? HomeTheme.accent.opacity(0.15) : Color.white.opacity(0.35))
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isOpen ? 12 : 22,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: isOpen ? 12 : 22,
                        style: .continuous
                    )
                    .strokeBorder(
                        isOpen ? HomeTheme.accent.opacity(0.4) : HomeTheme.glassBorder,
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                .animation(openAnimation, value: isOpen)
        }
        .buttonStyle(.plain)
        .tutorialAnchor(.homeFAB)
    }
}

// MARK: - Pill label (Bubble / Note)

/// Glass pill matching JSX L1532–L1559: 46pt height, 23pt radius, white 0.62
/// fill with `GLASS_BORDER`, drop shadow, and SF 13pt weight 800 text.
private struct FabPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .heavy))
            .tracking(0.02 * 13)
            .foregroundStyle(HomeTheme.textPrimary)
            .padding(.horizontal, 18)
            .frame(minWidth: 80, minHeight: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.62))
            )
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: Color(red: 70/255, green: 92/255, blue: 126/255).opacity(0.14), radius: 12, x: 0, y: 10)
    }
}

private struct FabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
