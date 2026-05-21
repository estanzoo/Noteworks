//
//  CourseSpaceView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI
import PencilKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Theme

private let textPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
private let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
private let textMuted = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
private let glassBorder = Color.white.opacity(0.5)
private let accent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)

// MARK: - Library View (matches React LibraryPage)

struct CourseSpaceView: View {
    @Binding var selectedTab: AppTab?
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: NotesStore
    @StateObject private var viewModel = CourseSpaceViewModel()
    @State private var activeTab: LibraryTab = .notes
    @State private var filterSubject: String? = nil
    @State private var showFilterDropdown = false
    @State private var navigateToNewNote = false
    @State private var newNoteId: String?
    @State private var showSearch = false
    @State private var showNotifications = false

    private var subjects: [String] {
        // Combine stored bubble names with any subjects that exist on notes
        // but were never explicitly added to the bubble list — keeps the
        // dropdown comprehensive even after edge cases.
        let stored = Set(store.bubbleNames.map { $0 })
        let fromNotes = Set(store.notes.compactMap { $0.subject }.filter { !$0.isEmpty })
        return stored.union(fromNotes).sorted()
    }

    private var filteredNotes: [Note] {
        let base: [Note]
        if let subject = filterSubject {
            let normalized = NotesStore.isLegacyOrphanSubject(subject)
                ? NotesStore.initialGuestBubbleName
                : subject
            if normalized.caseInsensitiveCompare(NotesStore.initialGuestBubbleName) == .orderedSame {
                base = store.notes.filter {
                    NotesStore.resolvedBubbleSubject($0.subject) == NotesStore.initialGuestBubbleName
                }
            } else {
                base = store.notes.filter {
                    $0.subject?.caseInsensitiveCompare(normalized) == .orderedSame
                }
            }
        } else {
            base = store.notes
        }
        // Bookmarked notes float to the top of the library, mirroring the
        // JSX `getSortedNotes` (L211). Stable order otherwise — the array
        // already comes back in insertion order from the store.
        return base.sorted { lhs, rhs in
            if lhs.bookmarked != rhs.bookmarked { return lhs.bookmarked && !rhs.bookmarked }
            return false
        }
    }

    private var title: String {
        if let subject = filterSubject {
            return "\(subject) · Library"
        }
        return "Library"
    }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Beta badge
                    LibraryBadgePill()
                        .padding(.top, 24)
                        .padding(.leading, 32)
                        .padding(.bottom, 12)

                    // Title row + top bar icons
                    HStack(alignment: .center) {
                        Text(title)
                            .font(.system(size: 40, weight: .bold))
                            .tracking(-0.02 * 40)
                            .foregroundStyle(textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Spacer()

                        HStack(spacing: 10) {
                            LibraryGlassIconButton(icon: "Icons/fluent_search-24-regular") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    showSearch = true
                                }
                            }

                            ZStack(alignment: .topTrailing) {
                                LibraryGlassIconButton(icon: "Icons/fluent_alert-24-regular") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showNotifications.toggle()
                                    }
                                }
                                if appState.notifications.unreadCount > 0 && !showNotifications {
                                    Text("\(appState.notifications.unreadCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(accent)
                                        .clipShape(Circle())
                                        .overlay { Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2) }
                                        .offset(x: 4, y: -4)
                                        .allowsHitTesting(false)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }

                            AppAvatarTopBarButton(
                                name: appState.profile?.displayName ?? "",
                                avatarUrl: appState.profile?.avatarUrl
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                    // Tab row + filter
                    HStack {
                        HStack(spacing: 0) {
                            // Tab container with glass pill
                            HStack(spacing: 0) {
                                LibraryTabButton(label: "NOTES", isActive: activeTab == .notes) {
                                    withAnimation(.easeInOut(duration: 0.2)) { activeTab = .notes }
                                }
                                LibraryTabButton(label: "ASSIGNMENTS", isActive: activeTab == .assignments) {
                                    withAnimation(.easeInOut(duration: 0.2)) { activeTab = .assignments }
                                }
                            }
                            .padding(3)
                            .background(Color.white.opacity(0.2))
                            .background(.ultraThinMaterial.opacity(0.3))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(glassBorder, lineWidth: 1)
                            }

                            // Active filter chip
                            if let subject = filterSubject {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { filterSubject = nil }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(subject)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(accent)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(accent)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(accent.opacity(0.1))
                                    .background(.ultraThinMaterial.opacity(0.3))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 12)
                            }
                        }

                        Spacer()

