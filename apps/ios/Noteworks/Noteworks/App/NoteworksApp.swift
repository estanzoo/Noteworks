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
    @StateObject private var notesStore = NotesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(notesStore)
                .onOpenURL { url in
                    Task {
                        try? await appState.supabaseClient.auth.session(from: url)
                    }
                }
        }
    }
}
