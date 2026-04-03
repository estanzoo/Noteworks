//
//  WelcomeView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct WelcomeView: View {
    let onSignUp: () -> Void
    let onSignIn: () -> Void
    let onSkip: () -> Void
    @State private var visible = false

    var body: some View {
        ZStack {
            // Skip button (top right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: onSkip) {
                        Text("Skip, set up later")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(OnboardingTheme.textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                    .padding(.top, 24)
                }
                Spacer()
            }

            // Main content
            VStack(spacing: 0) {
                Spacer()

                BetaBadge()
                    .padding(.bottom, 40)

                Text("Welcome to ")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                +
                Text("NoteWorks")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accent)

                Text("Turn isolated notes into collective mastery.")
                    .font(.system(size: 17))
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.bottom, 48)

                GlassCard {
                    VStack(spacing: 10) {
                        // Sign Up button
                        Button(action: onSignUp) {
                            Text("Sign up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(OnboardingTheme.accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: OnboardingTheme.accent.opacity(0.35), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)

                        // Google button
                        Button(action: onSignUp) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 18))
                                Text("Google")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .foregroundStyle(OnboardingTheme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)

                        // Apple button
                        Button(action: onSignUp) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 16))
                                Text("Apple")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .foregroundStyle(OnboardingTheme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 400)
                .padding(.horizontal, 20)

                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.4))
                    Button("Go sign-in", action: onSignIn)
                        .foregroundStyle(OnboardingTheme.accent)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15))
                .padding(.top, 28)

                Spacer()
            }
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { visible = true }
        }
    }
}