                        // Filter icon button only (dropdown is in a top-level overlay)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFilterDropdown.toggle()
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(showFilterDropdown ? accent : textPrimary)
                                .frame(width: 44, height: 44)
                                .background(
                                    showFilterDropdown
                                        ? accent.opacity(0.15)
                                        : Color.white.opacity(0.35)
                                )
                                .background(.ultraThinMaterial)
                                .clipShape(showFilterDropdown ? AnyShape(RoundedRectangle(cornerRadius: 12)) : AnyShape(Circle()))
                                .overlay {
                                    Group {
                                        if showFilterDropdown {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                                        } else {
                                            Circle().strokeBorder(glassBorder, lineWidth: 1)
                                        }
                                    }
                                }
                                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                    // Content
                    if !store.isReady {
                        libraryNotReadyPlaceholder
                    } else if activeTab == .notes {
                        notesGrid
                    } else {
                        assignmentsPlaceholder
                    }
                }
            }

            // Filter dropdown as a floating overlay (above everything)
            if showFilterDropdown {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showFilterDropdown = false
                        }
                    }

                VStack {
                    Spacer().frame(height: 178)
                    HStack {
                        Spacer()
                        LibraryFilterDropdown(
                            subjects: subjects,
                            selected: filterSubject,
                            onSelect: { subject in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    filterSubject = subject
                                    showFilterDropdown = false
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    .padding(.trailing, 32)
                    Spacer()
                }
                .zIndex(100)
            }
        }
        .overlay {
            if showNotifications {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showNotifications = false }
                    }
                VStack {
                    HStack {
                        Spacer()
                        NotificationDropdown(
                            store: appState.notifications,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) { showNotifications = false }
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
        .overlay {
            if showSearch {
                SearchPopupView(
                    isPresented: $showSearch,
                    onSelectCommunityPost: { post in
                        // Hand off to Community tab — the detail popup
                        // already lives there, so we just hop tabs and
                        // let `CommunityView` open it.
                        appState.pendingCommunityPost = post
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedTab = .people
                        }
                    },
                    onSelectLocalNote: { note in
                        // Reuse the existing `navigateToNewNote` plumbing
                        // — same nav destination, just driven from search
                        // instead of the FAB.
                        newNoteId = note.id
                        navigateToNewNote = true
                    }
                )
                    .transition(.opacity)
                    .zIndex(60)
            }
        }
        .navigationDestination(for: String.self) { noteId in
            NoteEditorView(noteId: noteId)
        }
        .navigationDestination(isPresented: $navigateToNewNote) {
            NoteEditorView(noteId: newNoteId)
        }
        .navigationBarHidden(true)
        .onAppear { adoptHomeBubbleFilterIfNeeded() }
        .onChange(of: store.libraryFilter) { _, _ in
            adoptHomeBubbleFilterIfNeeded()
        }
    }

    /// When the user taps a bubble on Home, `store.libraryFilter` is set
    /// before the tab switch fires. Pull it into local state once on appear
    /// (and clear the store-level filter) so subsequent in-library
    /// dropdown changes don't fight the home-driven selection.
    private func adoptHomeBubbleFilterIfNeeded() {
        guard let pending = store.libraryFilter else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            filterSubject = pending
        }
        resolveCourseIfNeeded(for: pending)
        store.libraryFilter = nil
    }

    private func resolveCourseIfNeeded(for subject: String?) {
        guard let subject,
              let accessToken = appState.accessToken,
              !accessToken.isEmpty else { return }
        let bubble = store.bubble(named: subject)
        guard bubble?.courseId == nil else { return }
        Task {
            do {
                let response = try await CourseResolutionService.shared.resolveCourse(
                    code: bubble?.courseCode ?? subject,
                    name: subject,
                    accessToken: accessToken
                )
                await MainActor.run {
                    store.setCourseMetadata(
                        forBubbleNamed: subject,
                        courseId: response.id,
                        courseCode: response.code
                    )
                }
            } catch {
                #if DEBUG
                print("[CourseResolution] Failed to resolve library subject '\(subject)': \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Placeholder while the store has no active user

    private var libraryNotReadyPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(textPrimary.opacity(0.5))
            Text("Loading your library…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(textSecondary)
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Notes grid (max 3 columns)

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)
    }

    private var notesGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 20) {
            // + New card always available so an empty bubble can grow notes.
            LibraryNewCard(
                subjectForDraft: {
                    guard let subject = filterSubject else {
                        return NotesStore.initialGuestBubbleName
                    }
                    if NotesStore.isLegacyOrphanSubject(subject) {
                        return NotesStore.initialGuestBubbleName
                    }
                    return subject
                }(),
                onNavigateToNewNote: { id in
                    newNoteId = id
                    navigateToNewNote = true
                }
            )

            ForEach(filteredNotes) { note in
                NavigationLink(value: note.id) {
                    LibraryNoteCard(note: note)
                }
                .buttonStyle(CardPressStyle())
                .contextMenu {
                    Button(role: .destructive) {
                        store.deleteNote(id: note.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 120)
        .overlay(alignment: .top) {
            if filteredNotes.isEmpty {
                Text("No notes in this category yet — tap + to start one.")
                    .font(.system(size: 15))
                    .foregroundStyle(textMuted)
                    .padding(.top, 280)
            }
        }
    }

    // MARK: - Assignments placeholder

    private var assignmentsPlaceholder: some View {
        VStack {
            Spacer(minLength: 100)
            Text("Assignments coming soon.")
                .font(.system(size: 17))
                .foregroundStyle(textMuted)
            Spacer(minLength: 100)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Library Tab Enum

private enum LibraryTab {
    case notes, assignments
}

// MARK: - Badge Pill

private struct LibraryBadgePill: View {
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

// MARK: - Glass Icon Button

private struct LibraryGlassIconButton: View {
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
        .tint(textPrimary)
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

// MARK: - Tab Button

private struct LibraryTabButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.02 * 14)
                .foregroundStyle(isActive ? textPrimary : textMuted)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    isActive
                        ? Color.white.opacity(0.6)
                        : Color.clear
                )
                .clipShape(Capsule())
                .shadow(
                    color: isActive ? .black.opacity(0.06) : .clear,
                    radius: 3, y: 1
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Dropdown

private struct LibraryFilterDropdown: View {
    let subjects: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    private var allOptions: [String] {
        subjects + ["Uncategorized"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // All notes option
            FilterOptionRow(label: "All notes", isSelected: selected == nil, isBold: true) {
                onSelect(nil)
            }

            Divider()
                .padding(.horizontal, 20)

            Text("All notes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textMuted)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(allOptions, id: \.self) { subject in
                FilterOptionRow(label: subject, isSelected: selected == subject, isBold: false) {
                    onSelect(subject)
                }
            }

            Spacer().frame(height: 8)
        }
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.7))
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(glassBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 24, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

private struct FilterOptionRow: View {
    let label: String
    let isSelected: Bool
    let isBold: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(textPrimary)
                        .frame(width: 18)
                } else {
                    Spacer().frame(width: 18)
                }

                Text(label)
                    .font(.system(size: 17, weight: isBold ? .semibold : .regular))
                    .foregroundStyle(textPrimary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Note Card (React NoteCard)

private struct LibraryNoteCard: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title + tag
            HStack(alignment: .top) {
                Text(note.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                HStack(alignment: .center, spacing: 8) {
                    // Bookmark chip — mirrors the Library mock: small
                    // rounded square, desaturated blue fill, solid accent
                    // bookmark immediately left of the course pill.
                    if note.bookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(accent.opacity(0.14))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(accent.opacity(0.2), lineWidth: 1)
                            }
                    }

                    // Corner pill: every note belongs to a bubble — orphan
                    // notes roll up to Untitled Bubble.
                    if let badge = note.displayBadge {
                        Text(badge)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.4))
                            .background(.ultraThinMaterial.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(glassBorder, lineWidth: 1)
                            }
                    }
                }
            }
            .padding(.bottom, 12)

            // Date
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(textMuted)
                Text(note.formattedDate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textMuted)
            }
            .padding(.bottom, 4)

            // Pages
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.system(size: 12))
                    .foregroundStyle(textMuted)
                Text("\(note.pageCount) PAGES")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textMuted)
            }

            Spacer(minLength: 16)

            // Shared by
            if let shared = note.sharedBy, !shared.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 12))
                        .foregroundStyle(textMuted)
                    Text("Shared by \(shared)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textMuted)
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(minHeight: 200, alignment: .topLeading)
        .background {
            // Outer gradient ring
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

// MARK: - New Card (+)

@ViewBuilder
private func libraryNewNoteMenuRow(title: String, detail: String, systemImage: String) -> some View {
    HStack(alignment: .center, spacing: 12) {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LibraryNewCard: View {
    @EnvironmentObject private var store: NotesStore
    let subjectForDraft: String?
    let onNavigateToNewNote: (String) -> Void

    @State private var showCreateMenu = false
    @State private var showPDFImporter = false
    @State private var importErrorMessage: String?
    @State private var showImportError = false

    private var newCardChrome: some View {
        VStack {
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
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

    var body: some View {
        ZStack(alignment: .center) {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    showCreateMenu.toggle()
                }
            } label: {
                newCardChrome
            }
            .buttonStyle(CardPressStyle())

            if showCreateMenu {
                createMenu
                    .frame(width: 258)
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .zIndex(showCreateMenu ? 20 : 0)
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let id = try importPDFIntoNewNote(from: url, subject: subjectForDraft, store: store)
                        onNavigateToNewNote(id)
                    } catch {
                        importErrorMessage = error.localizedDescription
                        showImportError = true
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
            }
        }
        .alert("Could not import", isPresented: $showImportError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(importErrorMessage ?? "Unknown error.")
        })
    }

    private var createMenu: some View {
        VStack(spacing: 10) {
            createOption(
                title: "Blank note",
                detail: "Start with an empty page",
                systemImage: "doc.text"
            ) {
                showCreateMenu = false
                let note = store.createDraftNote(subject: subjectForDraft)
                onNavigateToNewNote(note.id)
            }

            createOption(
                title: "Import from device",
                detail: "Open a local file as a note",
                systemImage: "tray.and.arrow.up"
            ) {
                showCreateMenu = false
                showPDFImporter = true
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.78))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(glassBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.09), radius: 18, x: 0, y: 10)
    }

    private func createOption(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255))
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255).opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255).opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(textPrimary)
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(CardPressStyle())
    }
}

