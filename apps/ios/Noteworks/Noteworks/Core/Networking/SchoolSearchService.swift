//
//  SchoolSearchService.swift
//  Noteworks
//
//  Created on 2026-04-13.
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

    private var searchTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(300)

    /// The access token for authenticated requests.
    var accessToken: String?

    func search() {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isLoading = false
            return
        }

        isLoading = true

        searchTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }

            do {
                let response: SchoolSearchResponse = try await fetchSchools(search: trimmed)
                guard !Task.isCancelled else { return }
                results = response.data
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }

            isLoading = false
        }
    }

    private func fetchSchools(search: String) async throws -> SchoolSearchResponse {
        let url = SupabaseConfig.getSchoolsURL(search: search, page: 1, pageSize: 8)
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
