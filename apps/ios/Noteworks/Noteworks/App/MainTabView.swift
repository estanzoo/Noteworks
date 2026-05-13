//
//  MainTabView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "Home"
    case notebook = "Library"
    case people = "Community"

    var icon: String {
        switch self {
        case .home:     return "Icons/fluent_home-24-regular"
        case .notebook: return "Icons/fluent_notebook-24-regular"
        case .people:   return "Icons/fluent_people-24-regular"
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: AppTab? = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            // All four navigation stacks are kept mounted simultaneously
            // (matching the JSX `PageTransition` model at L6831) so:
            //   • per-tab navigation state survives a tab switch
            //   • CourseSpace's notes grid does not have to re-layout from
            //     scratch every time a Home bubble is tapped (the source
            //     of the perceived "lag")
            //   • SwiftUI can cross-fade the layers cleanly via
            //     `.opacity` + `.animation(_, value:)`, instead of
            //     destroying one tree and building another in the same
            //     frame.
            //
            // `allowsHitTesting(false)` on the inactive layers keeps
            // touches from leaking through to hidden screens.
            ZStack {
                tabContainer(.home, isActive: selectedTab == .home) {
                    NavigationStack { HomeView(selectedTab: $selectedTab) }
                }
                tabContainer(.notebook, isActive: selectedTab == .notebook) {
                    NavigationStack { CourseSpaceView(selectedTab: $selectedTab) }
                }
                tabContainer(.people, isActive: selectedTab == .people) {
                    NavigationStack { CommunityView(selectedTab: $selectedTab) }
                }
                tabContainer(nil, isActive: selectedTab == nil) {
                    NavigationStack { ProfileView(selectedTab: $selectedTab) }
                }
            }
            // 0.22s mirrors the JSX `PageTransition` (L6893) which uses
            // `transition: opacity 0.24s cubic-bezier(0.22,0.61,0.36,1)`.
            .animation(.easeInOut(duration: 0.22), value: selectedTab)

            FloatingTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Wraps one tab's view tree with cross-fade visibility + hit-testing
    /// gating. Keeping the tree alive when inactive (just invisible)
    /// preserves both per-tab state and child navigation history.
    @ViewBuilder
    private func tabContainer<Content: View>(
        _ tab: AppTab?,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if Self.isRunningInPreview && !isActive {
            // SwiftUI Previews have a 5-second render budget; mounting all
            // four NavigationStacks at once routinely blows past it. In
            // the real app every tab stays mounted so state survives a
            // tab switch — preview only ever needs the active one.
            Color.clear
        } else {
            content()
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
                // A tiny rest offset on the inactive tab adds the soft "slide
                // forward" feel of the JSX `default` transition (L6869) when
                // it animates back to 0.
                .offset(y: isActive ? 0 : 6)
        }
    }

    private static let isRunningInPreview: Bool =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab?

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
    @Binding var selectedTab: AppTab?
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
    let notesStore = NotesStore.preview()
    return MainTabView()
        .environmentObject(AppState(notesStore: notesStore))
        .environmentObject(notesStore)
}

