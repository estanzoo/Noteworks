//
//  PostKindBadge.swift
//  Noteworks
//
//  Small pill that surfaces a post's `post_kind` channel on the card
//  header. Mirrors the "Post to" segmented control in the New Post
//  composer (noteworks-library.jsx L7956-7962) so a poster who picks
//  "Study Questions" sees a tiny Study Questions chip on their card
//  in the feed.
//
//  Also defines `PostMediaCarousel`, the horizontally-scrolling image
//  preview shown above the attachment stack when a post has photos.
//

import SwiftUI

struct PostKindPill: View {
    let kind: PostKind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(kind.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(CommunityTheme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(CommunityTheme.accent.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(CommunityTheme.accent.opacity(0.25), lineWidth: 1))
    }
}

struct PostMediaCarousel: View {
    let media: [PostMedia]
    var onImageTap: ((String) -> Void)? = nil

    private var images: [PostMedia] {
        media.filter(\.isImage)
    }

    var body: some View {
        if !images.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images) { item in
                        mediaTile(for: item)
                    }
                }
                .padding(.vertical, 6)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func mediaTile(for item: PostMedia) -> some View {
        let content = RemotePostImage(urlString: item.url, contentMode: .fill)
        .frame(width: 160, height: 160)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

        if let onImageTap {
            Button { onImageTap(item.url) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}
