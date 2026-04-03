//
//  GlassCard.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(32)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.linearGradient(
                            colors: [
                                .white.opacity(0.55),
                                .white.opacity(0.30),
                                Color(red: 245/255, green: 248/255, blue: 252/255).opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.6), .white.opacity(0.15), .white.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}
