//
//  LoginView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Login Page")
                .font(.largeTitle)
            
            // Temporary login button for testing
            Button("Login (Test)") {
                appState.isAuthenticated = true
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            Text("This is a placeholder. Add real login UI here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Login")
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}

