//
//  SearchPopupView.swift
//  Noteworks
//

import SwiftUI

// MARK: - Search Popup

/// Shared search overlay used from Home, CourseSpace, Profile, and
/// Community. Two tabs:
///   - **Your Notes** — searches `NotesStore.notes` in memory by title or
///     subject substring. Tapping a result currently just dismisses; the
///     local-notes screens already render notes, so deep navigation isn't
///     required from this surface yet.
///   - **Community** — hits `search-posts` on the backend with a 300ms
///     keystroke debounce, then renders post-shaped cards. Tapping a
///     result invokes `onSelectCommunityPost`, which the caller wires up
///     (Community uses it to open `CommunityPostDetailPopup`; the other
///     screens leave it as the default no-op).
struct SearchPopupView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var appState: AppState

    /// Which tab the popup opens on. Community-launched callers pass
    /// `.community` so the user lands on the relevant pill.
    var initialTab: SearchTab = .yours

    /// Invoked when the user taps a community search result. Defaults to
    /// a no-op so non-Community callers don't have to provide one.
    var onSelectCommunityPost: (CommunityPost) -> Void = { _ in }

    @State private var query = ""
    @State private var searchTab: SearchTab
    @FocusState private var focused: Bool

    // Community search state
    @State private var communityResults: [CommunityPost] = []
    @State private var isSearchingCommunity = false
    @State private var communityError: String?
    /// Set when the most recent committed search returned no rows. We
    /// can't infer "no results" from `communityResults.isEmpty` alone
    /// because the array is also empty before the first search lands.
    @State private var communitySearchedQuery: String?

    /// Bumped on every keystroke so an in-flight request that resolves
    /// after the user typed more characters is ignored.
    @State private var searchGeneration = 0
    private static let debounce: Duration = .milliseconds(300)

    private static let suggestions = [
        "Boolean operators",
        "Subject terms",
        "Refine results",
        "Citation searching",
    ]

    enum SearchTab: Equatable {
        case yours, community
    }

    init(
        isPresented: Binding<Bool>,
        initialTab: SearchTab = .yours,
        onSelectCommunityPost: @escaping (CommunityPost) -> Void = { _ in }
    ) {
        self._isPresented = isPresented
        self.initialTab = initialTab
        self.onSelectCommunityPost = onSelectCommunityPost
        _searchTab = State(initialValue: initialTab)
    }

    /// Local note hits. Empty when the query is blank or the Community
    /// tab is active.
    private var noteResults: [(title: String, subject: String?)] {
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
            // Blurred scrim over the host screen.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.1))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Glass search panel — pinned upper-center so the keyboard
            // doesn't push it off-screen.
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
            .frame(maxHeight: 460)
            .padding(.bottom, 200)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focused = true
            }
        }
        .onChange(of: query) { _, _ in
            scheduleSearchIfNeeded()
        }
        .onChange(of: searchTab) { _, _ in
            scheduleSearchIfNeeded()
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

            TextField(searchTab == .community ? "Search posts..." : "Search notes...", text: $query)
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
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            suggestionsView
        } else if searchTab == .community {
            communityContent(trimmed: trimmed)
        } else if !noteResults.isEmpty {
            yourNotesResultsView
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

    private var yourNotesResultsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(noteResults.enumerated()), id: \.offset) { _, note in
                    SearchResultCard(title: note.title, subject: note.subject) {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func communityContent(trimmed: String) -> some View {
        if isSearchingCommunity && communityResults.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Searching posts…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HomeTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
        } else if let error = communityError {
            VStack(spacing: 6) {
                Spacer()
                Text(error)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Pull down or change your query to try again.")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeTheme.textMuted)
                Spacer()
            }
            .frame(height: 160)
            .padding(.horizontal, 24)
        } else if !communityResults.isEmpty {
            communityResultsList
        } else if communitySearchedQuery == trimmed {
            emptyResultsView
        } else {
            // Query changed since last completed search — keep the
            // pre-search shimmer so the screen doesn't flash "no
            // results" while the debounce timer is running.
            VStack {
                Spacer()
                Text("Type to search community posts…")
                    .font(.system(size: 13))
                    .foregroundStyle(HomeTheme.textMuted)
                Spacer()
            }
            .frame(height: 160)
        }
    }

    private var communityResultsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(communityResults) { post in
                    Button {
                        onSelectCommunityPost(post)
                        dismiss()
                    } label: {
                        CommunitySearchResultRow(post: post)
                    }
                    .buttonStyle(.plain)
                    Divider()
                        .padding(.horizontal, 24)
                        .opacity(0.4)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 320)
    }

    private var emptyResultsView: some View {
        VStack {
            Spacer()
            Text("No results for \"\(query)\"")
                .font(.system(size: 15))
                .foregroundStyle(HomeTheme.textMuted)
            Spacer()
        }
        .frame(height: 120)
    }

    // MARK: - Community search driver

    /// Debounce trigger. Resets the loading bar immediately when the
    /// query changes so the UI doesn't show stale results while we wait
    /// out the debounce. Generation counter is the guard against
    /// out-of-order completions.
    private func scheduleSearchIfNeeded() {
        searchGeneration += 1
        let generation = searchGeneration

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard searchTab == .community, !trimmed.isEmpty else {
            communityResults = []
            communityError = nil
            communitySearchedQuery = nil
            isSearchingCommunity = false
            return
        }

        // Hold the previous results while we debounce so the list
        // doesn't blink between every keystroke.
        isSearchingCommunity = true
        communityError = nil

        Task {
            try? await Task.sleep(for: Self.debounce)
            guard generation == searchGeneration else { return }
            await runCommunitySearch(query: trimmed, generation: generation)
        }
    }

    private func runCommunitySearch(query: String, generation: Int) async {
        guard let token = appState.accessToken else {
            isSearchingCommunity = false
            communityError = "Sign in to search community posts."
            return
        }

        do {
            let page = try await CommunityService.shared.searchPosts(
                query: query,
                cursor: nil,
                limit: 20,
                accessToken: token
            )
            guard generation == searchGeneration else { return }
            communityResults = page.posts
            communitySearchedQuery = query
            isSearchingCommunity = false
            communityError = nil
        } catch {
            guard generation == searchGeneration else { return }
            let mapped = mapCommunityError(error)
            communityResults = []
            communitySearchedQuery = query
            isSearchingCommunity = false
            // Keep auth failures invisible-ish; AppState will route
            // the user back to Welcome via the global notification.
            if !mapped.isAuthFailure {
                communityError = mapped.userMessage
            }
        }
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

// MARK: - Your-Notes Result Card

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

// MARK: - Community Result Row

/// Single row inside the Community search results list. Renders title,
/// a short body excerpt, and a single-line metadata row (author + first
/// hashtag + attachment hint) so users can tell the hits apart.
private struct CommunitySearchResultRow: View {
    let post: CommunityPost

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "text.bubble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HomeTheme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(HomeTheme.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .lineLimit(1)

                if !post.body.isEmpty {
                    Text(post.body)
                        .font(.system(size: 12))
                        .foregroundStyle(HomeTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(post.authorName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HomeTheme.textMuted)

                    if let tag = post.hashtags.first {
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(HomeTheme.accent)
                    }

                    if !post.attachments.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(post.attachments.count)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(HomeTheme.textMuted)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
