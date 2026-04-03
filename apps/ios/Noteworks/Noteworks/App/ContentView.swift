//
//  ContentView.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .environmentObject(appState)
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}
