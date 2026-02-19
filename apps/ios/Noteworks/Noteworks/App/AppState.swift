//
//  AppState.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    init() {
        // TODO: Check if user is already logged in (from Keychain)
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        // TODO: Load from Keychain/AuthService
        // For now, default to false
        isAuthenticated = false
    }
}

// Placeholder User model - move to Shared/Models/User.swift later
struct User {
    let id: String
    let email: String
}

