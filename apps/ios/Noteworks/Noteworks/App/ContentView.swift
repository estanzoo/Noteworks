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
                // User is logged in → show main app with tabs
                MainTabView()
            } else {
                // User not logged in → show login screen
                NavigationStack {
                    LoginView()
                }
            }
        }
        .environmentObject(appState)
    }
}

#Preview {
    ContentView()
}
