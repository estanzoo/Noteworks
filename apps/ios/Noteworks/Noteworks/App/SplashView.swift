//
//  SplashView.swift
//  Noteworks
//
//  Shown while `AppState.bootstrap()` is restoring the persisted Supabase
//  session and fetching the current user's profile. Kept intentionally
//  minimal so cold launch never flashes Welcome under an already-logged-in
//  user.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            OnboardingBackground()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Noteworks")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.02 * 32)
                    .foregroundStyle(.primary)

                ProgressView()
                    .controlSize(.regular)
                    .tint(.primary.opacity(0.7))
            }
        }
    }
}

#Preview {
    SplashView()
}
