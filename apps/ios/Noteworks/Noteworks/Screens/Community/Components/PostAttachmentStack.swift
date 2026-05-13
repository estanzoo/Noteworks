//
//  PostAttachmentStack.swift
//  Noteworks
//
//  Renders the note attachments on a post. Each attachment is a row with
//  the note's title and a "View PDF" affordance when `has_pdf` is true.
//  Tapping an attachment surfaces the PDF in `PDFAttachmentPreview`.
//

import SwiftUI

struct PostAttachmentStack: View {
    let post: CommunityPost
    var detail: Bool = false
    var onOpenAttachment: ((PostAttachment) -> Void)? = nil

    var body: some View {
        if !post.attachments.isEmpty {
            VStack(spacing: 8) {
                ForEach(post.attachments) { attachment in
                    attachmentRow(attachment)
                }
            }
            .padding(.top, detail ? 0 : 12)
        }
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: PostAttachment) -> some View {
        let radius: CGFloat = detail ? 16 : 10
        let canOpen = attachment.hasPdf && onOpenAttachment != nil

        Button {
            guard canOpen else { return }
            onOpenAttachment?(attachment)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CommunityTheme.accent.opacity(0.12))
                    Image(systemName: attachment.hasPdf ? "doc.richtext" : "doc.text")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CommunityTheme.accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.title.isEmpty ? "Untitled note" : attachment.title)
                        .font(.system(size: detail ? 14 : 13, weight: .semibold))
                        .foregroundStyle(CommunityTheme.accent)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    if let filename = attachment.pdfFilename, attachment.hasPdf {
                        Text(filename)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CommunityTheme.textMuted)
                            .lineLimit(1)
                    } else if !attachment.hasPdf {
                        Text("Note")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CommunityTheme.textMuted)
                    }
                }
                Spacer(minLength: 0)

                if canOpen {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CommunityTheme.accent)
                }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
    }
}
