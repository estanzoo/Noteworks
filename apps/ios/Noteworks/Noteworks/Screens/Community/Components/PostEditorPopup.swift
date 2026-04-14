//
//  PostEditorPopup.swift
//  Noteworks
//

import SwiftUI

// MARK: - Constants

private let editorAccent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)
private let editorAccentLight = Color(red: 0x7C/255, green: 0xC4/255, blue: 0xE4/255)
private let editorTextPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
private let editorTextSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.5)
private let editorTextMuted = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3)
private let editorGlassBorder = Color.white.opacity(0.5)

private let editorCourseOptions = [
    "Biology", "Chemistry", "Physics", "Philosophy",
    "Mathematics", "Computer Science", "Art", "English", "Psychology", "Other"
]
private let editorTagOptions = [
    "Study Tips", "Question", "Exam Prep", "Group Study",
    "Resource", "Discussion", "Announcement"
]

private let accentGradient = LinearGradient(
    colors: [editorAccent, editorAccentLight],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

// MARK: - Publish Payload

struct NewPostPayload {
    let title: String
    let body: String?
    let tags: [String]
    let category: String
}

// MARK: - Post Editor Popup

struct PostEditorPopup: View {
    @Binding var isPresented: Bool
    let onPublish: (NewPostPayload) -> Void

    @State private var postTitle = ""
    @State private var postBody = ""
    @State private var selectedTags: Set<String> = []
    @State private var customTags: [String] = []
    @State private var customTagInput = ""
    @State private var selectedCourse: String? = nil
    @State private var courseDropdownOpen = false
    @State private var category = "Discussions"
    @FocusState private var titleFocused: Bool

    private var canPublish: Bool {
        !postTitle.trimmingCharacters(in: .whitespaces).isEmpty
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
                    attachmentButtons
                    courseSection
                    tagsSection
                    postToSection
                    publishButton
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 540, maxHeight: 680)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                titleFocused = true
            }
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

    // MARK: - Title Field

    private var titleField: some View {
        TextField("Enter your title...", text: $postTitle)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(editorTextPrimary)
            .focused($titleFocused)
            .textInputAutocapitalization(.sentences)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 1.5)
            }
            .padding(.bottom, 16)
    }

    // MARK: - Body Field

    private var bodyField: some View {
        TextField("Write your post content... (optional)", text: $postBody, axis: .vertical)
            .font(.system(size: 15))
            .foregroundStyle(editorTextPrimary)
            .lineLimit(4...8)
            .padding(.bottom, 12)
    }

    // MARK: - Attachment Buttons

    private var attachmentButtons: some View {
        HStack(spacing: 10) {
            EditorAttachButton(icon: "photo", label: "Photo / Video")
            EditorAttachButton(icon: "doc", label: "Document")
            EditorAttachButton(icon: "doc.text", label: "Note")
        }
        .padding(.bottom, 16)
    }

    // MARK: - Course Section

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Course")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorTextMuted)

            ZStack(alignment: .top) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        courseDropdownOpen.toggle()
                    }
                } label: {
                    HStack {
                        Text(selectedCourse ?? "Select a course...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedCourse != nil ? editorTextPrimary : editorTextMuted)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(editorTextMuted)
                            .rotationEffect(.degrees(courseDropdownOpen ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                courseDropdownOpen ? editorAccent.opacity(0.5) : Color.black.opacity(0.06),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(color: courseDropdownOpen ? editorAccent.opacity(0.08) : .clear, radius: 3)
                }
                .buttonStyle(.plain)
                .zIndex(1)

                if courseDropdownOpen {
                    ScrollView {
                        VStack(spacing: 0) {
                            if selectedCourse != nil {
                                courseOptionRow(label: "Clear selection", active: false, dimmed: true) {
                                    selectedCourse = nil
                                    withAnimation { courseDropdownOpen = false }
                                }
                            }

                            ForEach(editorCourseOptions, id: \.self) { course in
                                courseOptionRow(
                                    label: course,
                                    active: selectedCourse == course,
                                    dimmed: false
                                ) {
                                    selectedCourse = course
                                    withAnimation { courseDropdownOpen = false }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.9))
                            }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(editorGlassBorder, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 16, y: 4)
                    .offset(y: 48)
                    .zIndex(10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.bottom, 16)
        .zIndex(courseDropdownOpen ? 100 : 1)
    }

    private func courseOptionRow(label: String, active: Bool, dimmed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(editorAccent)
                        .frame(width: 16)
                } else if dimmed {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(editorTextMuted)
                        .frame(width: 16)
                } else {
                    Spacer().frame(width: 16)
                }

                Text(label)
                    .font(.system(size: 15, weight: active ? .semibold : .regular))
                    .foregroundStyle(dimmed ? editorTextMuted : editorTextPrimary)
                    .italic(dimmed)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(active ? editorAccent.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorTextMuted)

            WrappingHStack(items: editorTagOptions, spacing: 8, lineSpacing: 8) { tag in
                EditorTagChip(
                    label: tag,
                    isActive: selectedTags.contains(tag)
                ) {
                    if selectedTags.contains(tag) {
                        selectedTags.remove(tag)
                    } else {
                        selectedTags.insert(tag)
                    }
                }
            }

            if !customTags.isEmpty {
                WrappingHStack(items: customTags, spacing: 8, lineSpacing: 8) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(editorAccent)
                        Button {
                            customTags.removeAll { $0 == tag }
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

            HStack(spacing: 8) {
                TextField("Add custom tag...", text: $customTagInput)
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
                    .onSubmit { addCustomTag() }

                if !customTagInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { addCustomTag() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: editorAccent.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.bottom, 20)
    }

    private func addCustomTag() {
        let trimmed = customTagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !customTags.contains(trimmed),
              !editorTagOptions.contains(trimmed) else { return }
        customTags.append(trimmed)
        customTagInput = ""
    }

    // MARK: - Post To Section

    private var postToSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Post to")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorTextMuted)

            HStack(spacing: 8) {
                EditorChannelButton(icon: "doc.text", label: "Note", isActive: category == "Note") {
                    category = "Note"
                }
                EditorChannelButton(icon: "questionmark.circle", label: "Questions", isActive: category == "Study Questions") {
                    category = "Study Questions"
                }
                EditorChannelButton(icon: "bubble.right", label: "Discussions", isActive: category == "Discussions") {
                    category = "Discussions"
                }
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Publish Button

    private var publishButton: some View {
        Button {
            guard canPublish else { return }
            let allTags = (selectedCourse.map { [$0] } ?? []) + Array(selectedTags) + customTags
            let trimmedBody = postBody.trimmingCharacters(in: .whitespaces)
            onPublish(NewPostPayload(
                title: postTitle.trimmingCharacters(in: .whitespaces),
                body: trimmedBody.isEmpty ? nil : trimmedBody,
                tags: allTags.isEmpty ? ["General"] : allTags,
                category: category
            ))
            dismiss()
        } label: {
            Text("Publish")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(canPublish ? .white : editorTextMuted)
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
}

// MARK: - Attachment Button

private struct EditorAttachButton: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(editorAccent)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editorAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(editorAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(editorAccent.opacity(0.15), lineWidth: 1.5)
        }
    }
}

// MARK: - Tag Chip

private struct EditorTagChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? editorAccent : editorTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isActive ? editorAccent.opacity(0.1) : Color.white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isActive ? editorAccent.opacity(0.5) : Color.black.opacity(0.06),
                            lineWidth: 1.5
                        )
                }
        }
        .buttonStyle(.plain)
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

// MARK: - Wrapping HStack (flow layout for tags)

private struct WrappingHStack<Item: Hashable, ItemView: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: (Item) -> ItemView

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geo in
            generateContent(in: geo)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, spacing)
                    .padding(.bottom, lineSpacing)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width {
                            width = 0
                            height -= d.height + lineSpacing
                        }
                        let result = width
                        if item == items.last {
                            width = 0
                        } else {
                            width -= d.width + spacing
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: HeightKey.self, value: geo.size.height)
        }
        .onPreferenceChange(HeightKey.self) { binding.wrappedValue = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
