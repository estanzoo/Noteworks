//
//  GlassCard.swift
//  Noteworks
//
//  Shared glass panel used by onboarding and profile.
//  Defaults match onboarding (padding 32, corner 28). Pass smaller values for profile hero.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 32
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.5),
                                    Color.white.opacity(0.25),
                                    Color(red: 245/255, green: 248/255, blue: 252/255).opacity(0.35),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.8),
                                    Color.white.opacity(0),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                        .padding(.top, 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
    }
}
