//
//  SearchPopupView.swift
//  Noteworks
//

import SwiftUI

// MARK: - Search Popup

struct SearchPopupView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: NotesStore
    @State private var query = ""
    @State private var searchTab: SearchTab = .yours
    @FocusState private var focused: Bool

    private static let suggestions = [
        "Boolean operators",
        "Subject terms",
        "Refine results",
        "Citation searching",
    ]

    private enum SearchTab {
        case yours, community
    }

    /// Search hits read live from `NotesStore.notes`. Matches title or
    /// subject substring (case-insensitive); empty query returns no
    /// rows so the suggestions panel shows instead. Community tab is
    /// not wired to the server yet — returns empty for that tab so
    /// brand-new users don't see fake hardcoded hits.
    private var results: [(title: String, subject: String?)] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        guard searchTab == .yours else { return [] }
        let q = query.lowercased()
        return store.notes
            .filter {
                $0.title.lowercased().contains(q) ||
                ($0.subject ?? "").lowercased().contains(q)
            }
            .map { ($0.title, $0.subject) }
    }

    var body: some View {
        ZStack {
            // Blurred scrim over the home content
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.1))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Glass search panel — pinned to upper-center so keyboard doesn't push it
            VStack(spacing: 0) {
                searchBar
                Divider().padding(.horizontal, 24)
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.75))
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 32, y: 12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
            .padding(.horizontal, 40)
            .frame(maxHeight: 420)
            .padding(.bottom, 200)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focused = true
            }
        }
    }

    private func dismiss() {
        focused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = false
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(HomeTheme.textMuted)

            TextField("Search notes...", text: $query)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(HomeTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)

            HStack(spacing: 0) {
                SearchTabPill(label: "Your Notes", isActive: searchTab == .yours) {
                    searchTab = .yours
                }
                SearchTabPill(label: "Community", isActive: searchTab == .community) {
                    searchTab = .community
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.04))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Content (suggestions / results / empty)

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestionsView
        } else if !results.isEmpty {
            resultsView
        } else {
            emptyResultsView
        }
    }

    private var suggestionsView: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.suggestions.enumerated()), id: \.offset) { _, suggestion in
                Button {
                    query = suggestion
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 16))
                            .foregroundStyle(HomeTheme.textMuted)
                        Text(suggestion)
                            .font(.system(size: 16))
                            .foregroundStyle(HomeTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
    }

    private var resultsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(results.enumerated()), id: \.offset) { _, note in
                    SearchResultCard(title: note.title, subject: note.subject) {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var emptyResultsView: some View {
        VStack {
            Spacer()
            Text("No notes found for \"\(query)\"")
                .font(.system(size: 15))
                .foregroundStyle(HomeTheme.textMuted)
            Spacer()
        }
        .frame(height: 120)
    }
}

// MARK: - Search Tab Pill

private struct SearchTabPill: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? HomeTheme.textPrimary : HomeTheme.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isActive ? Color.white.opacity(0.8) : Color.clear)
                .clipShape(Capsule())
                .shadow(color: isActive ? .black.opacity(0.05) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Result Card

private struct SearchResultCard: View {
    let title: String
    let subject: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if let subject {
                    Text(subject)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomeTheme.accent)
                    +
                    Text(" — \(title) notes content preview...")
                        .font(.system(size: 13))
                        .foregroundStyle(HomeTheme.textSecondary)
                } else {
                    Text("\(title) notes content preview...")
                        .font(.system(size: 13))
                        .foregroundStyle(HomeTheme.textSecondary)
                }

                Spacer(minLength: 10)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HomeTheme.textPrimary)
            }
            .padding(16)
            .frame(width: 170, height: 130, alignment: .topLeading)
            .background(Color.white.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
