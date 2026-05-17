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

    var body: some View {
        if !media.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(media) { item in
                        if let url = URL(string: item.url) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .empty:
                                    Color.black.opacity(0.04)
                                        .overlay(ProgressView().scaleEffect(0.7))
                                default:
                                    Color.black.opacity(0.04)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.system(size: 16))
                                                .foregroundStyle(CommunityTheme.textMuted)
                                        )
                                }
                            }
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}
