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
            if appState.isBootstrapping {
                // Cold-launch restore in flight — never flash Welcome
                // under a returning user.
                SplashView()
            } else if appState.profile?.hasCompletedOnboarding == true || appState.isGuestMode {
                // Real signed-in user with completed onboarding, OR a
                // guest who tapped "Skip, set up later" — both go to
                // the main tab view. Guest mode just means there's no
                // `profile` / `accessToken` underneath; the local-only
                // surfaces still work, and any server-backed feature
                // surfaces a sign-in prompt as it already does today.
                MainTabView()
            } else {
                // Single OnboardingFlow position keeps SwiftUI view identity
                // stable across `isAuthenticated` transitions: when the user
                // signs in or signs up, `handleAuthResult` flips
                // `isAuthenticated`, but ContentView stays in this branch
                // until the profile reports `onboarding_completed_at`, so
                // the OnboardingFlow's @State and @StateObject survive.
                OnboardingFlow(
                    startAt: appState.resumeOnboardingAtCollege ? .college : .welcome
                )
            }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    let notesStore = NotesStore.preview()
    return ContentView()
        .environmentObject(AppState(notesStore: notesStore))
        .environmentObject(notesStore)
}
