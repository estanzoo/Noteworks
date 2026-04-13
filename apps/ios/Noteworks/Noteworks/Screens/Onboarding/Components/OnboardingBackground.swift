//
//  OnboardingBackground.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct OnboardingBackground: View {
    @State private var phase: CGFloat = 0

    // React: linear-gradient(160deg, #BDD8EA, #D4E4F0 30%, #E6EEF5 55%, #F0F3F7 80%, #E8ECF4)
    private let bgGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 189/255, green: 216/255, blue: 234/255), location: 0.0),
            .init(color: Color(red: 212/255, green: 228/255, blue: 240/255), location: 0.30),
            .init(color: Color(red: 230/255, green: 238/255, blue: 245/255), location: 0.55),
            .init(color: Color(red: 240/255, green: 243/255, blue: 247/255), location: 0.80),
            .init(color: Color(red: 232/255, green: 236/255, blue: 244/255), location: 1.0),
        ],
        startPoint: UnitPoint(x: 0.33, y: 0.03),
        endPoint: UnitPoint(x: 0.67, y: 0.97)
    )

    var body: some View {
        ZStack {
            bgGradient

            // Blob 1: rgb(142,198,225) center alpha 0.55, div opacity 0.45 → effective 0.2475
            BlobCircle(rgb: (142, 198, 225), centerAlpha: 0.2475, size: 500, blur: 50)
                .offset(x: -80 + sin(phase * 0.5) * 30, y: -200 + cos(phase * 0.3) * 40)
            // Blob 2: rgb(120,195,210) center alpha 0.45, div opacity 0.35 → effective 0.1575
            BlobCircle(rgb: (120, 195, 210), centerAlpha: 0.1575, size: 400, blur: 55)
                .offset(x: 120 + cos(phase * 0.4) * 40, y: 250 + sin(phase * 0.35) * 30)
            // Blob 3: rgb(175,185,220) center alpha 0.40, div opacity 0.30 → effective 0.12
            BlobCircle(rgb: (175, 185, 220), centerAlpha: 0.12, size: 350, blur: 65)
                .offset(x: -20 + sin(phase * 0.6) * 25, y: 50 + cos(phase * 0.45) * 35)
            // Blob 4: rgb(185,178,210) center alpha 0.28, div opacity 0.22 → effective 0.0616
            BlobCircle(rgb: (185, 178, 210), centerAlpha: 0.0616, size: 280, blur: 50)
                .offset(x: 140 + cos(phase * 0.55) * 20, y: -120 + sin(phase * 0.4) * 25)
            // Blob 5: rgb(155,200,205) center alpha 0.32, div opacity 0.28 → effective 0.0896
            BlobCircle(rgb: (155, 200, 205), centerAlpha: 0.0896, size: 240, blur: 58)
                .offset(x: -100 + sin(phase * 0.35) * 35, y: 180 + cos(phase * 0.5) * 20)
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

private struct BlobCircle: View {
    let rgb: (CGFloat, CGFloat, CGFloat)
    let centerAlpha: CGFloat
    let size: CGFloat
    let blur: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: rgb.0/255, green: rgb.1/255, blue: rgb.2/255).opacity(centerAlpha),
                        Color(red: rgb.0/255, green: rgb.1/255, blue: rgb.2/255).opacity(0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.35
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blur)
    }
}
