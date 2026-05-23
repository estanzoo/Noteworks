//
//  PostEditorPopup.swift
//  Noteworks
//
//  The "New Post" sheet. Pixel-aligned to the JSX mock in
//  others/NoteWorks_UI 2/noteworks-library.jsx (PostEditorPopup, L7598).
//
//  Top to bottom:
//    - Avatar + "New Post" header with a close (×) button
//    - Title field (large, underlined)
//    - Body field (multi-line, "(optional)" hint)
//    - Three attach chips: Photo / Video · Document · Note
//        - Photo / Video — uploads each picked image via
//          `upload-post-media`; the returned storage paths go on
//          `CreatePostRequest.mediaPaths`
//        - Document      — picks PDFs from Files, uploads them via the
//          existing `upload-note-pdf` pipeline (one note per file)
//        - Note          — inline picker over the user's library;
//          attaches the existing note + its PDF if any
//    - Course dropdown   — driven by the user's local bubble names
//      (Plan 2 ties bubbles to courses), nullable
//    - Tag chips         — 7 preset (mock L7596) + custom-tag input,
//      everything stored as hashtags under the hood
//    - "Post to" channel — Note / Study Questions / Discussions,
//      written to `posts.post_kind` (migration 20260516060000)
//    - Publish button
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Constants

private let editorAccent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)
private let editorAccentLight = Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)
private let editorTextPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
private let editorTextSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.6)
private let editorTextMuted = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.4)
private let editorGlassBorder = Color.white.opacity(0.5)
private let editorErrorRed = Color(red: 0xC4/255, green: 0x44/255, blue: 0x44/255)
private let editorNotePaper = Color(red: 0xFE/255, green: 0xFC/255, blue: 0xF4/255)
private let editorNotePaperDot = Color.black.opacity(0.06)

