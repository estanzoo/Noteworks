//
//  HomeView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

// MARK: - Model

struct CourseBubble: Identifiable {
    let id = UUID()
    let name: String
    let noteCount: Int
    let size: CGFloat          // diameter of the bubble
    let offsetX: CGFloat       // relative offset from center (-0.5 to 0.5 of canvas width)
    let offsetY: CGFloat       // relative offset from center (-0.5 to 0.5 of canvas height)
}

// MARK: - HomeView

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @StateObject private var viewModel = HomeViewModel()

    // Sample data — replace with real data later
    private let courses: [CourseBubble] = [
        CourseBubble(name: "Biology",    noteCount: 4,  size: 160, offsetX: -0.25, offsetY: -0.25),
        CourseBubble(name: "Art",        noteCount: 2,  size: 140, offsetX:  0.10, offsetY: -0.28),
        CourseBubble(name: "Physics",    noteCount: 1,  size: 130, offsetX:  0.38, offsetY: -0.20),
        CourseBubble(name: "Chemistry",  noteCount: 4,  size: 150, offsetX:  0.05, offsetY:  0.08),
        CourseBubble(name: "Unnamed",    noteCount: 8,  size: 170, offsetX: -0.38, offsetY:  0.12),
        CourseBubble(name: "Mathematics",noteCount: 10, size: 165, offsetX:  0.30, offsetY:  0.15),
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Background
            Color(white: 0.94)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HomeNavBar()

                // Bubble canvas
                GeometryReader { geo in
                    ZStack {
                        ForEach(courses) { course in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = .notebook
                                }
                            } label: {
                                BubbleView(course: course)
                            }
                            .buttonStyle(.plain)
                            .position(
                                x: geo.size.width  / 2 + course.offsetX * geo.size.width,
                                y: geo.size.height / 2 + course.offsetY * geo.size.height
                            )
                        }
                    }
                }
            }

            // FAB — add new course
            Button {
                // TODO: Add new course action
            } label: {
                Image("Icons/fluent_add-32-filled")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color.primary)
                    .frame(width: 56, height: 56)
                    .background(Color(white: 0.97))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 32)
            .padding(.bottom, 100) // above tab bar
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Top Nav Bar

struct HomeNavBar: View {
    var body: some View {
        HStack(alignment: .center) {
            // Title + tagline — Figma: 246×44, top: 68, left: 32, opacity: 0.9
            // Inter font — add Inter-Medium.ttf to the project to activate custom font
            VStack(alignment: .leading, spacing: 2) {
                Text("NoteWorks")
                    .font(.custom("Inter_24pt-Medium", size: 36).leading(.tight))
                    .tracking(36 * 0.05)          // letter-spacing 5%
                    .foregroundStyle(Color.primary)
                Text("BUBBLES OF THOUGHT")
                    .font(.custom("Inter_24pt-Medium", size: 12).leading(.tight))
                    .tracking(12 * 0.15)          // letter-spacing 15%
                    .textCase(.uppercase)
                    .foregroundStyle(Color.secondary)
            }
            .frame(width: 246, height: 44, alignment: .leading)
            .opacity(0.9)

            Spacer()

            // Right actions — 44×44 hit targets, gap 12, pill background
            HStack(spacing: 12) {
                NavBarIconButton(icon: "Icons/fluent_search-24-regular")
                NavBarIconButton(icon: "Icons/fluent_alert-24-regular")

                // Study Mode pill button
                Button {
                    // TODO: toggle study mode
                } label: {
                    Text("Study Mode")
                        .font(.custom("Inter_24pt-Medium", size: 13).leading(.tight))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color(white: 0.90))
                        .clipShape(Capsule())
                }

                NavBarIconButton(icon: "Icons/fluent_person-24-regular")
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(white: 0.94))
    }
}

// MARK: - Reusable nav bar icon button (44×44 pill)

struct NavBarIconButton: View {
    let icon: String

    var body: some View {
        Button {
            // action handled by parent
        } label: {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)           // 44×44 tap target
                .background(Color(white: 0.90))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bubble

struct BubbleView: View {
    let course: CourseBubble

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.90))
                .frame(width: course.size, height: course.size)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)

            VStack(spacing: 6) {
                Text(course.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Image("Icons/fluent_notebook-24-regular")
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                        .foregroundStyle(Color.secondary)

                    Text("\(course.noteCount) \(course.noteCount == 1 ? "Note" : "Notes")")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.secondary)
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
