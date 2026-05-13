//
//  NoteworksApp.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//

import SwiftUI

@main
struct NoteworksApp: App {
    @StateObject private var appState: AppState
    @StateObject private var notesStore: NotesStore

    init() {
        // Single composition root: AppState owns NotesStore and the auth
        // service, but both are still exposed as environment objects so
        // existing views (CourseSpaceView, NoteEditorView, etc.) keep
        // their `@EnvironmentObject` access.
        let store = NotesStore()
        _notesStore = StateObject(wrappedValue: store)
        _appState = StateObject(wrappedValue: AppState(notesStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(notesStore)
                .task {
                    // Cold-launch session restore. `ContentView` is showing
                    // `SplashView` until `isBootstrapping` flips false.
                    await appState.bootstrap()
                }
                .onOpenURL { url in
                    Task {
                        try? await appState.supabaseClient.auth.session(from: url)
                    }
                }
        }
    }
}
