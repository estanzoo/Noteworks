//
//  APIClient.swift
//  Noteworks
//
//  Created on 2026-03-18.
//

import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case badRequest(String)
    case notFound(String)
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case unknown(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .badRequest(let msg):
            return msg
        case .notFound(let msg):
            return msg
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .decodingError(let err):
            return "Data error: \(err.localizedDescription)"
        case .unknown(let code, let msg):
            return "Error \(code): \(msg)"
        }
    }
}

/// Posted when `APIClient` exhausts its single retry and a request still
/// returns 401. `AppState` observes this to drop the user back to Welcome
/// without every call site having to remember to do so.
extension Notification.Name {
    static let authSessionExpired = Notification.Name("NoteworksAuthSessionExpired")
}

/// Lightweight HTTP client for Supabase Edge Functions.
///
/// `accessToken` is still passed explicitly to each call (every screen
/// already has one in hand). On 401 the client asks the configured
/// `refreshTokenProvider` for a new one and retries the request **once**.
/// If the retry is also 401 — or there is no provider — `.unauthorized`
/// bubbles up and `Notification.Name.authSessionExpired` is posted.
actor APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let decoder: JSONDecoder

    /// Closure that exchanges the stored refresh token for a fresh access
    /// token. Returns `nil` if refresh failed (caller should sign out).
    /// Configured once on app launch via `configure(refreshTokenProvider:)`.
    private var refreshTokenProvider: (@Sendable () async -> String?)?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Configuration

    /// Install the refresh hook used by the one-shot 401 retry. Safe to
    /// call multiple times — the most recent provider wins.
    func configure(refreshTokenProvider: @escaping @Sendable () async -> String?) {
        self.refreshTokenProvider = refreshTokenProvider
    }

    // MARK: - JSON requests

    func get<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        try await performJSON(url: url, method: "GET", body: nil, accessToken: accessToken)
    }

    func post<T: Decodable>(_ url: URL, body: some Encodable, accessToken: String) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await performJSON(url: url, method: "POST", body: data, accessToken: accessToken)
    }

    func patch<T: Decodable>(_ url: URL, body: some Encodable, accessToken: String) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await performJSON(url: url, method: "PATCH", body: data, accessToken: accessToken)
    }

    func delete<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        try await performJSON(url: url, method: "DELETE", body: nil, accessToken: accessToken)
    }

    // MARK: - Raw binary upload (for PDFs)

    func uploadPDF(_ url: URL, pdfData: Data, accessToken: String) async throws -> NoteResponse {
        try await performWithRetry(accessToken: accessToken) { token in
            var request = self.makeRequest(url: url, method: "POST", accessToken: token)
            request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
            request.httpBody = pdfData
            return request
        }
    }

    // MARK: - Raw data download

    func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.serverError("Failed to download file")
        }
        return data
    }

    // MARK: - Private helpers

    private func performJSON<T: Decodable>(
        url: URL,
        method: String,
        body: Data?,
        accessToken: String
    ) async throws -> T {
        try await performWithRetry(accessToken: accessToken) { token in
            var request = self.makeRequest(url: url, method: method, accessToken: token)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            return request
        }
    }

    /// Runs `buildRequest(token)` once, and on 401 asks the configured
    /// `refreshTokenProvider` for a new token and runs it again exactly one
    /// more time. The closure is invoked with the most-current token so the
    /// retry uses fresh `Authorization`/`apikey` headers.
    private func performWithRetry<T: Decodable>(
        accessToken: String,
        buildRequest: (_ token: String) -> URLRequest
    ) async throws -> T {
        do {
            return try await perform(buildRequest(accessToken))
        } catch APIError.unauthorized {
            guard let provider = refreshTokenProvider,
                  let refreshed = await provider() else {
                NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                throw APIError.unauthorized
            }
            do {
                return try await perform(buildRequest(refreshed))
            } catch APIError.unauthorized {
                NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                throw APIError.unauthorized
            }
        }
    }

    private func makeRequest(url: URL, method: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(0, "Invalid response")
        }

        guard (200...299).contains(http.statusCode) else {
            throw mapError(statusCode: http.statusCode, data: data)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func mapError(statusCode: Int, data: Data) -> APIError {
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
            ?? String(data: data, encoding: .utf8)
            ?? "Unknown error"

        switch statusCode {
        case 401: return .unauthorized
        case 400: return .badRequest(message)
        case 404: return .notFound(message)
        case 500...599: return .serverError(message)
        default: return .unknown(statusCode, message)
        }
    }
}

private struct ErrorBody: Decodable {
    let error: String?
    let message: String
}
