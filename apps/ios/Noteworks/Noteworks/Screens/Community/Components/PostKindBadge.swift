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
    /// Icon-only chip. Used in the cramped feed-card header (3-column
    /// grid) where a full "Discussion" label would crowd out the
    /// author name. The detail popup keeps the full label.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon)
                .font(.system(size: compact ? 11 : 10, weight: .semibold))
            if !compact {
                Text(kind.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
        // Keep the pill on one line — without this, a narrow card column
        // squeezes "Discussion" into a stack of "Disc / ussi / on".
        .fixedSize()
        .foregroundStyle(CommunityTheme.accent)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 6 : 5)
        .background(CommunityTheme.accent.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(CommunityTheme.accent.opacity(0.25), lineWidth: 1))
    }
}

struct PostMediaCarousel: View {
    let media: [PostMedia]
    /// When true (post detail), use a full-width swipe pager instead of
    /// a horizontal strip of small tiles.
    var useSwipePager: Bool = false
    var onImageTap: ((String) -> Void)? = nil

    @State private var pagerIndex: Int = 0

    private var images: [PostMedia] {
        media.filter(\.isImage)
    }

    var body: some View {
        if !images.isEmpty {
            if useSwipePager {
                swipePager
                    .padding(.top, 12)
            } else {
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
    }

    private var swipePager: some View {
        VStack(spacing: 8) {
            TabView(selection: $pagerIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { idx, item in
                    pagerTile(for: item)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if images.count > 1 {
                Text("\(pagerIndex + 1) / \(images.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CommunityTheme.textMuted)
            }
        }
        .onChange(of: images.count) { _, newCount in
            if pagerIndex >= newCount { pagerIndex = 0 }
        }
    }

    @ViewBuilder
    private func pagerTile(for item: PostMedia) -> some View {
        let content = RemotePostImage(urlString: item.url, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

        if let onImageTap {
            Button { onImageTap(item.url) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
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
