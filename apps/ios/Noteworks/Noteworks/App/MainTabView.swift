//
//  MainTabView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

enum AppTab: String, CaseIterable {
    case home = "Home"
    case spaces = "Spaces"
    case account = "Account"
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .spaces: return "person.3.fill"
        case .account: return "person.circle.fill"
        }
    }
    
    var outlineIcon: String {
        switch self {
        case .home: return "house"
        case .spaces: return "person.3"
        case .account: return "person.circle"
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .home
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Page content (full screen)
            NavigationStack {
                Group {
                    switch selectedTab {
                    case .home:
                        HomeView()
                    case .spaces:
                        CommunityView()
                    case .account:
                        AccountView()
                    }
                }
            }
            
            // Floating rounded rectangle tab bar at bottom
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedTab == tab ? tab.icon : tab.outlineIcon)
                                .font(.system(size: 18, weight: .medium))
                            
                            if selectedTab == tab {
                                Text(tab.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                        .padding(.horizontal, selectedTab == tab ? 16 : 12)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab
                                ? AnyShapeStyle(Color.blue)
                                : AnyShapeStyle(Color.clear)
                        )
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

#Preview {
    MainTabView()
}

