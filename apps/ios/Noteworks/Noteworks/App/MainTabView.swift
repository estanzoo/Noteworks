//
//  MainTabView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "Home"
    case notebook = "Note"
    case people = "Public"

    var icon: String {
        switch self {
        case .home:     return "Icons/fluent_home-24-regular"
        case .notebook: return "Icons/fluent_notebook-24-regular"
        case .people:   return "Icons/fluent_people-24-regular"
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            // Page content
            NavigationStack {
                Group {
                    switch selectedTab {
                    case .home:     HomeView()
                    case .notebook: CourseSpaceView()
                    case .people:   AccountView()
                    }
                }
            }

            FloatingTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    // Bar background layers matching Figma color-dodge blend
    private let barLayerDark   = Color(white: 0.20)
    private let barLayerWhite  = Color(white: 1.00).opacity(0.5)
    private let barLayerLight  = Color(white: 0.97)

    // Selected highlight: hsba(0, 0%, 93%, 1), Plus Darker blend
    private let highlightColor = Color(white: 0.93)

    var body: some View {
        GeometryReader { geo in
            // Scale bar width relative to screen: 290 / 390 ≈ 74% of screen width,
            // clamped so it never gets too wide on large iPads or too narrow on small ones.
            let barWidth = min(max(geo.size.width * 0.38, 280), 360)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    TabItemButton(tab: tab, selectedTab: $selectedTab, highlightColor: highlightColor)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: barWidth, height: 62)
            // Layered bar background (Figma color-dodge)
            .background {
                ZStack {
                    barLayerDark
                    barLayerWhite.blendMode(.colorDodge)
                    barLayerLight.blendMode(.colorDodge)
                }
            }
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
            // Center horizontally, pin to bottom with safe-area padding
            .position(x: geo.size.width / 2, y: geo.size.height - 20 - 31) // 31 = half bar height
        }
        .frame(height: 62 + 20 + 34) // bar + bottom gap + safe area estimate
    }
}

// MARK: - Individual Tab Button

struct TabItemButton: View {
    let tab: AppTab
    @Binding var selectedTab: AppTab
    let highlightColor: Color

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                // Always rendered — opacity controls visibility to avoid layout shifts
                RoundedRectangle(cornerRadius: 100)
                    .fill(highlightColor.blendMode(.plusDarker))
                    .overlay {
                        RoundedRectangle(cornerRadius: 100)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.9),
                                        .white.opacity(0.4),
                                        .white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    .frame(width: 102, height: 54)
                    .opacity(isSelected ? 1 : 0)

                VStack(spacing: 4) {
                    Image(tab.icon)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)

                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(-0.1)
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.5))
            }
            .frame(height: 54)
            .contentShape(Rectangle())
            .animation(nil, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
}

