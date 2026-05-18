//
//  PostAttachmentPreviewPane.swift
//  Noteworks
//
//  Rich left-side preview pane for the post detail popup. Renders a big
//  primary preview tile (image full-bleed, real PDF first page via
//  PDFKit, or a stylized note card), a horizontal thumbnail strip with
//  every image / PDF / note attached to the post, and a footer caption.
//  Mirrors `ComposerAttachmentPreview` in noteworks-library.jsx L7628
//  but on the read side — so the post detail looks like a continuation
//  of the New Post composer.
//
//  Tapping the big tile or a thumbnail forwards to the caller:
//    - PDFs → opened in `PDFAttachmentPreview` (QuickLook).
//    - Images → opened in a full-screen viewer (handled by the caller).
//    - Notes without a PDF → no-op.
//

import SwiftUI
import PDFKit

// MARK: - Unified preview item

enum PostPreviewItem: Identifiable, Equatable {
    case image(url: String)
    case attachment(PostAttachment)

    var id: String {
        switch self {
        case .image(let url): return "img-\(url)"
        case .attachment(let a): return "att-\(a.id)"
        }
    }

    static func items(for post: CommunityPost) -> [PostPreviewItem] {
        var out: [PostPreviewItem] = []
        for m in post.media where m.isImage {
            out.append(.image(url: m.url))
        }
        for a in post.attachments {
            out.append(.attachment(a))
        }
        return out
    }
}

// MARK: - Pane

struct PostAttachmentPreviewPane: View {
    let post: CommunityPost
    let accessToken: String
    var onOpenAttachment: (PostAttachment) -> Void
    var onOpenImage: ((String) -> Void)? = nil

    @State private var selectedIndex: Int = 0

    private var items: [PostPreviewItem] { PostPreviewItem.items(for: post) }

    private var primaryCaption: String {
        let trimmed = post.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let first = items.first {
            switch first {
            case .image: return "Photo"
            case .attachment(let a): return a.title.isEmpty ? "Untitled note" : a.title
            }
        }
        return "Untitled post"
    }

