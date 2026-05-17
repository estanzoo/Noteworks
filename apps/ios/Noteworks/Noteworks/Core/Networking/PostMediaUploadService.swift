//
//  PostMediaUploadService.swift
//  Noteworks
//
//  Talks to the `upload-post-media` edge function. Mirrors
//  `AvatarUploadService` — sends the image bytes as the request body,
//  then hands the returned `storage_path` to `create-post` via
//  `CreatePostRequest.media_paths`. Kept separate from
//  `AvatarUploadService` because the two endpoints write to different
//  storage buckets and have different lifecycle rules (avatars are
//  owned by `users`, post media by `posts`).
//

import Foundation
import UIKit

/// Response shape returned by `POST /functions/v1/upload-post-media`.
struct PostMediaUploadResponse: Decodable {
    let storagePath: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case storagePath = "storage_path"
        case url
    }
}

enum PostMediaUploadError: LocalizedError {
    case encodingFailed
    case server(status: Int, body: String)
    case decodeFailed(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Couldn't read the selected image."
        case .server(let status, let body):
            return "Media upload failed (\(status)): \(body)"
        case .decodeFailed(let error):
            return "Media upload returned an unexpected response: \(error.localizedDescription)"
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

final class PostMediaUploadService {
    static let shared = PostMediaUploadService()
    private init() {}

    /// Uploads a single image (re-encoded as JPEG @ 0.85 quality so we
    /// stay under the 20 MB bucket cap). Returns the storage path the
    /// caller should put in `CreatePostRequest.mediaPaths`.
    func uploadImage(imageData: Data, accessToken: String) async throws -> PostMediaUploadResponse {
        guard let image = UIImage(data: imageData),
              let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw PostMediaUploadError.encodingFailed
        }

        var request = URLRequest(url: SupabaseConfig.uploadPostMediaURL)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = jpeg
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PostMediaUploadError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PostMediaUploadError.server(status: status, body: body)
        }

        do {
            return try JSONDecoder().decode(PostMediaUploadResponse.self, from: data)
        } catch {
            throw PostMediaUploadError.decodeFailed(error)
        }
    }
}
