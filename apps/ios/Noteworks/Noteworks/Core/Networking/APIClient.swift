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

/// Lightweight HTTP client for Supabase Edge Functions.
/// All authenticated requests require an `accessToken` from the current session.
actor APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - JSON requests

    func get<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        var request = makeRequest(url: url, method: "GET", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    func post<T: Decodable>(_ url: URL, body: some Encodable, accessToken: String) async throws -> T {
        var request = makeRequest(url: url, method: "POST", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    // MARK: - Raw binary upload (for PDFs)

    func uploadPDF(_ url: URL, pdfData: Data, accessToken: String) async throws -> NoteResponse {
        var request = makeRequest(url: url, method: "POST", accessToken: accessToken)
        request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        request.httpBody = pdfData
        return try await perform(request)
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
