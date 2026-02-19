//
//  AccountView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Account Page")
                .font(.largeTitle)
            
            // Logout button
            Button("Logout") {
                appState.isAuthenticated = false
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding()
            
            Text("This is a placeholder. Add account settings here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Account")
    }
}

#Preview {
        NavigationStack {
        AccountView()
    }
}