    private var secondaryCaption: String {
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return post.postKind.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ATTACHMENT PREVIEW")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(CommunityTheme.textMuted)
                Text(primaryCaption)
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(CommunityTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !secondaryCaption.isEmpty {
                    Text(secondaryCaption)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CommunityTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            if let active = items.indices.contains(selectedIndex) ? items[selectedIndex] : items.first {
                primaryTile(for: active)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                if items.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        selectedIndex = idx
                                    }
                                } label: {
                                    thumbnail(for: item, isActive: idx == selectedIndex)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text("\(items.count) attached \(items.count == 1 ? "file" : "files")")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(CommunityTheme.textMuted)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 224/255, green: 238/255, blue: 248/255).opacity(0.58),
                    Color.white.opacity(0.34),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onChange(of: items.count) { _, newCount in
            if selectedIndex >= newCount { selectedIndex = 0 }
        }
    }

    // MARK: - Primary tile

    @ViewBuilder
    private func primaryTile(for item: PostPreviewItem) -> some View {
        Button {
            openItem(item)
        } label: {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.52))
                .overlay(
                    primaryContent(for: item)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
                )
                .shadow(color: Color(red: 73/255, green: 99/255, blue: 124/255).opacity(0.12), radius: 18, y: 8)
                .frame(minHeight: 280)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isOpenable(item))
    }

    @ViewBuilder
    private func primaryContent(for item: PostPreviewItem) -> some View {
        switch item {
        case .image(let url):
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    placeholderBackground
                        .overlay(ProgressView().tint(CommunityTheme.accent))
                case .failure:
                    placeholderBackground
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(CommunityTheme.textMuted)
                        )
                @unknown default:
                    placeholderBackground
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .attachment(let a):
            if a.hasPdf {
                PDFFirstPagePreview(
                    attachment: a,
                    accessToken: accessToken
                )
            } else {
                noteCardBackground(title: a.title)
            }
        }
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 226/255, green: 237/255, blue: 246/255).opacity(0.86),
                Color.white.opacity(0.74),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func noteCardBackground(title: String) -> some View {
        ZStack {
            placeholderBackground
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(CommunityTheme.accent)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
                    )
                    .frame(width: 78, height: 96)
                    .shadow(color: Color(red: 72/255, green: 90/255, blue: 117/255).opacity(0.18), radius: 14, y: 8)
                Text(title.isEmpty ? "Untitled note" : title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(CommunityTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            .padding(28)
        }
    }

    // MARK: - Thumbnails

    @ViewBuilder
    private func thumbnail(for item: PostPreviewItem, isActive: Bool) -> some View {
        let stroke = isActive ? CommunityTheme.accent.opacity(0.72) : Color.white.opacity(0.76)
        let strokeWidth: CGFloat = isActive ? 2 : 1
        ZStack {
            switch item {
            case .image(let url):
                AsyncImage(url: URL(string: url)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Color.black.opacity(0.05)
                    }
                }

            case .attachment(let a):
                Color.white.opacity(0.64)
                Image(systemName: a.hasPdf ? "doc.richtext" : "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? CommunityTheme.accent : CommunityTheme.textMuted)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(stroke, lineWidth: strokeWidth)
        )
        .shadow(
            color: isActive ? CommunityTheme.accent.opacity(0.18) : .clear,
            radius: 8, y: 4
        )
    }

    // MARK: - Open routing

    private func openItem(_ item: PostPreviewItem) {
        switch item {
        case .image(let url):
            onOpenImage?(url)
        case .attachment(let a):
            guard a.hasPdf else { return }
            onOpenAttachment(a)
        }
    }

    private func isOpenable(_ item: PostPreviewItem) -> Bool {
        switch item {
        case .image: return onOpenImage != nil
        case .attachment(let a): return a.hasPdf
        }
    }
}

// MARK: - PDF first-page renderer (shared)
//
// `PDFFirstPageImage` rasterises the first page of a PDF given its
// raw bytes — used directly by the New Post composer (which has local
// bytes) and indirectly by the post detail pane (which downloads first
// via `PDFFirstPagePreview` then forwards the bytes here).

/// Renders the first page of a PDF (provided as raw bytes) at the
/// available size, off the main thread. Used by:
///   - `PostAttachmentPreviewPane` (downloads bytes on demand, then
///     hands them to this view).
///   - The New Post composer (already has the PDF bytes locally, so the
///     preview is instant — no network round-trip).
///
/// `cacheKey` is optional: when provided, the rendered `UIImage` is
/// cached so reopening the same PDF doesn't re-rasterise. Pass the
/// note id for posted PDFs, or a local UUID for unpublished ones.
struct PDFFirstPageImage: View {
    let data: Data
    var cacheKey: String? = nil
    var fileLabel: String? = nil
    /// Inset around the rendered page so it doesn't bleed to the corners.
    var padding: CGFloat = 28

    @State private var image: UIImage?
    @State private var failed: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(padding)
                } else if failed {
                    PDFPlaceholderTile(label: fileLabel)
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 226/255, green: 237/255, blue: 246/255).opacity(0.86),
                            Color.white.opacity(0.74),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    ProgressView().tint(CommunityTheme.accent)
                }

                if image != nil, let label = fileLabel, !label.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Label(label, systemImage: "doc.richtext")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(CommunityTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.92)))
                                .overlay(Capsule().strokeBorder(CommunityTheme.glassBorder, lineWidth: 1))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                    }
                    .allowsHitTesting(false)
                }
            }
            .task(id: cacheKey ?? "\(data.hashValue)") {
                await render(at: geo.size)
            }
        }
    }

    @MainActor
    private func render(at size: CGSize) async {
        if let cacheKey, let cached = PDFRenderCache.shared.image(for: cacheKey) {
            image = cached
            return
        }
        let renderSize = CGSize(
            width: max(120, size.width * UIScreen.main.scale),
            height: max(160, size.height * UIScreen.main.scale)
        )
        let rendered = await Self.renderFirstPage(data: data, size: renderSize)
        if let rendered {
            image = rendered
            if let cacheKey {
                PDFRenderCache.shared.store(rendered, for: cacheKey)
            }
        } else {
            failed = true
        }
    }

    private static func renderFirstPage(data: Data, size: CGSize) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(data: data),
                  let page = doc.page(at: 0) else { return nil }
            let pageRect = page.bounds(for: .mediaBox)
            guard pageRect.width > 0, pageRect.height > 0 else { return nil }
            let scale = min(size.width / pageRect.width, size.height / pageRect.height)
            let drawSize = CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: drawSize, format: format)
            return renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: drawSize))
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: drawSize.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
        }.value
    }
}

