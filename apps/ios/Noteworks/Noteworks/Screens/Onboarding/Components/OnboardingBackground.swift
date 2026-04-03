//
//  OnboardingBackground.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct OnboardingBackground: View {
    @State private var phase: CGFloat = 0

    private let bgGradient = LinearGradient(
        colors: [
            Color(red: 189/255, green: 216/255, blue: 234/255),
            Color(red: 212/255, green: 228/255, blue: 240/255),
            Color(red: 230/255, green: 238/255, blue: 245/255),
            Color(red: 240/255, green: 243/255, blue: 247/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            bgGradient

            // Animated blobs
            BlobCircle(color: Color(red: 142/255, green: 198/255, blue: 225/255).opacity(0.45), size: 500, blur: 50)
                .offset(x: -80 + sin(phase * 0.5) * 30, y: -200 + cos(phase * 0.3) * 40)
            BlobCircle(color: Color(red: 120/255, green: 195/255, blue: 210/255).opacity(0.35), size: 400, blur: 55)
                .offset(x: 120 + cos(phase * 0.4) * 40, y: 250 + sin(phase * 0.35) * 30)
            BlobCircle(color: Color(red: 175/255, green: 185/255, blue: 220/255).opacity(0.30), size: 350, blur: 65)
                .offset(x: -20 + sin(phase * 0.6) * 25, y: 50 + cos(phase * 0.45) * 35)
            BlobCircle(color: Color(red: 185/255, green: 178/255, blue: 210/255).opacity(0.22), size: 280, blur: 50)
                .offset(x: 140 + cos(phase * 0.55) * 20, y: -120 + sin(phase * 0.4) * 25)
            BlobCircle(color: Color(red: 155/255, green: 200/255, blue: 205/255).opacity(0.28), size: 240, blur: 58)
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
    let color: Color
    let size: CGFloat
    let blur: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: blur)
    }
}
