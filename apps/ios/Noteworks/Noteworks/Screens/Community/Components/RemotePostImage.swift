//
//  RemotePostImage.swift
//  Noteworks
//
//  Loads community post photos via URLSession (works with signed URLs
//  from the API, same as PDFs). AsyncImage is unreliable for Supabase
//  storage URLs on device.
//

import SwiftUI

struct RemotePostImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                ZStack {
                    Color.black.opacity(0.04)
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(CommunityTheme.textMuted)
                }
            } else {
                ZStack {
                    Color.black.opacity(0.04)
                    ProgressView()
                        .tint(CommunityTheme.accent)
                        .scaleEffect(0.85)
                }
            }
        }
        .task(id: urlString) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        image = nil
        failed = false
        guard let url = URL(string: urlString) else {
            failed = true
            return
        }
        if let cached = PostImageCache.shared.image(for: urlString) {
            image = cached
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            PostImageCache.shared.store(decoded, for: urlString)
            image = decoded
        } catch {
            failed = true
        }
    }
}

/// Small in-memory cache so reopening a post doesn't re-download photos.
private final class PostImageCache {
    static let shared = PostImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 48
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