// MARK: - PDF → note import (Library)

private enum PDFLibraryImportError: LocalizedError {
    case unreadable
    case empty
    case renderFailed(page: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "That file could not be read as a PDF."
        case .empty:
            return "The PDF has no pages."
        case .renderFailed(let page):
            return "Could not render page \(page)."
        }
    }
}

@MainActor
private func renderPDFPageImage(_ page: PDFPage) -> UIImage? {
    let media = page.bounds(for: .mediaBox)
    guard media.width > 0, media.height > 0 else { return nil }
    let pixelWidth: CGFloat = 2048
    let pixelHeight = pixelWidth * media.height / media.width
    let size = CGSize(width: pixelWidth, height: pixelHeight)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { ctx in
        UIColor.white.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.cgContext.saveGState()
        ctx.cgContext.translateBy(x: 0, y: size.height)
        ctx.cgContext.scaleBy(x: size.width / media.width, y: -size.height / media.height)
        page.draw(with: .mediaBox, to: ctx.cgContext)
        ctx.cgContext.restoreGState()
    }
}

/// Builds a new draft note with one canvas page per PDF page. Each PDF slice
/// becomes the page background so users can annotate above it with PencilKit.
@MainActor
private func importPDFIntoNewNote(from url: URL, subject: String?, store: NotesStore) throws -> String {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
        if accessing { url.stopAccessingSecurityScopedResource() }
    }
    guard let document = PDFDocument(url: url) else {
        throw PDFLibraryImportError.unreadable
    }
    let total = document.pageCount
    guard total > 0 else { throw PDFLibraryImportError.empty }

    let baseTitle = url.deletingPathExtension().lastPathComponent
    let note = store.createDraftNote(subject: subject, title: baseTitle.isEmpty ? "Imported PDF" : baseTitle)
    let noteId = note.id

    for _ in 1..<total {
        _ = store.addPage(noteId: noteId)
    }

    for index in 0..<total {
        guard let pdfPage = document.page(at: index) else {
            throw PDFLibraryImportError.renderFailed(page: index + 1)
        }
        guard let image = renderPDFPageImage(pdfPage), let data = image.pngData() else {
            throw PDFLibraryImportError.renderFailed(page: index + 1)
        }
        let filename = "\(UUID().uuidString).png"
        store.saveOverlayImageData(data, for: noteId, filename: filename)
        let pageNumber = index + 1
        let bounds = pdfPage.bounds(for: .mediaBox)
        let aspect = bounds.width > 0
            ? bounds.height / bounds.width
            : image.size.height / max(1, image.size.width)
        store.setPageBackgroundImage(
            noteId: noteId,
            page: pageNumber,
            filename: filename,
            aspectHeightOverWidth: aspect
        )
    }

    store.setCurrentPage(noteId: noteId, page: 1)
    return noteId
}

// MARK: - Card Press Style

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - AnyShape helper

private struct AnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        _path = { shape.path(in: $0) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

#Preview {
    let store = NotesStore.preview()
    NavigationStack {
        CourseSpaceView(selectedTab: .constant(AppTab.notebook))
            .environmentObject(AppState(notesStore: store))
            .environmentObject(store)
    }
}
