//
//  CommunityView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

// MARK: - Theme

private let textPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
private let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
private let textMuted = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
private let glassBorder = Color.white.opacity(0.5)
private let accent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)

// MARK: - Community View (matches React CommunityPage)

struct CommunityView: View {
    @StateObject private var viewModel = CommunityViewModel()
    @State private var activeTab: CommunityTab = .post
    @State private var showAccountView = false

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Beta badge
                    CommunityBadgePill()
                        .padding(.top, 24)
                        .padding(.leading, 32)
                        .padding(.bottom, 12)

                    // Title row + top bar icons
                    HStack(alignment: .center) {
                        Text("Community")
                            .font(.system(size: 40, weight: .bold))
                            .tracking(-0.02 * 40)
                            .foregroundStyle(textPrimary)

                        Spacer()

                        HStack(spacing: 10) {
                            CommunityGlassIconButton(icon: "Icons/fluent_search-24-regular")
                            CommunityGlassIconButton(icon: "Icons/fluent_alert-24-regular")
                            CommunityGlassIconButton(icon: "Icons/fluent_person-24-regular") {
                                showAccountView = true
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                    // Post / Note tab switcher
                    HStack(spacing: 0) {
                        CommunityTabButton(label: "POST", isActive: activeTab == .post) {
                            withAnimation(.easeInOut(duration: 0.2)) { activeTab = .post }
                        }
                        CommunityTabButton(label: "NOTE", isActive: activeTab == .note) {
                            withAnimation(.easeInOut(duration: 0.2)) { activeTab = .note }
                        }
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.2))
                    .background(.ultraThinMaterial.opacity(0.3))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(glassBorder, lineWidth: 1)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)

                    // Content
                    if activeTab == .post {
                        postContent
                    } else {
                        notePlaceholder
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showAccountView) {
            AccountView()
        }
        .navigationBarHidden(true)
    }

    // MARK: - Post content (masonry-style with 3 columns)

    private var postContent: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3),
            spacing: 20
        ) {
            // New post card
            PostNewCardView()

            // Post cards
            ForEach(viewModel.posts) { post in
                PostCardView(post: post)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
    }

    // MARK: - Note placeholder

    private var notePlaceholder: some View {
        VStack {
            Spacer(minLength: 100)
            Text("Shared notes coming soon.")
                .font(.system(size: 17))
                .foregroundStyle(textMuted)
            Spacer(minLength: 100)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tab Enum

private enum CommunityTab {
    case post, note
}

// MARK: - Badge

private struct CommunityBadgePill: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 11, weight: .bold))
            .tracking(0.06 * 11)
            .foregroundStyle(Color(red: 0x7A/255, green: 0x8A/255, blue: 0x96/255))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.45))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Glass Icon Button (with optional action)

private struct CommunityGlassIconButton: View {
    let icon: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundStyle(textPrimary)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.35))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(glassBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Button

private struct CommunityTabButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.02 * 14)
                .foregroundStyle(isActive ? textPrimary : textMuted)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(isActive ? Color.white.opacity(0.6) : Color.clear)
                .clipShape(Capsule())
                .shadow(
                    color: isActive ? .black.opacity(0.06) : .clear,
                    radius: 3, y: 1
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Post New Card (React PostNewCard)

private struct PostNewCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // User row
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("User name")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Text("Your school\nYour major")
                        .font(.system(size: 12))
                        .foregroundStyle(textMuted)
                        .lineSpacing(2)
                }
            }
            .padding(.bottom, 20)

            // Placeholder fields
            Text("Please enter the title...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.bottom, 12)

            Text("Type the text here...")
                .font(.system(size: 14))
                .foregroundStyle(textMuted)

            Spacer(minLength: 40)

            // Bottom row
            HStack {
                Text("# topic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 16))
                        .foregroundStyle(textMuted)
                    Image(systemName: "heart")
                        .font(.system(size: 16))
                        .foregroundStyle(textMuted)
                }
            }
        }
        .padding(24)
        .frame(minHeight: 280, alignment: .topLeading)
        .modifier(GlassCardModifier())
    }
}

// MARK: - Post Card (React PostCard)

private struct PostCardView: View {
    let post: CommunityPost

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // User row
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.user)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Text("\(post.school)\n\(post.major)")
                        .font(.system(size: 12))
                        .foregroundStyle(textMuted)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 16)

            // Title
            Text(post.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(textPrimary)
                .lineLimit(3)
                .padding(.bottom, post.body != nil ? 8 : 0)

            // Body
            if let body = post.body {
                Text(body)
                    .font(.system(size: 14))
                    .foregroundStyle(textSecondary)
                    .lineLimit(4)
                    .lineSpacing(3)
            }

            Spacer(minLength: 16)

            // Bottom row: tags + stats
            HStack(alignment: .center) {
                // Tags
                HStack(spacing: 6) {
                    ForEach(Array(Set(post.tags)), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Spacer()

                // Stats
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 14))
                            .foregroundStyle(textMuted)
                        Text("\(post.comments)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textMuted)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.system(size: 14))
                            .foregroundStyle(textMuted)
                        Text("\(post.likes)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textMuted)
                    }
                }
            }
        }
        .padding(24)
        .frame(minHeight: 200, alignment: .topLeading)
        .modifier(GlassCardModifier())
    }
}

// MARK: - Reusable glass card modifier

private struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(-1)
            }
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.2),
                                Color(red: 245/255, green: 248/255, blue: 252/255).opacity(0.3)
                            ],
                            startPoint: UnitPoint(x: 0.15, y: 0),
                            endPoint: UnitPoint(x: 0.85, y: 1)
                        )
                    )
            }
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(glassBorder, lineWidth: 1)
            }
            .shadow(color: .white.opacity(0.6), radius: 0, x: 0, y: -0.5)
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

// MARK: - Card Press Style

private struct CommunityCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        CommunityView()
    }
}
