//
//  PostEditorPopup.swift
//  Noteworks
//
//  The "New Post" sheet. Drives the two-step post-creation flow from
//  docs/Community_Posts_Guide.md — first uploads each pending PDF to
//  `upload-note-pdf` (one per client-generated UUID), then calls the
//  caller's `submit` closure with the resulting `CreatePostRequest`
//  including `attachment_note_ids`. Also surfaces hashtag suggestions
//  via `search-hashtags` as the user types.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Constants

private let editorAccent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)
private let editorAccentLight = Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)
private let editorTextPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
private let editorTextSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
private let editorTextMuted = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
private let editorGlassBorder = Color.white.opacity(0.5)

private let accentGradient = LinearGradient(
    colors: [editorAccent, editorAccentLight],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

// MARK: - Pending attachment

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

// MARK: - Post Editor Popup

struct PostEditorPopup: View {
    @Binding var isPresented: Bool
    let accessToken: String
    var initialAttachments: [PendingPostAttachment] = []
    var initialTitle: String? = nil
    var initialBody: String? = nil
    var initialCourseId: String? = nil
    var prepareInitialAttachments: (() async -> [PendingPostAttachment])? = nil
    let onPublished: (CommunityPost) -> Void
    let submit: (CreatePostRequest) async throws -> CommunityPost

    @State private var postTitle: String
    @State private var postBody: String
    @State private var hashtags: [String] = []
    @State private var hashtagInput = ""
    @State private var hashtagSuggestions: [HashtagSuggestion] = []
    @State private var hashtagSearchTask: Task<Void, Never>?
    @State private var attachments: [PendingPostAttachment] = []
    @State private var showFileImporter = false
    @State private var visibility: String = "public"
    @State private var errorMessage: String?
    @State private var titleError: String?
    @State private var bodyError: String?
    @State private var isPublishing: Bool = false
    @State private var isPreparingInitialAttachments = false
    @FocusState private var titleFocused: Bool

    init(
        isPresented: Binding<Bool>,
        accessToken: String,
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
    private static let maxHashtags = 20
    private static let maxTitle = 255
    private static let maxBody = 10_000

    private var trimmedTitle: String { postTitle.trimmingCharacters(in: .whitespaces) }
    private var trimmedBody: String { postBody.trimmingCharacters(in: .whitespaces) }

    private var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedBody.isEmpty
            && !isPublishing
            && !isPreparingInitialAttachments
            && !attachments.contains { $0.status == .preparing }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.12))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    titleField
                    bodyField
                    attachmentSection
                    hashtagSection
                    visibilitySection
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0xC4/255, green: 0x44/255, blue: 0x44/255))
                            .padding(.bottom, 12)
                    }
                    publishButton
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 540, maxHeight: 720)
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
            .padding(.horizontal, 32)
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
                titleFocused = true
            }
        }
        .task {
            await prepareInitialAttachmentsIfNeeded()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    private func dismiss() {
        titleFocused = false
        hashtagSearchTask?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                Circle()
                    .fill(editorAccent.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "person")
                            .font(.system(size: 16))
                            .foregroundStyle(editorAccent)
                    }
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
                        .fill(titleError == nil ? Color.black.opacity(0.06) : Color.red.opacity(0.4))
                        .frame(height: 1.5)
                }

            if let titleError {
                Text(titleError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC4/255, green: 0x44/255, blue: 0x44/255))
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
            TextField("Write your post content…", text: $postBody, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(editorTextPrimary)
                .lineLimit(4...8)

            if let bodyError {
                Text(bodyError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0xC4/255, green: 0x44/255, blue: 0x44/255))
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Attachments

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Attached PDFs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(editorTextMuted)
                Spacer()
                Text("\(attachments.count) / \(Self.maxAttachments)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(editorTextMuted)
            }

            Button {
                showFileImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 14))
                    Text("Attach PDF")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(editorAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(editorAccent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(editorAccent.opacity(0.15), lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)
            .disabled(attachments.count >= Self.maxAttachments)
            .opacity(attachments.count >= Self.maxAttachments ? 0.5 : 1)

            ForEach(attachments) { attachment in
                attachmentRow(attachment)
            }
        }
        .padding(.bottom, 18)
    }

    private func attachmentRow(_ attachment: PendingPostAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(editorAccent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(editorAccent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(editorTextPrimary)
                    .lineLimit(1)

                Text(statusLabel(attachment.status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(attachment.status))
            }

            Spacer(minLength: 0)

            if attachment.status == .preparing || attachment.status == .uploading {
                ProgressView()
                    .scaleEffect(0.7)
            } else if !attachment.isLocked {
                Button {
                    attachments.removeAll { $0.id == attachment.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(editorTextMuted)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(editorAccent.opacity(0.7))
                    .frame(width: 22, height: 22)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
    }

    private func statusLabel(_ status: PendingPostAttachment.Status) -> String {
        switch status {
        case .preparing: return "Preparing current note..."
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
        case .failed: return Color(red: 0xC4/255, green: 0x44/255, blue: 0x44/255)
        }
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

    // MARK: - Hashtags

    private var hashtagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hashtags")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(editorTextMuted)
                Spacer()
                Text("\(hashtags.count) / \(Self.maxHashtags)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(editorTextMuted)
            }

            if !hashtags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(hashtags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text("#\(tag)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(editorAccent)
                            Button {
                                hashtags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(editorAccent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(editorAccent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(editorAccent.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add a hashtag (no #)…", text: $hashtagInput)
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
                    .onSubmit { addHashtag(hashtagInput) }
                    .onChange(of: hashtagInput) { _, newValue in
                        scheduleHashtagSearch(prefix: newValue)
                    }

                if !hashtagInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        addHashtag(hashtagInput)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: editorAccent.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(hashtags.count >= Self.maxHashtags)
                }
            }

            if !hashtagSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(hashtagSuggestions) { suggestion in
                        Button {
                            addHashtag(suggestion.name)
                        } label: {
                            HStack {
                                Text("#\(suggestion.name)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(editorTextPrimary)
                                Spacer()
                                Text("\(suggestion.postCount) post\(suggestion.postCount == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(editorTextMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if suggestion.id != hashtagSuggestions.last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.9))
                        }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(editorGlassBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            }
        }
        .padding(.bottom, 18)
    }

    private func addHashtag(_ raw: String) {
        let normalized = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        guard !normalized.isEmpty,
              !hashtags.contains(normalized),
              hashtags.count < Self.maxHashtags else { return }
        hashtags.append(normalized)
        hashtagInput = ""
        hashtagSuggestions = []
    }

    /// 250 ms debounced lookup against `search-hashtags`. The previous
    /// search is cancelled on every keystroke so only the latest prefix
    /// hits the network.
    private func scheduleHashtagSearch(prefix: String) {
        hashtagSearchTask?.cancel()
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard trimmed.count >= 1 else {
            hashtagSuggestions = []
            return
        }
        hashtagSearchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            do {
                let results = try await CommunityService.shared.searchHashtags(
                    prefix: trimmed,
                    limit: 6,
                    accessToken: accessToken
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    // Hide tags the user already added.
                    self.hashtagSuggestions = results.filter { !hashtags.contains($0.name) }
                }
            } catch {
                // Silent fallback — autocomplete is a nicety, not required.
                if Task.isCancelled { return }
                await MainActor.run { self.hashtagSuggestions = [] }
            }
        }
    }

    // MARK: - Visibility

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visibility")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorTextMuted)

            HStack(spacing: 8) {
                EditorChannelButton(icon: "globe", label: "Public", isActive: visibility == "public") {
                    visibility = "public"
                }
                EditorChannelButton(icon: "lock", label: "Private", isActive: visibility == "private") {
                    visibility = "private"
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

    // MARK: - Submit flow

    private func publish() async {
        guard !isPublishing else { return }
        titleError = nil
        bodyError = nil
        errorMessage = nil

        // Client-side validation matching the server's contract.
        if trimmedTitle.isEmpty {
            titleError = "Title is required."
            return
        }
        if trimmedTitle.count > Self.maxTitle {
            titleError = "Title can't exceed \(Self.maxTitle) characters."
            return
        }
        if trimmedBody.isEmpty {
            bodyError = "Body is required."
            return
        }
        if trimmedBody.count > Self.maxBody {
            bodyError = "Body can't exceed \(Self.maxBody) characters."
            return
        }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let uploadedIds = try await uploadAttachments()
            let request = CreatePostRequest(
                title: trimmedTitle,
                body: trimmedBody,
                visibility: visibility,
                courseId: initialCourseId ?? attachments.first(where: { $0.courseId != nil })?.courseId,
                attachmentNoteIds: uploadedIds.isEmpty ? nil : uploadedIds,
                hashtags: hashtags.isEmpty ? nil : hashtags
            )
            let created = try await submit(request)
            onPublished(created)
            dismiss()
        } catch let error as CommunityError {
            errorMessage = error.userMessage
        } catch {
            let mapped = mapCommunityError(error)
            errorMessage = mapped.userMessage
        }
    }

    /// Sequentially uploads every attachment that isn't already `.uploaded`.
    /// Sequential (not parallel) keeps the per-row status indicators in
    /// sync with what's actually happening on the wire.
    private func uploadAttachments() async throws -> [String] {
        var ids: [String] = []
        for index in attachments.indices {
            let item = attachments[index]
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
                // Shouldn't happen because we await sequentially, but in
                // case it does, just wait for the existing upload to land.
                throw APIError.serverError("An attachment upload is already in progress.")
            }
        }
        return ids
    }
}

// MARK: - Channel Button

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
