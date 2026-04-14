//
//  HomeView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @StateObject private var viewModel = HomeViewModel()

    @State private var bubblesVisible = false
    @State private var showAccountView = false
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var notifications = HomeNotification.samples

    private var unreadCount: Int {
        notifications.filter(\.unread).count
    }

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
                HomeBadgePill()
                    .padding(.top, 24)
                    .padding(.leading, 32)
                    .padding(.bottom, 12)

                titleRow
                bubbleField
            }

            HomeGlassIconButton(icon: "Icons/fluent_add-32-filled")
                .padding(.trailing, 32)
                .padding(.bottom, 100)
        }
        .overlay { notificationOverlay }
        .overlay { searchOverlay }
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

    // MARK: - Title Row

    private var titleRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NoteWorks")
                    .font(.custom("Inter_24pt-Medium", size: 40).weight(.bold))
                    .tracking(-0.02 * 40)
                    .foregroundStyle(HomeTheme.textPrimary)
                Text("BUBBLES OF THOUGHT")
                    .font(.custom("Inter_24pt-Medium", size: 13).weight(.semibold))
                    .tracking(0.15 * 13)
                    .textCase(.uppercase)
                    .foregroundStyle(HomeTheme.textMuted)
            }

            Spacer()

            HStack(spacing: 10) {
                HomeGlassIconButton(icon: "Icons/fluent_search-24-regular") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showSearch = true
                    }
                }

                ZStack(alignment: .topTrailing) {
                    HomeGlassIconButton(
                        icon: "Icons/fluent_alert-24-regular",
                        isActive: showNotifications
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNotifications.toggle()
                        }
                    }

                    if unreadCount > 0 && !showNotifications {
                        Text("\(unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(HomeTheme.accent)
                            .clipShape(Circle())
                            .overlay {
                                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                            }
                            .offset(x: 4, y: -4)
                            .allowsHitTesting(false)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                HomeGlassIconButton(icon: "Icons/fluent_person-24-regular") {
                    showAccountView = true
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    // MARK: - Bubble Field

    private var bubbleField: some View {
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

    // MARK: - Search Overlay

    @ViewBuilder
    private var searchOverlay: some View {
        if showSearch {
            SearchPopupView(isPresented: $showSearch)
                .transition(.opacity)
                .zIndex(100)
        }
    }

    // MARK: - Notification Overlay

    @ViewBuilder
    private var notificationOverlay: some View {
        if showNotifications {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNotifications = false
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    NotificationDropdown(
                        notifications: $notifications,
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showNotifications = false
                            }
                        }
                    )
                }
                .padding(.top, 130)
                .padding(.trailing, 32)
                Spacer()
            }
            .transition(.opacity)
            .zIndex(50)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(selectedTab: .constant(.home))
    }
}
