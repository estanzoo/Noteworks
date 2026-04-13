//
//  NoteworksApp.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//

import SwiftUI

@main
struct NoteworksApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    Task {
                        try? await appState.supabaseClient.auth.session(from: url)
                    }
                }
        }
    }
}
