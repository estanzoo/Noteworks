//
//  ContentView.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(NotesStore())
}