/// Stylized "PDF" card shown while the PDF is downloading / when we
/// don't have its bytes yet (e.g. server-side note without raw bytes
/// in memory, or a failed render).
struct PDFPlaceholderTile: View {
    var label: String? = nil
    var ext: String = "PDF"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 226/255, green: 237/255, blue: 246/255).opacity(0.86),
                    Color.white.opacity(0.74),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .overlay(
                        Text(ext)
                            .font(.system(size: 14, weight: .black))
                            .tracking(1.4)
                            .foregroundStyle(CommunityTheme.accent)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(CommunityTheme.glassBorder, lineWidth: 1)
                    )
                    .frame(width: 78, height: 96)
                    .shadow(color: Color(red: 72/255, green: 90/255, blue: 117/255).opacity(0.18), radius: 14, y: 8)
                if let label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(CommunityTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240)
                }
            }
            .padding(28)
        }
    }
}

/// In-memory cache of rendered PDF first-page UIImages. Keyed by the
/// caller (note id for posted PDFs, or a local UUID for unpublished
/// composer attachments).
private final class PDFRenderCache {
    static let shared = PDFRenderCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 64
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

/// Server-side variant used by the post detail pane: downloads the PDF
/// bytes via `PDFStorageService`, caches them, then hands the data off
/// to `PDFFirstPageImage` to render the actual first page.
private struct PDFFirstPagePreview: View {
    let attachment: PostAttachment
    let accessToken: String

    @State private var data: Data?
    @State private var failed: Bool = false

    var body: some View {
        ZStack {
            if let data {
                PDFFirstPageImage(
                    data: data,
                    cacheKey: "post-\(attachment.noteId)",
                    fileLabel: attachment.pdfFilename ?? attachment.title
                )
            } else if failed {
                PDFPlaceholderTile(label: attachment.pdfFilename)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 226/255, green: 237/255, blue: 246/255).opacity(0.86),
                        Color.white.opacity(0.74),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 10) {
                    ProgressView().tint(CommunityTheme.accent)
                    Text("Loading preview…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CommunityTheme.textMuted)
                }
            }
        }
        .task(id: attachment.id) {
            await loadBytes()
        }
    }

    @MainActor
    private func loadBytes() async {
        if let cached = PDFBytesCache.shared.data(for: attachment.noteId) {
            data = cached
            return
        }
        do {
            let downloaded = try await PDFStorageService.shared.downloadPDF(
                noteId: attachment.noteId,
                accessToken: accessToken
            )
            PDFBytesCache.shared.store(downloaded, for: attachment.noteId)
            data = downloaded
        } catch {
            failed = true
        }
    }
}

private final class PDFBytesCache {
    static let shared = PDFBytesCache()
    private let cache = NSCache<NSString, NSData>()

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func data(for noteId: String) -> Data? {
        cache.object(forKey: noteId as NSString) as Data?
    }

    func store(_ data: Data, for noteId: String) {
        cache.setObject(data as NSData, forKey: noteId as NSString, cost: data.count)
    }
}
