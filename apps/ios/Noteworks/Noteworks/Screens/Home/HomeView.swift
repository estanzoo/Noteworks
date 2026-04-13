//
//  HomeView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

// MARK: - Theme (matches React TEXT_PRIMARY, TEXT_MUTED, GLASS_BORDER, ACCENT)

private let textPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
private let textMuted = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
private let glassBorder = Color.white.opacity(0.5)
private let accent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)

// MARK: - Model

struct CourseBubble: Identifiable {
    let id = UUID()
    let name: String
    let noteCount: Int
    let size: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
}

// MARK: - HomeView

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @StateObject private var viewModel = HomeViewModel()
    @State private var bubblesVisible = false
    @State private var showAccountView = false

    private let courses: [CourseBubble] = [
        CourseBubble(name: "Biology",     noteCount: 4,  size: 160, offsetX: -0.25, offsetY: -0.25),
        CourseBubble(name: "Art",         noteCount: 2,  size: 140, offsetX:  0.10, offsetY: -0.28),
        CourseBubble(name: "Physics",     noteCount: 1,  size: 130, offsetX:  0.38, offsetY: -0.20),
        CourseBubble(name: "Chemistry",   noteCount: 4,  size: 150, offsetX:  0.05, offsetY:  0.08),
        CourseBubble(name: "Unnamed",     noteCount: 8,  size: 170, offsetX: -0.38, offsetY:  0.12),
        CourseBubble(name: "Mathematics", noteCount: 10, size: 165, offsetX:  0.30, offsetY:  0.15),
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OnboardingBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Badge
                BadgePill()
                    .padding(.top, 24)
                    .padding(.leading, 32)
                    .padding(.bottom, 12)

                // Title row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NoteWorks")
                            .font(.custom("Inter_24pt-Medium", size: 40).weight(.bold))
                            .tracking(-0.02 * 40)
                            .foregroundStyle(textPrimary)
                        Text("BUBBLES OF THOUGHT")
                            .font(.custom("Inter_24pt-Medium", size: 13).weight(.semibold))
                            .tracking(0.15 * 13)
                            .textCase(.uppercase)
                            .foregroundStyle(textMuted)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        GlassIconButton(icon: "Icons/fluent_search-24-regular")
                        GlassIconButton(icon: "Icons/fluent_alert-24-regular")
                        GlassIconButton(icon: "Icons/fluent_person-24-regular") {
                            showAccountView = true
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

                // Bubble field
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = .notebook
                                }
                            } label: {
                                BubbleView(course: course)
                            }
                            .buttonStyle(BubblePressStyle())
                            .position(
                                x: geo.size.width / 2 + course.offsetX * geo.size.width,
                                y: geo.size.height / 2 + course.offsetY * geo.size.height
                            )
                            .scaleEffect(bubblesVisible ? 1 : 0.6)
                            .opacity(bubblesVisible ? 1 : 0)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.6)
                                    .delay(Double(index) * 0.08),
                                value: bubblesVisible
                            )
                        }
                    }
                }
            }

            // FAB
            GlassIconButton(icon: "Icons/fluent_add-32-filled")
                .padding(.trailing, 32)
                .padding(.bottom, 100)
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showAccountView) {
            AccountView()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                bubblesVisible = true
            }
        }
    }
}

// MARK: - Badge pill (React: Badge component)

private struct BadgePill: View {
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

// MARK: - Glass icon button (React: GlassIconBtn — 44×44, circle, glass)

private struct GlassIconButton: View {
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

// MARK: - Bubble press style (React: scale 0.95 on press)

private struct BubblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Bubble (React: BubbleItem — glass circle with gradient + backdrop blur)

struct BubbleView: View {
    let course: CourseBubble

    private var titleSize: CGFloat {
        max(16, course.size * 0.09)
    }

    var body: some View {
        ZStack {
            // Glass circle (React: linear-gradient 145deg, backdrop-filter blur(30) saturate(1.5))
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.45),
                            Color.white.opacity(0.15)
                        ],
                        startPoint: UnitPoint(x: 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                )
                .frame(width: course.size, height: course.size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: course.size, height: course.size)
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                }
                // React: inset 0 0.5px 0 rgba(255,255,255,0.7)
                .shadow(color: Color.white.opacity(0.7), radius: 0, x: 0, y: -0.5)
                // React: 0 0 0 0.5px rgba(255,255,255,0.3)
                .shadow(color: Color.white.opacity(0.3), radius: 0.25)
                // React: 0 8px 32px rgba(0,0,0,0.05)
                .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 8)

            // Content
            VStack(spacing: 4) {
                Text(course.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Image("Icons/fluent_notebook-24-regular")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(textMuted)

                    Text("\(course.noteCount) \(course.noteCount == 1 ? "Note" : "Notes")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textMuted)
                }
            }
            .padding(12)
            .frame(width: course.size)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(selectedTab: .constant(.home))
    }
}
