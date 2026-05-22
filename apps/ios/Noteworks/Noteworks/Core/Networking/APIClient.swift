//
//  APIClient.swift
//  Noteworks
//
//  Created on 2026-03-18.
//

import Foundation
import os.log

private let apiLogger = Logger(subsystem: "studio.noteworks", category: "APIClient")

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
        decoder.dateDecodingStrategy = .iso8601Flexible
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

    /// Edge Functions with `verify_jwt = false` (e.g. password reset confirm).
    /// Sends only the project anon key — no user session.
    func postPublic<T: Decodable>(_ url: URL, body: some Encodable) async throws -> T {
        let data = try JSONEncoder().encode(body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return try await perform(request)
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
            // Without this log a decode failure becomes the opaque
            // "Couldn't read the server's response." banner; surface the
            // real reason (and a body preview) to the unified log so we
            // can triage future contract drifts from Xcode's Console.
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<binary>"
            apiLogger.error("Decode failure for \(request.url?.absoluteString ?? "?", privacy: .public)\nerror: \(String(describing: error), privacy: .public)\nbody: \(preview, privacy: .public)")
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

// MARK: - Date decoding

extension JSONDecoder.DateDecodingStrategy {
    /// ISO-8601 strategy that accepts both Postgres `timestamptz` output
    /// (`2026-05-13T19:05:58.718074+00:00`, with 1–6 digit fractional
    /// seconds) and the plainer `2026-05-13T19:05:58Z` form. `Foundation`'s
    /// built-in `.iso8601` only accepts the latter, so any field backed by
    /// a `timestamptz` column would otherwise throw `dataCorrupted`.
    static let iso8601Flexible: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = ISO8601DateParser.shared.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected ISO-8601 date, got \(raw)"
        )
    }
}

/// Parses ISO-8601 strings with or without fractional seconds. Wraps two
/// `ISO8601DateFormatter`s because each one's `formatOptions` are an AND
/// mask — a single instance cannot accept both fractional and integral
/// forms. Used by `JSONDecoder.DateDecodingStrategy.iso8601Flexible`.
private final class ISO8601DateParser: @unchecked Sendable {
    static let shared = ISO8601DateParser()

    private let withFraction: ISO8601DateFormatter
    private let withoutFraction: ISO8601DateFormatter

    private init() {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.withFraction = f1

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        self.withoutFraction = f2
    }

    func date(from string: String) -> Date? {
        if let d = withFraction.date(from: string) { return d }
        return withoutFraction.date(from: string)
    }
}