private let accentGradient = LinearGradient(
    colors: [editorAccent, editorAccentLight],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

/// Mirrors `TAG_OPTIONS` at noteworks-library.jsx L7596.
private let presetTags: [String] = [
    "Study Tips",
    "Question",
    "Exam Prep",
    "Group Study",
    "Resource",
    "Discussion",
    "Announcement",
]

// MARK: - Pending attachment models

/// A PDF the user has picked but hasn't uploaded yet (or has uploaded
/// already). Each one carries a client-generated UUID that doubles as
/// the eventual `note_id` for `upload-note-pdf`.
struct PendingPostAttachment: Identifiable, Equatable {
    let id: String
    let filename: String
    var data: Data
    var courseId: String?
    var isLocked: Bool = false
    var status: Status

    enum Status: Equatable {
        case preparing
        case pending
        case uploading
        case uploaded
        case failed(String)
    }
}

/// An image the user picked. We keep the raw bytes locally and replace
/// `storagePath` once `upload-post-media` succeeds. Display is driven
/// by `data` (optimistic) or the returned `storagePath` (post-publish).
private struct PendingMediaItem: Identifiable, Equatable {
    let id: String
    var data: Data
    var status: Status

    enum Status: Equatable {
        case pending
        case uploading
        case uploaded(storagePath: String, publicURL: String)
        case failed(String)
    }

    var uploadedPath: String? {
        if case .uploaded(let path, _) = status { return path }
        return nil
    }

    var publicURL: String? {
        if case .uploaded(_, let url) = status { return url }
        return nil
    }
}

// MARK: - Unified preview item
//
// The composer keeps images, documents, and library notes in separate
// pieces of state (different upload pipelines), but the new attachment
// preview pane treats them as one ordered list. This view-only enum is
// the bridge — the order is photos first, then documents/notes, matching
// the order they appear inline on the right-hand side of the form.

private enum EditorPreviewItem: Identifiable, Equatable {
    case image(id: String, data: Data)
    /// `data` is the raw file bytes. When the file extension is "PDF"
    /// (the only document type the picker accepts today) the preview
    /// tile rasterises the first page via `PDFFirstPageImage`.
    case document(id: String, filename: String, ext: String, data: Data)
    case note(id: String, title: String, subtitle: String?)

    var id: String {
        switch self {
        case .image(let id, _): return "img-\(id)"
        case .document(let id, _, _, _): return "doc-\(id)"
        case .note(let id, _, _): return "note-\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .image: return "Photo"
        case .document(_, let filename, _, _): return filename
        case .note(_, let title, _): return title.isEmpty ? "Untitled note" : title
        }
    }
}

// MARK: - Post Editor Popup

struct PostEditorPopup: View {
    @Binding var isPresented: Bool
    let accessToken: String
    var isTutorialStatic: Bool = false
    var initialAttachments: [PendingPostAttachment] = []
    var initialTitle: String? = nil
    var initialBody: String? = nil
    var initialCourseId: String? = nil
    var prepareInitialAttachments: (() async -> [PendingPostAttachment])? = nil
    let onPublished: (CommunityPost) -> Void
    let submit: (CreatePostRequest) async throws -> CommunityPost

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notesStore: NotesStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var postTitle: String
    @State private var postBody: String
    @State private var presetSelected: Set<String> = []
    @State private var customTags: [String] = []
    @State private var customTagInput: String = ""
    @State private var attachments: [PendingPostAttachment] = []
    @State private var mediaItems: [PendingMediaItem] = []
    @State private var showPhotoPicker = false
    @State private var photoPickerSelection: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showNotePicker = false
    @State private var attachedLibraryNoteIds: Set<String> = []
    @State private var selectedBubbleName: String? = nil
    @State private var courseDropdownOpen = false
    @State private var postKind: PostKind = .discussions
    @State private var errorMessage: String?
    @State private var titleError: String?
    @State private var bodyError: String?
    @State private var isPublishing: Bool = false
    @State private var isPreparingInitialAttachments = false
    /// Which attachment is shown in the large left-hand preview tile.
    @State private var previewSelectedIndex: Int = 0
    @FocusState private var titleFocused: Bool

    init(
        isPresented: Binding<Bool>,
        accessToken: String,
        isTutorialStatic: Bool = false,
        initialAttachments: [PendingPostAttachment] = [],
        initialTitle: String? = nil,
        initialBody: String? = nil,
        initialCourseId: String? = nil,
        prepareInitialAttachments: (() async -> [PendingPostAttachment])? = nil,
        onPublished: @escaping (CommunityPost) -> Void,
        submit: @escaping (CreatePostRequest) async throws -> CommunityPost
    ) {
        self._isPresented = isPresented
        self.accessToken = accessToken
        self.isTutorialStatic = isTutorialStatic
        self.initialAttachments = initialAttachments
        self.initialTitle = initialTitle
        self.initialBody = initialBody
        self.initialCourseId = initialCourseId
        self.prepareInitialAttachments = prepareInitialAttachments
        self.onPublished = onPublished
        self.submit = submit
        self._postTitle = State(initialValue: initialTitle ?? "")
        self._postBody = State(initialValue: initialBody ?? "")
        self._attachments = State(initialValue: initialAttachments)
    }

    private static let maxAttachments = 10
    private static let maxMedia = 6
    private static let maxHashtags = 20
    private static let maxTitle = 255
    private static let maxBody = 10_000

    private var trimmedTitle: String { postTitle.trimmingCharacters(in: .whitespaces) }
    private var trimmedBody: String { postBody.trimmingCharacters(in: .whitespaces) }

    /// Title is the only required field — JSX composer publishes with
    /// body empty (it shows "(optional)" on the placeholder).
    private var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !isPublishing
            && !isPreparingInitialAttachments
            && !attachments.contains { $0.status == .preparing }
    }

    /// Hashtags actually sent to `create-post`. Preset chips are stored
    /// as lower-kebab versions ("Study Tips" → "study-tips") so they
    /// survive the server's normalisation.
    private var resolvedHashtags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for label in presetTags where presetSelected.contains(label) {
            let normalized = normalize(label)
            if !normalized.isEmpty, seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        for label in customTags {
            let normalized = normalize(label)
            if !normalized.isEmpty, seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return Array(result.prefix(Self.maxHashtags))
    }

    /// Lower-kebab a free-form label so preset / custom tags reuse the
    /// same hashtag rows on the server (avoids "study-tips" and
    /// "Study Tips" splitting into two hashtag rows).
    private func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private var meAuthorName: String { appState.profile?.displayName ?? "You" }
    private var meAvatarUrl: String? { appState.profile?.avatarUrl }

    private var bubbleOptions: [String] {
        notesStore.bubbleNames
            .filter { !NotesStore.isReservedName($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Flattened, ordered list of every pending attachment (images +
    /// documents + library notes) for the left-hand preview pane. Photos
    /// come first so that an image-only post lands on an image preview
    /// (matches noteworks-library.jsx L7628 `ComposerAttachmentPreview`).
    private var previewItems: [EditorPreviewItem] {
        var items: [EditorPreviewItem] = []
        for media in mediaItems {
            items.append(.image(id: media.id, data: media.data))
        }
        for attachment in attachments {
            if attachedLibraryNoteIds.contains(attachment.id) {
                items.append(.note(
                    id: attachment.id,
                    title: attachment.filename,
                    subtitle: noteSubtitle(for: attachment.id)
                ))
            } else {
                items.append(.document(
                    id: attachment.id,
                    filename: attachment.filename,
                    ext: fileExtension(for: attachment.filename),
                    data: attachment.data
                ))
            }
        }
        return items
    }

    private var hasAnyAttachment: Bool { !previewItems.isEmpty }

    /// We only split into the side-by-side layout on regular-width
    /// classes — on iPhone the preview lives above the form as a small
    /// strip (kept inline by the existing thumbnail rows).
    private var showsPreviewPane: Bool {
        hasAnyAttachment && horizontalSizeClass != .compact
    }

    /// Sentence shown under the title in the preview pane when the
    /// body is empty. Mirrors `previewMeta` in the JSX (L7632).
    private var previewSecondaryLine: String {
        var parts: [String] = []
        parts.append(postKind.label)
        if let course = selectedBubbleName, !course.isEmpty {
            parts.append(course)
        }
        return parts.joined(separator: " · ")
    }

    private func noteSubtitle(for noteId: String) -> String? {
        guard let note = notesStore.notes.first(where: { $0.id == noteId }) else {
            return nil
        }
        let subject = (note.subject?.isEmpty == false) ? note.subject! : "Uncategorized"
        return subject
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.12))
                .ignoresSafeArea()
                .onTapGesture {
                    if !isTutorialStatic { dismiss() }
                }

            popupShell
                .allowsHitTesting(!isTutorialStatic)
                .frame(
                    maxWidth: showsPreviewPane ? 960 : 540,
                    maxHeight: 760
                )
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.white.opacity(0.78))
                        }
                )
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(editorGlassBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 32, y: 12)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
                .padding(.horizontal, showsPreviewPane ? 24 : 32)
                .animation(.easeInOut(duration: 0.22), value: showsPreviewPane)
                .tutorialAnchor(.communityComposer)
                .tutorialHighlight(.communityComposer, activeTarget: appState.tutorialCoordinator.activeTarget)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            if attachments.isEmpty && !initialAttachments.isEmpty {
                attachments = initialAttachments
            }
            if postTitle.isEmpty, let initialTitle {
                postTitle = initialTitle
            }
            if postBody.isEmpty, let initialBody {
                postBody = initialBody
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if !isTutorialStatic {
                    titleFocused = true
                }
            }
        }
        .task {
            await prepareInitialAttachmentsIfNeeded()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoPickerSelection,
            maxSelectionCount: max(1, Self.maxMedia - mediaItems.count),
            matching: .images
        )
        .onChange(of: photoPickerSelection) { _, newItems in
            handlePhotoPick(newItems)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Shell layout

    @ViewBuilder
    private var popupShell: some View {
        if showsPreviewPane {
            HStack(spacing: 0) {
                previewPane
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                    .frame(maxHeight: .infinity)
                    .clipped()
                Rectangle()
                    .fill(Color(red: 219/255, green: 227/255, blue: 235/255).opacity(0.74))
                    .frame(width: 1)
                formScroll
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            formScroll
        }
    }

    private var formScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                titleField
                bodyField
                attachButtonsRow
                notePickerInline
                // On regular width the left preview pane already shows
                // attachments — inline rows here would duplicate and bleed
                // over the form (scaledToFill images ignore the divider).
                if !showsPreviewPane {
                    attachedLibraryNotesPreview
                    mediaPreviews
                    documentPreviews
                }
                courseSection
                tagsSection
                postToSection
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(editorErrorRed)
                        .padding(.bottom, 12)
                }
                publishButton
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
    }

    private func dismiss() {
        titleFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = false
            }
        }
    }

    // MARK: - Attachment preview pane (left side)
    //
    // Mirrors `ComposerAttachmentPreview` in noteworks-library.jsx L7628:
    // header label + primary attachment caption, a big primary preview
    // tile, then a thumbnail strip + "N attached file…" footer.

    @ViewBuilder
    private var previewPane: some View {
        let items = previewItems
        let safeIndex = items.isEmpty ? 0 : min(previewSelectedIndex, items.count - 1)
        let primary = items.indices.contains(safeIndex) ? items[safeIndex] : items.first
        let captionTitle: String = {
            let t = trimmedTitle
            if !t.isEmpty { return t }
            return primary?.displayName ?? "Untitled post"
        }()
        let captionSecondary: String = {
            let b = trimmedBody
            if !b.isEmpty { return b }
            return previewSecondaryLine
        }()

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ATTACHMENT PREVIEW")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(editorTextMuted)
                Text(captionTitle)
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(editorTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !captionSecondary.isEmpty {
                    Text(captionSecondary)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(editorTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            if let primary {
                primaryPreviewTile(for: primary)
                    .id(primary.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeOut(duration: 0.18), value: primary.id)
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                if items.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) { index, item in
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        previewSelectedIndex = index
                                    }
                                } label: {
                                    thumbnailTile(for: item, isActive: index == safeIndex)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text("\(items.count) attached \(items.count == 1 ? "file" : "files") will publish with this post.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(editorTextMuted)
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
        .onChange(of: previewItems.map(\.id)) { _, ids in
            if previewSelectedIndex >= ids.count {
                previewSelectedIndex = max(0, ids.count - 1)
            }
        }
    }

    // MARK: - Preview tiles

    @ViewBuilder
    private func primaryPreviewTile(for item: EditorPreviewItem) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.52))
            .overlay {
                primaryPreviewContent(for: item)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
            )
            .shadow(color: Color(red: 73/255, green: 99/255, blue: 124/255).opacity(0.12), radius: 18, y: 8)
            .frame(minHeight: 240)
            .layoutPriority(-1)
    }

    @ViewBuilder
    private func primaryPreviewContent(for item: EditorPreviewItem) -> some View {
        switch item {
        case .image(_, let data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [editorAccent.opacity(0.18), Color.white.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

        case .document(let id, let filename, let ext, let data):
            if ext == "PDF", !data.isEmpty {
                PDFFirstPageImage(
                    data: data,
                    cacheKey: "composer-\(id)",
                    fileLabel: filename
                )
            } else {
                PDFPlaceholderTile(label: filename, ext: ext)
            }

        case .note(_, let title, let subtitle):
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 222/255, green: 236/255, blue: 246/255).opacity(0.8),
                        Color.white.opacity(0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                noteCardMock(title: title, subtitle: subtitle)
                    .frame(maxWidth: 220)
                    .padding(20)
            }
        }
    }

    private func noteCardMock(title: String, subtitle: String?) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [editorNotePaper, Color(red: 0xFF/255, green: 0xFB/255, blue: 0xE8/255)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(red: 228/255, green: 229/255, blue: 220/255), lineWidth: 1)
            )
            .overlay(
                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(Color(red: 242/255, green: 123/255, blue: 232/255).opacity(0.62))
                        .frame(height: 12)
                        .padding(.trailing, 14)
                    Capsule()
                        .fill(Color.black.opacity(0.09))
                        .frame(height: 8)
                        .padding(.trailing, 44)
                    Capsule()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 8)
                        .padding(.trailing, 26)
                    Spacer(minLength: 8)
                    Capsule()
                        .fill(editorAccent.opacity(0.16))
                        .frame(height: 8)
                    Capsule()
                        .fill(editorAccent.opacity(0.12))
                        .frame(width: 110, height: 8)
                    Text(title.isEmpty ? "Untitled note" : title)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(editorTextPrimary)
                        .lineLimit(1)
                        .padding(.top, 6)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(editorTextMuted)
                            .lineLimit(1)
                    }
                }
                .padding(18)
            )
            .aspectRatio(0.72, contentMode: .fit)
            .shadow(color: Color(red: 72/255, green: 90/255, blue: 117/255).opacity(0.14), radius: 20, y: 12)
    }

    @ViewBuilder
    private func thumbnailTile(for item: EditorPreviewItem, isActive: Bool) -> some View {
        let stroke = isActive ? editorAccent.opacity(0.72) : Color.white.opacity(0.76)
        let strokeWidth: CGFloat = isActive ? 2 : 1
        ZStack {
            switch item {
            case .image(_, let data):
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.05)
                }

            case .document(let id, _, let ext, let data):
                if ext == "PDF", !data.isEmpty {
                    PDFFirstPageImage(
                        data: data,
                        cacheKey: "composer-thumb-\(id)",
                        fileLabel: nil,
                        padding: 4
                    )
                } else {
                    Color.white.opacity(0.64)
                    Text(ext)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(isActive ? editorAccent : editorTextMuted)
                }

            case .note:
                Color.white.opacity(0.64)
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? editorAccent : editorTextMuted)
            }
        }
        .frame(width: 54, height: 54)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(stroke, lineWidth: strokeWidth)
        )
        .shadow(
            color: isActive ? editorAccent.opacity(0.18) : .clear,
            radius: 8, y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                CommunityAvatar(
                    name: meAuthorName,
                    size: 36,
                    avatarUrl: meAvatarUrl
                )
                Text("New Post")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(editorTextPrimary)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(editorTextMuted)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Enter your title…", text: $postTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(editorTextPrimary)
                .focused($titleFocused)
                .textInputAutocapitalization(.sentences)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(titleError == nil ? Color.black.opacity(0.06) : editorErrorRed.opacity(0.4))
                        .frame(height: 1.5)
                }

            if let titleError {
                Text(titleError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(editorErrorRed)
            } else if trimmedTitle.count > 200 {
                Text("\(trimmedTitle.count) / \(Self.maxTitle)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(editorTextMuted)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Body

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Write your post content… (optional)", text: $postBody, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(editorTextPrimary)
                .lineLimit(3...7)

            if let bodyError {
                Text(bodyError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(editorErrorRed)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Attach buttons row (Photo / Document / Note)

    private var attachButtonsRow: some View {
        HStack(spacing: 10) {
            AttachChip(icon: "photo", label: "Photo / Video", isDisabled: mediaItems.count >= Self.maxMedia) {
                showPhotoPicker = true
            }
            AttachChip(icon: "doc", label: "Document", isDisabled: attachments.count >= Self.maxAttachments) {
                showFileImporter = true
            }
            AttachChip(icon: "doc.text", label: "Note") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showNotePicker.toggle()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Note picker inline panel

    @ViewBuilder
    private var notePickerInline: some View {
        if showNotePicker {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Select a note to attach")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(editorTextMuted)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showNotePicker = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(editorTextMuted)
                            .frame(width: 20, height: 20)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

                if notesStore.notes.isEmpty {
                    Text("Your library is empty. Use the Document button to attach a PDF instead.")
                        .font(.system(size: 12))
                        .foregroundStyle(editorTextSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(notesStore.notes.prefix(20)) { note in
                                NotePickerRow(
                                    note: note,
                                    attached: attachedLibraryNoteIds.contains(note.id)
                                ) {
                                    toggleLibraryNote(note)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(editorGlassBorder, lineWidth: 1)
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var attachedLibraryNotesPreview: some View {
        let libraryRows = attachments.filter { attachedLibraryNoteIds.contains($0.id) }
        if !showNotePicker, !libraryRows.isEmpty {
            VStack(spacing: 8) {
                ForEach(libraryRows) { item in
                    attachedNoteRow(item)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func attachedNoteRow(_ item: PendingPostAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(editorAccent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(editorAccent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(editorTextPrimary)
                    .lineLimit(1)
                Text(statusLabel(item.status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(item.status))
            }

            Spacer(minLength: 0)

            if !item.isLocked, item.status != .uploading, item.status != .preparing {
                Button {
                    attachments.removeAll { $0.id == item.id }
                    attachedLibraryNoteIds.remove(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(editorTextMuted)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(editorAccent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(editorAccent.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Document (PDF) previews

    @ViewBuilder
    private var documentPreviews: some View {
        let docs = attachments.filter { !attachedLibraryNoteIds.contains($0.id) }
        if !docs.isEmpty {
            VStack(spacing: 8) {
                ForEach(docs) { attachment in
                    docRow(attachment)
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func docRow(_ attachment: PendingPostAttachment) -> some View {
        HStack(spacing: 10) {
            Text(fileExtension(for: attachment.filename))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(editorAccent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(editorAccent.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(editorTextPrimary)
                    .lineLimit(1)
                Text(statusLabel(attachment.status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(attachment.status))
            }

            Spacer(minLength: 0)

            if attachment.status == .preparing || attachment.status == .uploading {
                ProgressView().scaleEffect(0.7)
            } else if !attachment.isLocked {
                Button {
                    attachments.removeAll { $0.id == attachment.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(editorTextMuted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(editorGlassBorder, lineWidth: 1))
    }

    // MARK: - Image previews

    @ViewBuilder
    private var mediaPreviews: some View {
        if !mediaItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(mediaItems) { item in
                        imageTile(item)
                    }
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func imageTile(_ item: PendingMediaItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = UIImage(data: item.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.05)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(editorGlassBorder, lineWidth: 1))

            if case .uploading = item.status {
                Color.black.opacity(0.35)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                ProgressView().tint(.white)
                    .frame(width: 100, height: 100)
            } else {
                Button {
                    mediaItems.removeAll { $0.id == item.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(4)
            }

            if case .failed(let msg) = item.status {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.75))
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Course dropdown

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Course")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorTextMuted)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    courseDropdownOpen.toggle()
                }
            } label: {
                HStack {
                    Text(selectedBubbleName ?? "Select a course…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectedBubbleName == nil ? editorTextMuted : editorTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(editorTextMuted)
                        .rotationEffect(.degrees(courseDropdownOpen ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.5))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(courseDropdownOpen ? editorAccent.opacity(0.5) : Color.black.opacity(0.06), lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)

            if courseDropdownOpen {
                VStack(spacing: 0) {
                    if selectedBubbleName != nil {
                        CourseOptionRow(label: "Clear selection", active: false, dimmed: true) {
                            selectedBubbleName = nil
                            courseDropdownOpen = false
                        }
                    }
                    if bubbleOptions.isEmpty {
                        Text("Create a bubble on Home to pick a course here.")
                            .font(.system(size: 12))
                            .foregroundStyle(editorTextSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(bubbleOptions, id: \.self) { name in
                            CourseOptionRow(label: name, active: selectedBubbleName == name) {
                                selectedBubbleName = name
                                courseDropdownOpen = false
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.9))
                        }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(editorGlassBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorTextMuted)

            FlowLayout(spacing: 8) {
                ForEach(presetTags, id: \.self) { tag in
                    TagChip(
                        label: tag,
                        active: presetSelected.contains(tag),
                        removable: false,
                        onTap: { togglePreset(tag) },
                        onRemove: {}
                    )
                }
                ForEach(customTags, id: \.self) { tag in
                    TagChip(
                        label: tag,
                        active: true,
                        removable: true,
                        onTap: {},
                        onRemove: { customTags.removeAll { $0 == tag } }
                    )
                }
            }

            HStack(spacing: 8) {
                TextField("Add custom tag…", text: $customTagInput)
                    .font(.system(size: 13))
                    .foregroundStyle(editorTextPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1.5)
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { addCustomTag() }

                if !customTagInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: addCustomTag) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: editorAccent.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 18)
    }

    // MARK: - Post to channel

    private var postToSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Post to")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorTextMuted)

            HStack(spacing: 8) {
                ForEach(PostKind.allCases, id: \.self) { kind in
                    EditorChannelButton(
                        icon: kind.icon,
                        label: kind.label,
                        isActive: postKind == kind
                    ) {
                        postKind = kind
                    }
                }
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Publish

    private var publishButton: some View {
        Button {
            Task { await publish() }
        } label: {
            HStack(spacing: 8) {
                if isPublishing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                }
                Text(isPublishing ? "Publishing…" : "Publish")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canPublish ? .white : editorTextMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                if canPublish {
                    RoundedRectangle(cornerRadius: 16).fill(accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.04))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: canPublish ? editorAccent.opacity(0.35) : .clear,
                radius: 10, y: 4
            )
        }
        .buttonStyle(.plain)
        .disabled(!canPublish)
    }

    // MARK: - Helpers — tags

    private func togglePreset(_ tag: String) {
        if presetSelected.contains(tag) { presetSelected.remove(tag) }
        else { presetSelected.insert(tag) }
    }

    private func addCustomTag() {
        let trimmed = customTagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let normalized = normalize(trimmed)
        if !normalized.isEmpty,
           !customTags.contains(where: { normalize($0) == normalized }),
           !presetTags.contains(where: { normalize($0) == normalized }) {
            customTags.append(trimmed)
        }
        customTagInput = ""
    }

    // MARK: - Helpers — attachments

    private func statusLabel(_ status: PendingPostAttachment.Status) -> String {
        switch status {
        case .preparing: return "Preparing current note…"
        case .pending: return "Ready to upload"
        case .uploading: return "Uploading…"
        case .uploaded: return "Uploaded"
        case .failed(let m): return m
        }
    }

    private func statusColor(_ status: PendingPostAttachment.Status) -> Color {
        switch status {
        case .preparing, .pending, .uploading: return editorTextMuted
        case .uploaded: return editorAccent
        case .failed: return editorErrorRed
        }
    }

    private func fileExtension(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(4))
    }

    @MainActor
    private func prepareInitialAttachmentsIfNeeded() async {
        guard let prepareInitialAttachments else { return }
        guard !isPreparingInitialAttachments else { return }
        guard attachments.contains(where: { $0.status == .preparing }) else { return }

        isPreparingInitialAttachments = true
        let prepared = await prepareInitialAttachments()
        for item in prepared {
            if let idx = attachments.firstIndex(where: { $0.id == item.id }) {
                attachments[idx] = item
            } else if attachments.count < Self.maxAttachments {
                attachments.append(item)
            }
        }
        isPreparingInitialAttachments = false
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard attachments.count < Self.maxAttachments else { break }
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                let item = PendingPostAttachment(
                    id: UUID().uuidString,
                    filename: url.lastPathComponent,
                    data: data,
                    status: .pending
                )
                attachments.append(item)
            }
        case .failure(let error):
            errorMessage = "Could not import file: \(error.localizedDescription)"
        }
    }

    private func handlePhotoPick(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard mediaItems.count < Self.maxMedia else { break }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        let pending = PendingMediaItem(
                            id: UUID().uuidString,
                            data: data,
                            status: .pending
                        )
                        mediaItems.append(pending)
                    }
                }
            }
            await MainActor.run { photoPickerSelection = [] }
        }
    }

    private func toggleLibraryNote(_ note: Note) {
        if attachedLibraryNoteIds.contains(note.id) {
            attachedLibraryNoteIds.remove(note.id)
            attachments.removeAll { $0.id == note.id }
            return
        }
        guard attachments.count < Self.maxAttachments else { return }

        // Library notes that already have a PDF flow through the existing
        // server-side `post_attachments` join — we don't re-upload bytes.
        // We mark them `.uploaded` immediately and rely on the server's
        // post_attachments row creation in `create-post`.
        attachedLibraryNoteIds.insert(note.id)
        attachments.append(PendingPostAttachment(
            id: note.id,
            filename: note.title.isEmpty ? "Untitled note" : note.title,
            data: Data(),
            courseId: note.courseId,
            isLocked: false,
            status: .uploaded
        ))
    }

    // MARK: - Submit flow

    private func publish() async {
        guard !isPublishing else { return }
        titleError = nil
        bodyError = nil
        errorMessage = nil

        if trimmedTitle.isEmpty {
            titleError = "Title is required."
            return
        }
        if trimmedTitle.count > Self.maxTitle {
            titleError = "Title can't exceed \(Self.maxTitle) characters."
            return
        }
        // Body is optional in the new composer to match the mock ("(optional)").
        if trimmedBody.count > Self.maxBody {
            bodyError = "Body can't exceed \(Self.maxBody) characters."
            return
        }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let uploadedNoteIds = try await uploadAttachments()
            let mediaUpload = try await uploadMedia()
            let request = CreatePostRequest(
                title: trimmedTitle,
                body: trimmedBody,
                visibility: "public",
                courseId: initialCourseId ?? attachments.first(where: { $0.courseId != nil })?.courseId,
                postKind: postKind,
                attachmentNoteIds: uploadedNoteIds.isEmpty ? nil : uploadedNoteIds,
                mediaPaths: mediaUpload.paths.isEmpty ? nil : mediaUpload.paths,
                hashtags: resolvedHashtags.isEmpty ? nil : resolvedHashtags
            )
            var created = try await submit(request)
            if created.media.isEmpty, !mediaUpload.items.isEmpty {
                created.media = mediaUpload.items
            }
            onPublished(created)
            dismiss()
        } catch let error as CommunityError {
            errorMessage = error.userMessage
        } catch {
            let mapped = mapCommunityError(error)
            errorMessage = mapped.userMessage
        }
    }

    private func uploadAttachments() async throws -> [String] {
        var ids: [String] = []
        for index in attachments.indices {
            let item = attachments[index]
            // Library notes (already uploaded as part of the user's
            // library) — server's `post_attachments` link will be
            // created in `create-post`. We don't have raw PDF bytes
            // here, so we just hand over the note id.
            if attachedLibraryNoteIds.contains(item.id) {
                ids.append(item.id)
                continue
            }
            switch item.status {
            case .uploaded:
                ids.append(item.id)
            case .preparing:
                throw APIError.serverError("Still preparing the current note. Please wait.")
            case .pending, .failed:
                attachments[index].status = .uploading
                do {
                    _ = try await PDFStorageService.shared.uploadPDFData(
                        item.data,
                        noteId: item.id,
                        filename: item.filename,
                        courseId: item.courseId ?? initialCourseId,
                        accessToken: accessToken
                    )
                    attachments[index].status = .uploaded
                    ids.append(item.id)
                } catch {
                    attachments[index].status = .failed("Upload failed — tap Publish to retry")
                    throw error
                }
            case .uploading:
                throw APIError.serverError("An attachment upload is already in progress.")
            }
        }
        return ids
    }

    private struct MediaUploadResult {
        var paths: [String] = []
        var items: [PostMedia] = []
    }

    private func uploadMedia() async throws -> MediaUploadResult {
        var result = MediaUploadResult()
        for index in mediaItems.indices {
            let item = mediaItems[index]
            if let path = item.uploadedPath, let url = item.publicURL {
                result.paths.append(path)
                result.items.append(PostMedia(kind: "image", url: url))
                continue
            }
            mediaItems[index].status = .uploading
            do {
                let resp = try await PostMediaUploadService.shared.uploadImage(
                    imageData: item.data,
                    accessToken: accessToken
                )
                mediaItems[index].status = .uploaded(
                    storagePath: resp.storagePath,
                    publicURL: resp.url
                )
                result.paths.append(resp.storagePath)
                result.items.append(PostMedia(kind: "image", url: resp.url))
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "Image upload failed"
                mediaItems[index].status = .failed(msg)
                throw error
            }
        }
        return result
    }
}

// MARK: - Reusable sub-components

private struct AttachChip: View {
    let icon: String
    let label: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(editorAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(editorAccent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(editorAccent.opacity(0.25), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

private struct TagChip: View {
    let label: String
    let active: Bool
    let removable: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: removable ? onRemove : onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? editorAccent : editorTextSecondary)
                if removable {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(editorAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(active ? editorAccent.opacity(0.1) : Color.white.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(active ? editorAccent.opacity(0.5) : Color.black.opacity(0.08), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CourseOptionRow: View {
    let label: String
    let active: Bool
    var dimmed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                    .foregroundStyle(dimmed ? editorTextMuted : (active ? editorAccent : editorTextPrimary))
                Spacer()
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(editorAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(active ? editorAccent.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NotePickerRow: View {
    let note: Note
    let attached: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(editorAccent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(editorAccent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(editorTextPrimary)
                        .lineLimit(1)
                    Text((note.subject?.isEmpty == false ? note.subject! : "Uncategorized"))
                        .font(.system(size: 11))
                        .foregroundStyle(editorTextMuted)
                }

                Spacer(minLength: 0)

                if attached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(editorAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(attached ? editorAccent.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EditorChannelButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isActive ? .white : editorTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 14).fill(accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.4))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                if !isActive {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1.5)
                }
            }
            .shadow(
                color: isActive ? editorAccent.opacity(0.25) : .clear,
                radius: 6, y: 2
            )
        }
        .buttonStyle(.plain)
    }
}
