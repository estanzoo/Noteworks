//
//  SmartOrganizationService.swift
//  Noteworks
//

import Foundation

struct SmartOrganizationRequest: Encodable {
    let notePDFBase64: String
    let filename: String
    let noteTitle: String
    let pageCount: Int
    let courseContext: String?

    private enum CodingKeys: String, CodingKey {
        case notePDFBase64 = "note_pdf_base64"
        case filename
        case noteTitle = "note_title"
        case pageCount = "page_count"
        case courseContext = "course_context"
    }
}

struct SmartOrganizationResponse: Decodable, Equatable {
    let sections: [SmartOrganizationSection]
}

struct SmartOrganizationSection: Decodable, Equatable {
    let heading: String
    let bullets: [String]
}

protocol SmartOrganizationServiceProtocol {
    func organize(_ request: SmartOrganizationRequest, accessToken: String) async throws -> SmartOrganizationResponse
}

final class SmartOrganizationService: SmartOrganizationServiceProtocol {
    static let shared = SmartOrganizationService()

    private let api: APIClient
    private let session: URLSession

    init(api: APIClient = .shared, session: URLSession = .shared) {
        self.api = api
        self.session = session
    }

    func organize(_ request: SmartOrganizationRequest, accessToken: String) async throws -> SmartOrganizationResponse {
        do {
            return try await api.post(SupabaseConfig.smartOrganizeURL, body: request, accessToken: accessToken)
        } catch {
            if let localKey = SmartOrganizationGeminiEnvironment.apiKey {
                return try await organizeLocallyWithGemini(request, apiKey: localKey)
            }
            throw error
        }
    }

    private func organizeLocallyWithGemini(_ request: SmartOrganizationRequest, apiKey: String) async throws -> SmartOrganizationResponse {
        var lastError: Error?
        for model in SmartOrganizationGeminiEnvironment.modelCandidates {
            do {
                return try await organizeLocallyWithGemini(request, apiKey: apiKey, model: model)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? APIError.serverError("No Gemini model was available.")
    }

    private func organizeLocallyWithGemini(
        _ request: SmartOrganizationRequest,
        apiKey: String,
        model: String
    ) async throws -> SmartOrganizationResponse {
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(encodedKey)") else {
            throw APIError.badRequest("Invalid Gemini model or API key.")
        }

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": Self.prompt(for: request)],
                    [
                        "inline_data": [
                            "mime_type": "application/pdf",
                            "data": request.notePDFBase64,
                        ],
                    ],
                ],
            ]],
            "generationConfig": [
                "temperature": 0.3,
                "response_mime_type": "application/json",
            ],
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

        let gemini = try JSONDecoder().decode(SmartGeminiGenerateContentResponse.self, from: data)
        let text = gemini.candidates.first?.content.parts.compactMap(\.text).joined() ?? ""
        let cleaned = Self.stripCodeFence(text)
        guard let payload = cleaned.data(using: .utf8), !payload.isEmpty else {
            throw APIError.serverError("Gemini returned an empty response.")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SmartOrganizationResponse.self, from: payload)
    }

    private static func prompt(for request: SmartOrganizationRequest) -> String {
        """
        You are the Smart Organization engine for Noteworks.

        Analyze the student's note PDF and describe how you would reorganize it for clarity.
        Do not rewrite the note — return a concise summary of proposed structural changes.

        Note title: \(request.noteTitle)
        Page count: \(request.pageCount)
        Course context: \(request.courseContext ?? "Unknown")

        Return ONLY valid JSON:
        {
          "sections": [
            {
              "heading": "STRUCTURE",
              "bullets": ["3-5 bullets about section order, merged blocks, renamed headings"]
            },
            {
              "heading": "READABILITY",
              "bullets": ["3-5 bullets about paragraph tightening, bullets, duplicates removed"]
            },
            {
              "heading": "NEXT STEPS",
              "bullets": ["3-5 bullets the student should review after reorganization"]
            }
          ]
        }

        Each bullet should start with "- ". Keep bullets concrete and tied to the note content when possible.
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

private enum SmartOrganizationGeminiEnvironment {
    static var apiKey: String? { env("GEMINI_API_KEY") }
    static var model: String? { env("GEMINI_MODEL") }

    static var modelCandidates: [String] {
        var candidates: [String] = []
        if let model { candidates.append(model) }
        candidates.append(contentsOf: ["gemini-2.0-flash-lite", "gemini-2.0-flash", "gemini-2.5-flash"])
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func env(_ key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return nil
    }
}

private struct SmartGeminiGenerateContentResponse: Decodable {
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
