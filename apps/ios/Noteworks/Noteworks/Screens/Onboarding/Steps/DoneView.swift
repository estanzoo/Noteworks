//
//  DoneView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct DoneView: View {
    let name: String
    let onExplore: () -> Void
    @State private var visible = false

    var body: some View {
        VStack {
            Spacer()

            GlassCard {
                VStack(spacing: 0) {
                    // Checkmark circle
                    ZStack {
                        Circle()
                            .fill(OnboardingTheme.accent.opacity(0.12))
                            .frame(width: 72, height: 72)
                            .overlay {
                                Circle()
                                    .strokeBorder(OnboardingTheme.accent.opacity(0.25), lineWidth: 1.5)
                            }

                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.accent)
                    }
                    .padding(.bottom, 32)

                    // Title
                    (
                        Text("Let's Get To Work, ")
                            .foregroundStyle(OnboardingTheme.textPrimary)
                        +
                        Text(name.isEmpty ? "there" : name)
                            .foregroundStyle(OnboardingTheme.accent)
                    )
                    .font(.system(size: 34, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, 12)

                    Text("Your workspace is ready. Start creating, organizing, and collaborating.")
                        .font(.system(size: 17))
                        .foregroundStyle(OnboardingTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.bottom, 40)

                    // Explore button
                    Button(action: onExplore) {
                        Text("Explore Now!")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                            .background(OnboardingTheme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: OnboardingTheme.accent.opacity(0.4), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)

            Spacer()
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.97)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { visible = true }
        }
    }
}

// MARK: - Sign-In Done View

struct SignInDoneView: View {
    let email: String
    let onContinue: () -> Void
    @State private var visible = false

    private var displayName: String {
        let prefix = email.components(separatedBy: "@").first ?? ""
        return prefix.isEmpty ? "there" : prefix
    }

    var body: some View {
        VStack {
            Spacer()

            GlassCard {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(OnboardingTheme.accent.opacity(0.12))
                            .frame(width: 72, height: 72)
                            .overlay {
                                Circle()
                                    .strokeBorder(OnboardingTheme.accent.opacity(0.25), lineWidth: 1.5)
                            }

                        Image(systemName: "hand.wave.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(OnboardingTheme.accent)
                    }
                    .padding(.bottom, 32)

                    (
                        Text("Welcome Back, ")
                            .foregroundStyle(OnboardingTheme.textPrimary)
                        +
                        Text(displayName)
                            .foregroundStyle(OnboardingTheme.accent)
                    )
                    .font(.system(size: 34, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, 12)

                    Text("Good to see you again. Your notes are right where you left them.")
                        .font(.system(size: 17))
                        .foregroundStyle(OnboardingTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.bottom, 40)

                    Button(action: onContinue) {
                        Text("Let's Go!")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                            .background(OnboardingTheme.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: OnboardingTheme.accent.opacity(0.4), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 20)

            Spacer()
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.97)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { visible = true }
        }
    }
}

// MARK: - Skipped View

struct SkippedView: View {
    let onComplete: () -> Void
    @State private var visible = false

    var body: some View {
        VStack {
            Spacer()
            Text("Redirecting to home...")
                .font(.system(size: 17))
                .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.4))
            Spacer()
        }
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onComplete()
            }
        }
    }
}
