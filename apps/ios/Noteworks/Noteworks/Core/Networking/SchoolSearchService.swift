//
//  SchoolSearchService.swift
//  Noteworks
//
//  Created on 2026-04-13.
//
//  The college autocomplete UI used to hit `/get-schools` on every keystroke
//  (with a 300ms debounce). That made the dropdown feel sluggish: the user
//  had to type, wait for the request, and then see suggestions. We now
//  prefetch the entire `schools` table once — typically while the user is
//  still on the Welcome / SignUp screens — and run the autocomplete filter
//  locally against the in-memory cache. The remote search is kept as a
//  fallback for the brief window before the prefetch completes (and for
//  the rare case where the prefetch fails outright).
//

import Foundation
import Combine

// MARK: - Models

struct SchoolResult: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let location: String?
    let country: String?
    let stateProvince: String?
    let city: String?
}

private struct SchoolSearchResponse: Decodable {
    let data: [SchoolResult]
    let pagination: Pagination

    struct Pagination: Decodable {
        let page: Int
        let pageSize: Int
        let total: Int
        let totalPages: Int
        let hasMore: Bool
    }
}

// MARK: - Service

@MainActor
final class SchoolSearchService: ObservableObject {
    @Published var query = ""
    @Published var results: [SchoolResult] = []
    @Published var isLoading = false

    /// Has the full schools list finished downloading? While this is false
    /// we fall back to the remote `/get-schools` search so the user is
    /// never stuck without suggestions.
    @Published private(set) var isPrefetched = false

    private var searchTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?

    /// In-memory cache populated by `prefetchAll()`. Sorted by name (same
    /// order the server returns) so the autocomplete keeps a stable feel.
    private var cache: [SchoolResult] = []

    /// Debounce only matters for the remote-fallback path; local filtering
    /// is fast enough to run on every keystroke.
    private let remoteDebounce: Duration = .milliseconds(300)

    /// Defensive cap on prefetch pages so a misconfigured server can't make
    /// the app loop forever. 100 pages × 100 rows = 10k schools, which is
    /// well above the realistic size of `public.schools`.
    private let maxPrefetchPages = 100
    private let prefetchPageSize = 100

    /// Maximum suggestions to surface — matches the existing UI which only
    /// has room for ~8 rows in the glass dropdown.
    private let suggestionLimit = 8

    /// The access token for authenticated requests.
    var accessToken: String?

    // MARK: - Prefetch

    /// Kicks off (or refreshes) the full-table download. Safe to call
    /// multiple times — concurrent calls share the same in-flight task,
    /// and a successful prefetch is reused for the rest of the session.
    func prefetchAll(accessToken: String?) {
        self.accessToken = accessToken
        guard prefetchTask == nil, !isPrefetched else { return }

        prefetchTask = Task { [weak self] in
            guard let self else { return }
            await self.runPrefetch()
            self.prefetchTask = nil
        }
    }

    private func runPrefetch() async {
        var collected: [SchoolResult] = []
        var page = 1

        while page <= maxPrefetchPages {
            do {
                let response = try await fetchSchools(
                    search: nil,
                    page: page,
                    pageSize: prefetchPageSize
                )
                collected.append(contentsOf: response.data)
                if !response.pagination.hasMore { break }
                page += 1
            } catch {
                // Prefetch failed — leave `isPrefetched = false` so
                // `search()` keeps using the remote endpoint. The next
                // call to `prefetchAll` will retry.
                return
            }
        }

        cache = collected
        isPrefetched = true

        // If the user has already typed something while we were
        // downloading, refresh the results now that the local cache is
        // ready so the UI doesn't sit on a stale remote response.
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            search()
        }
    }

    // MARK: - Search

    func search() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isLoading = false
            return
        }

        // Fast path: filter the in-memory cache. Mirrors the server's
        // `name.ilike.%q% OR location.ilike.%q%` predicate.
        if isPrefetched {
            results = localFilter(query: trimmed)
            isLoading = false
            return
        }

        // Fallback path: hit `/get-schools` with the same debounce as
        // before. This keeps the existing behaviour for users on a cold
        // launch who type before `prefetchAll()` has finished.
        isLoading = true
        searchTask = Task {
            try? await Task.sleep(for: remoteDebounce)
            guard !Task.isCancelled else { return }

            do {
                let response = try await fetchSchools(
                    search: trimmed,
                    page: 1,
                    pageSize: suggestionLimit
                )
                guard !Task.isCancelled else { return }
                // The prefetch might have completed while this request was
                // in flight — prefer the (definitive) local filter in that
                // case so a slow network can't overwrite fresher data.
                if isPrefetched {
                    results = localFilter(query: trimmed)
                } else {
                    results = response.data
                }
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }

            isLoading = false
        }
    }

    private func localFilter(query: String) -> [SchoolResult] {
        let needle = query.lowercased()
        var matches: [SchoolResult] = []
        matches.reserveCapacity(suggestionLimit)

        for school in cache {
            if school.name.lowercased().contains(needle)
                || (school.location?.lowercased().contains(needle) ?? false)
            {
                matches.append(school)
                if matches.count == suggestionLimit { break }
            }
        }
        return matches
    }

    // MARK: - Networking

    private func fetchSchools(
        search: String?,
        page: Int,
        pageSize: Int
    ) async throws -> SchoolSearchResponse {
        let url = SupabaseConfig.getSchoolsURL(
            search: search ?? "",
            page: page,
            pageSize: pageSize
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.serverError("School search failed")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SchoolSearchResponse.self, from: data)
    }
}
