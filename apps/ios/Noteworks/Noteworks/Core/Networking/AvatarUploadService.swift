//
//  AvatarUploadService.swift
//  Noteworks
//
//  Talks to the `upload-avatar` edge function. The function accepts the
//  raw image bytes as the request body and replies with the public
//  avatar URL after writing it onto `users.avatar_url`.
//

import Foundation
import UIKit

/// Response shape returned by `POST /functions/v1/upload-avatar`.
struct AvatarUploadResponse: Decodable {
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case avatarUrl = "avatar_url"
    }
}

enum AvatarUploadError: LocalizedError {
    case encodingFailed
    case server(status: Int, body: String)
    case decodeFailed(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Couldn't read the selected image."
        case .server(let status, let body):
            return "Avatar upload failed (\(status)): \(body)"
        case .decodeFailed(let error):
            return "Avatar upload returned an unexpected response: \(error.localizedDescription)"
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

final class AvatarUploadService {
    static let shared = AvatarUploadService()
    private init() {}

    /// Uploads the given image to the `avatars` bucket as a JPEG (the
    /// `PhotosPicker` may hand us a HEIC; recompressing to JPEG keeps the
    /// payload small and avoids surprising the CDN). Returns the new
    /// public URL on success.
    func uploadAvatar(imageData: Data, accessToken: String) async throws -> String {
        // Normalize to JPEG @ ~0.85 quality so we stay under the 5 MB cap
        // and serve a format every browser/iOS version can render.
        guard let image = UIImage(data: imageData),
              let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw AvatarUploadError.encodingFailed
        }

        var request = URLRequest(url: SupabaseConfig.uploadAvatarURL)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = jpeg

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AvatarUploadError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AvatarUploadError.server(status: status, body: body)
        }

        do {
            let decoded = try JSONDecoder().decode(AvatarUploadResponse.self, from: data)
            return decoded.avatarUrl
        } catch {
            throw AvatarUploadError.decodeFailed(error)
        }
    }
}
