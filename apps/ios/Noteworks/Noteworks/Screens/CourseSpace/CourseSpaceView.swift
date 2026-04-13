//
//  CourseSpaceView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI
import PencilKit

// MARK: - Theme

private let textPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
private let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
private let textMuted = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
private let glassBorder = Color.white.opacity(0.5)
private let accent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)

// MARK: - Library View (matches React LibraryPage)

struct CourseSpaceView: View {
    @StateObject private var viewModel = CourseSpaceViewModel()
    @State private var activeTab: LibraryTab = .notes
    @State private var filterSubject: String? = nil
    @State private var showFilterDropdown = false
    @State private var navigateToNewNote = false
    @State private var newNoteId: String?
    @State private var showAccountView = false

    private var subjects: [String] {
        let raw = viewModel.notes.compactMap { $0.subject }.filter { !$0.isEmpty }
        return Array(Set(raw)).sorted()
    }

    private var filteredNotes: [NoteItem] {
        guard let subject = filterSubject else { return viewModel.notes }
        if subject == "Uncategorized" {
            return viewModel.notes.filter { $0.subject == nil || $0.subject?.isEmpty == true }
        }
        return viewModel.notes.filter { $0.subject == subject }
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
                            LibraryGlassIconButton(icon: "Icons/fluent_search-24-regular")
                            LibraryGlassIconButton(icon: "Icons/fluent_alert-24-regular")
                            LibraryGlassIconButton(icon: "Icons/fluent_person-24-regular") {
                                showAccountView = true
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
                    if activeTab == .notes {
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
        .navigationDestination(for: String.self) { noteId in
            NoteEditorView(noteId: noteId)
        }
        .navigationDestination(isPresented: $navigateToNewNote) {
            NoteEditorView(noteId: newNoteId)
        }
        .navigationDestination(isPresented: $showAccountView) {
            AccountView()
        }
        .navigationBarHidden(true)
    }

    // MARK: - Notes grid (max 3 columns)

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)
    }

    private var notesGrid: some View {
        Group {
            if filteredNotes.isEmpty {
                VStack {
                    Spacer(minLength: 80)
                    Text("No notes in this category.")
                        .font(.system(size: 17))
                        .foregroundStyle(textMuted)
                    Spacer(minLength: 80)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    // + New card
                    LibraryNewCard {
                        let id = viewModel.createNote()
                        newNoteId = id
                        navigateToNewNote = true
                    }

                    ForEach(filteredNotes) { note in
                        NavigationLink(value: note.id) {
                            LibraryNoteCard(note: note)
                        }
                        .buttonStyle(CardPressStyle())
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 120)
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
        .buttonStyle(.plain)
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
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title + tag
            HStack(alignment: .top) {
                Text(note.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(2)

                Spacer()

                if let tag = note.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textSecondary)
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

private struct LibraryNewCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .buttonStyle(CardPressStyle())
    }
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
    private let _path: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        _path = { shape.path(in: $0) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

#Preview {
    NavigationStack {
        CourseSpaceView()
    }
}
