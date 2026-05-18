//
//  FeedbackService.swift
//  Noteworks
//
//  Wraps `POST /submit-feedback`. Built as a tiny dedicated service so
//  the Profile screen never imports `APIClient` directly — same pattern
//  as `CommunityService`, `CourseResolutionService`, etc.
//

import Foundation
import UIKit

/// Request payload sent to `submit-feedback`. Mirrors the validator
/// inside `packages/supabase/.../functions/submit-feedback/index.ts`
/// 1:1 — field names use snake_case so we don't need a custom
/// `CodingKeys`.
struct SubmitFeedbackRequest: Encodable, Sendable {
    let feedback_type: String
    let area: String
    let area_other: String?
    let priority: String
    let title: String
    let body: String
    let follow_up_enabled: Bool
    let contact_email: String?
    let media_paths: [String]
    let app_version: String?
    let device_info: DeviceInfo?

    struct DeviceInfo: Encodable, Sendable {
        let os: String
        let os_version: String
        let model: String
    }
}

/// Response shape from `submit-feedback` (201). Only the id + created
/// timestamp are useful client-side; everything else round-trips via
/// the Feedback table itself.
struct SubmitFeedbackResponse: Decodable, Sendable {
    let id: String
    let status: String
    let createdAt: Date
}

protocol FeedbackServiceProtocol {
    func submitFeedback(_ request: SubmitFeedbackRequest, accessToken: String) async throws -> SubmitFeedbackResponse
}

final class FeedbackService: FeedbackServiceProtocol {
    static let shared = FeedbackService()

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func submitFeedback(
        _ request: SubmitFeedbackRequest,
        accessToken: String
    ) async throws -> SubmitFeedbackResponse {
        try await api.post(SupabaseConfig.submitFeedbackURL, body: request, accessToken: accessToken)
    }

    /// Snapshot of the host device so the support team can quickly tell
    /// whether a bug is OS-specific. Called from the iOS submit path —
    /// safe to extend later (locale, available storage, etc.) without
    /// touching the edge function (it accepts arbitrary JSON).
    @MainActor
    static func currentDeviceInfo() -> SubmitFeedbackRequest.DeviceInfo {
        let device = UIDevice.current
        return SubmitFeedbackRequest.DeviceInfo(
            os: device.systemName,
            os_version: device.systemVersion,
            model: device.model
        )
    }
}
