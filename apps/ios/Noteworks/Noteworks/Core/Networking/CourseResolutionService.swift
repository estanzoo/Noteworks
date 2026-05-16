//
//  CourseResolutionService.swift
//  Noteworks
//
//  Resolves local bubble/course labels to backend `courses.id` values.
//

import Foundation

struct CourseResolutionRequest: Encodable {
    let code: String
    let name: String
    let schoolId: String?
}

struct CourseResolutionResponse: Decodable, Equatable {
    let id: String
    let code: String
    let name: String?
}

final class CourseResolutionService {
    static let shared = CourseResolutionService()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func resolveCourse(
        code: String,
        name: String? = nil,
        schoolId: String? = nil,
        accessToken: String
    ) async throws -> CourseResolutionResponse {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name ?? trimmedCode).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = CourseResolutionRequest(
            code: trimmedCode,
            name: displayName.isEmpty ? trimmedCode : displayName,
            schoolId: schoolId
        )
        return try await api.post(SupabaseConfig.resolveCourseURL, body: body, accessToken: accessToken)
    }
}
