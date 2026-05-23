//
//  GapDetectionService.swift
//  Noteworks
//

import Foundation

struct GapDetectionRequest: Encodable {
    let sourcePDFBase64: String
    let comparisonPDFBase64: String
    let sourceFilename: String
    let comparisonFilename: String
    let sourceTitle: String
    let comparisonTitle: String
    let courseContext: String?
    let additionalPDFsBase64: [String]?
    let additionalFilenames: [String]?

    private enum CodingKeys: String, CodingKey {
        case sourcePDFBase64 = "source_pdf_base64"
        case comparisonPDFBase64 = "comparison_pdf_base64"
        case sourceFilename = "source_filename"
        case comparisonFilename = "comparison_filename"
        case sourceTitle = "source_title"
        case comparisonTitle = "comparison_title"
        case courseContext = "course_context"
        case additionalPDFsBase64 = "additional_pdfs_base64"
        case additionalFilenames = "additional_filenames"
    }
}

struct GapDetectionResponse: Decodable, Equatable {
    let title: String
    let overview: String
    let missingTopics: [String]
    let extraTopics: [String]
    let weakAreas: [String]
    let contradictions: [String]
    let recommendedAdditions: [String]
    let confidence: GapDetectionConfidence
}

enum GapDetectionConfidence: String, Decodable, Equatable {
    case low
    case medium
    case high
}

protocol GapDetectionServiceProtocol {
    func compare(_ request: GapDetectionRequest, accessToken: String) async throws -> GapDetectionResponse
}

final class GapDetectionService: GapDetectionServiceProtocol {
    static let shared = GapDetectionService()

    private let api: APIClient
    private let session: URLSession

    init(api: APIClient = .shared, session: URLSession = .shared) {
        self.api = api
        self.session = session
    }

    func compare(_ request: GapDetectionRequest, accessToken: String) async throws -> GapDetectionResponse {
        do {
            return try await api.post(SupabaseConfig.gapDetectURL, body: request, accessToken: accessToken)
        } catch {
            if let localKey = LocalGeminiEnvironment.apiKey {
                return try await compareLocallyWithGemini(request, apiKey: localKey)
            }
            throw error
        }
    }

    /// Temporary fallback for when the Supabase Edge Function is not available.
    /// This intentionally supports archived builds while Supabase access is blocked.
    /// Remove this method and `LocalGeminiEnvironment` once the backend key is ready.
    private func compareLocallyWithGemini(_ request: GapDetectionRequest, apiKey: String) async throws -> GapDetectionResponse {
        var lastError: Error?
        for model in LocalGeminiEnvironment.modelCandidates {
            do {
                return try await compareLocallyWithGemini(request, apiKey: apiKey, model: model)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? APIError.serverError("No Gemini model was available.")
    }

    private func compareLocallyWithGemini(
        _ request: GapDetectionRequest,
        apiKey: String,
        model: String
    ) async throws -> GapDetectionResponse {
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(encodedKey)") else {
            throw APIError.badRequest("Invalid Gemini model or API key.")
        }

        var parts: [[String: Any]] = [
            ["text": Self.prompt(for: request)],
            [
                "inline_data": [
                    "mime_type": "application/pdf",
                    "data": request.sourcePDFBase64
                ]
            ],
            [
                "inline_data": [
                    "mime_type": "application/pdf",
                    "data": request.comparisonPDFBase64
                ]
            ]
        ]
        for pdf in request.additionalPDFsBase64 ?? [] {
            parts.append([
                "inline_data": [
                    "mime_type": "application/pdf",
                    "data": pdf
                ]
            ])
        }

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": parts
            ]],
            "generationConfig": [
                "temperature": 0.25,
                "response_mime_type": "application/json"
            ]
        ]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = String(data: data.prefix(512), encoding: .utf8) ?? "Gemini request failed"
            throw APIError.serverError(message)
        }

        let gemini = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let text = gemini.candidates.first?.content.parts.compactMap(\.text).joined() ?? ""
        let cleaned = Self.stripCodeFence(text)
        guard let payload = cleaned.data(using: .utf8), !payload.isEmpty else {
            throw APIError.serverError("Gemini returned an empty response.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GapDetectionResponse.self, from: payload)
    }

    private static func prompt(for request: GapDetectionRequest) -> String {
        """
        You are the Gap Detection engine for Noteworks.

        Compare PDF A, the student's current note, against PDF B, the comparison note or class material.
        Any additional PDFs are optional class materials that provide extra context.

        PDF A filename: \(request.sourceFilename)
        PDF A title: \(request.sourceTitle)
        PDF B filename: \(request.comparisonFilename)
        PDF B title: \(request.comparisonTitle)
        Course context: \(request.courseContext ?? "Unknown")
        Additional class materials: \((request.additionalFilenames ?? []).joined(separator: ", "))

        Return ONLY valid JSON with these snake_case keys:
        {
          "title": "Gap Detection Summary",
          "overview": "2-4 sentence student-friendly summary of the most important differences.",
          "missing_topics": ["topics or ideas that PDF B covers but PDF A misses"],
          "extra_topics": ["topics PDF A covers that PDF B does not emphasize"],
          "weak_areas": ["areas in PDF A that are present but too shallow, unclear, or unsupported"],
          "contradictions": ["possible conflicts or mismatches between the PDFs"],
          "recommended_additions": ["specific additions the student should add to PDF A"],
          "confidence": "low | medium | high"
        }

        Keep every list to at most 6 concise items. Prefer concrete course concepts over generic study advice.
        """
    }

    private static func stripCodeFence(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```(?:json)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum LocalGeminiEnvironment {
    static var apiKey: String? {
        value(for: "GEMINI_API_KEY")
    }

    static var model: String? {
        value(for: "GEMINI_MODEL")
    }

    static var modelCandidates: [String] {
        var candidates: [String] = []
        if let model { candidates.append(model) }
        candidates.append(contentsOf: ["gemini-2.0-flash-lite", "gemini-2.0-flash", "gemini-2.5-flash"])
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func value(for key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return dotenv()[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func dotenv() -> [String: String] {
        for name in [".env.local", ".env"] {
            if let text = bundledTextFile(named: name) {
                return parse(text)
            }
        }
        return [:]
    }

    private static func bundledTextFile(named name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent(name)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    private static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            result[key] = value
        }
        return result
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
