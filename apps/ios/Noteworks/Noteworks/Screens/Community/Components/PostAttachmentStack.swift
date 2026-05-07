//
//  PostAttachmentStack.swift
//  Noteworks
//
//  Mirrors PostAttachmentStack (JSX L4401–L4488): image grid, video tile,
//  document and note rows. Used both on PostCard (detail=false, compact
//  thumbnails) and in the detail popup (detail=true, larger layout).
//

import SwiftUI

struct PostAttachmentStack: View {
    let post: CommunityPost
    var detail: Bool = false
    var onImageTap: ((Int) -> Void)? = nil

    private var images: [CommunityAttachment]   { post.attachments.filter { $0.kind == .image } }
    private var videos: [CommunityAttachment]   { post.attachments.filter { $0.kind == .video } }
    private var documents: [CommunityAttachment] { post.attachments.filter { $0.kind == .document } }
    private var notes: [CommunityAttachment]    { post.attachments.filter { $0.kind == .note } }

    var body: some View {
        if !post.attachments.isEmpty {
            VStack(alignment: .leading, spacing: detail ? 12 : 8) {
                if !images.isEmpty { imageGrid }
                ForEach(videos) { video in videoTile(video) }
                if !documents.isEmpty || !notes.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(documents) { document in documentRow(document) }
                        ForEach(notes) { note in noteRow(note) }
                    }
                }
            }
            .padding(.top, detail ? 0 : 12)
        }
    }

    // MARK: - Image grid

    private var imageGrid: some View {
        let columns: [GridItem] = images.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: detail ? 12 : 8), GridItem(.flexible(), spacing: detail ? 12 : 8)]

        return LazyVGrid(columns: columns, spacing: detail ? 12 : 8) {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                Button {
                    onImageTap?(index)
                } label: {
                    imageContent(image)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func imageContent(_ attachment: CommunityAttachment) -> some View {
        let radius: CGFloat = detail ? 22 : 12
        Group {
            if let url = attachment.url, let remote = URL(string: url) {
                AsyncImage(url: remote) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: detail ? .fit : .fill)
                    default:
                        Rectangle().fill(Color.white.opacity(0.48))
                    }
                }
            } else {
                // Placeholder for local/hardcoded images without a resolvable URL.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.72), Color.white.opacity(0.38)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: detail ? (images.count == 1 ? 420 : 360) : 120)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
        )
        .shadow(color: detail ? Color(red: 72/255, green: 90/255, blue: 117/255).opacity(0.12) : .clear,
                radius: 14, x: 0, y: 14)
    }

    // MARK: - Video tile

    private func videoTile(_ attachment: CommunityAttachment) -> some View {
        let radius: CGFloat = detail ? 22 : 12
        return HStack(spacing: 10) {
            Image(systemName: "play.rectangle")
                .font(.system(size: detail ? 24 : 18, weight: .regular))
                .foregroundStyle(CommunityTheme.textMuted)
            Text(attachment.name.isEmpty ? "Video" : attachment.name)
                .font(.system(size: detail ? 15 : 13, weight: .medium))
                .foregroundStyle(CommunityTheme.textMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minHeight: detail ? 240 : 100)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 227/255, green: 236/255, blue: 245/255).opacity(0.88),
                            Color(red: 243/255, green: 247/255, blue: 251/255).opacity(0.62),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Document row

    private func documentRow(_ attachment: CommunityAttachment) -> some View {
        let radius: CGFloat = detail ? 16 : 10
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CommunityTheme.accent.opacity(0.10))
                Text(attachment.ext ?? "FILE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CommunityTheme.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.name)
                    .font(.system(size: detail ? 14 : 13, weight: .semibold))
                    .foregroundStyle(CommunityTheme.textPrimary)
                    .lineLimit(1)
                if let size = attachment.size {
                    Text(size)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CommunityTheme.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, detail ? 14 : 12)
        .padding(.vertical, detail ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Note row

    private func noteRow(_ attachment: CommunityAttachment) -> some View {
        let radius: CGFloat = detail ? 16 : 10
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CommunityTheme.accent.opacity(0.12))
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CommunityTheme.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.name)
                    .font(.system(size: detail ? 14 : 13, weight: .semibold))
                    .foregroundStyle(CommunityTheme.accent)
                    .lineLimit(1)
                if let subject = attachment.subject {
                    Text(subject)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CommunityTheme.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, detail ? 14 : 12)
        .padding(.vertical, detail ? 12 : 8)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(CommunityTheme.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(CommunityTheme.accent.opacity(0.15), lineWidth: 1)
        )
    }
}
