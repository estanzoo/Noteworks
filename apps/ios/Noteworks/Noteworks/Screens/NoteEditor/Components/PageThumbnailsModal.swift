//
//  PageThumbnailsModal.swift
//  Noteworks
//
//  Full-screen Page Thumbnails sheet from NoteWorks_UI 4
//  (`PageThumbnailsModal` / `PagePreviewThumb` in noteworks-library.jsx).
//
//  • Tap a thumbnail → jump to that page and dismiss.
//  • Drag a thumbnail → reorder pages (when not in select mode).
//  • Select → multi-select toolbar with Rotate / Share / Delete.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Rotate options (mirrors JSX `rotateOptions`)

private struct PageRotateOption: Identifiable {
    let id: String
    let label: String
    let rotation: Int
    let symbol: String

    static let all: [PageRotateOption] = [
        PageRotateOption(id: "cw90", label: "Rotate 90° clockwise", rotation: 90, symbol: "rotate.right"),
        PageRotateOption(id: "ccw90", label: "Rotate 90° counterclockwise", rotation: 270, symbol: "rotate.left"),
        PageRotateOption(id: "flip180", label: "Rotate 180°", rotation: 180, symbol: "arrow.triangle.2.circlepath")
    ]
}

private struct RotateButtonAnchorKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

// MARK: - Modal

struct PageThumbnailsModal: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    @ObservedObject var store: NotesStore
    var onClose: () -> Void
    var onSharePages: ([Int]) -> Void

    @State private var selectMode = false
    @State private var selectedPages: Set<Int> = []
    @State private var rotateMenuOpen = false
    @State private var rotateButtonFrame: CGRect = .zero
    @State private var deleteConfirmOpen = false
    @State private var draggingPage: Int?

    private var pageSettings: [NotePageSetting] {
        viewModel.pageSettingsSnapshot(store: store)
    }

    private var pages: [Int] {
        Array(1...max(1, viewModel.totalPages))
    }

    private var hasSelection: Bool { !selectedPages.isEmpty }

    var body: some View {
        ZStack {
            Color(red: 198/255, green: 212/255, blue: 228/255).opacity(0.36)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            modalCard

            if deleteConfirmOpen {
                deleteConfirmOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            resetSelectionState()
        }
        .onChange(of: viewModel.currentPage) { _, _ in
            if !selectMode {
                selectedPages = []
            }
        }
    }

    private var modalCard: some View {
        GeometryReader { proxy in
            let modalWidth = min(1060, proxy.size.width - 40)
            let modalHeight = min(proxy.size.height * 0.84, max(320, proxy.size.height - 72))

            VStack(spacing: 0) {
                headerBar
                if selectMode {
                    selectToolbar
                }
                thumbnailGrid
            }
            .coordinateSpace(name: "PageThumbnailsModal")
            .overlay(alignment: .topLeading) {
                if rotateMenuOpen, selectMode, hasSelection {
                    rotateDropdownMenu
                        .offset(
                            x: rotateButtonFrame.minX,
                            y: rotateButtonFrame.maxY + 8
                        )
                        .zIndex(40)
                }
            }
            .onPreferenceChange(RotateButtonAnchorKey.self) { rotateButtonFrame = $0 }
            .frame(width: modalWidth, height: modalHeight)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 250/255, green: 252/255, blue: 254/255).opacity(0.98),
                        Color(red: 241/255, green: 246/255, blue: 250/255).opacity(0.97)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
            )
            .shadow(color: Color(red: 65/255, green: 82/255, blue: 105/255).opacity(0.22), radius: 38, y: 18)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Button("Done") { onClose() }
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(NoteEditorTheme.accent)

            Spacer()

            VStack(spacing: 3) {
                Text("Page Thumbnails")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                Text(selectMode ? "\(selectedPages.count) selected" : "Drag to rearrange pages")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
            }

            Spacer()

            Button(selectMode ? "Cancel" : "Select") {
                if selectMode {
                    leaveSelectMode()
                } else {
                    selectMode = true
                }
            }
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(selectMode ? NoteEditorTheme.danger : NoteEditorTheme.accent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 210/255, green: 222/255, blue: 234/255).opacity(0.66))
                .frame(height: 1)
        }
    }

    // MARK: - Select toolbar

    private var selectToolbar: some View {
        HStack(spacing: 10) {
            ThumbnailActionButton(title: "Rotate", showsChevron: true, disabled: !hasSelection) {
                guard hasSelection else { return }
                rotateMenuOpen.toggle()
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: RotateButtonAnchorKey.self,
                        value: geo.frame(in: .named("PageThumbnailsModal"))
                    )
                }
            }

            ThumbnailActionButton(title: "Share", disabled: !hasSelection) {
                guard hasSelection else { return }
                onSharePages(Array(selectedPages).sorted())
            }

            ThumbnailActionButton(title: "Delete", disabled: !hasSelection, tint: NoteEditorTheme.danger) {
                guard hasSelection else { return }
                rotateMenuOpen = false
                deleteConfirmOpen = true
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.36))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 210/255, green: 222/255, blue: 234/255).opacity(0.55))
                .frame(height: 1)
        }
    }

    private var rotateDropdownMenu: some View {
        VStack(spacing: 8) {
            ForEach(PageRotateOption.all) { option in
                Button {
                    viewModel.rotatePages(Array(selectedPages).sorted(), to: option.rotation)
                    rotateMenuOpen = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NoteEditorTheme.accent)
                            .frame(width: 18)
                        Text(option.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(NoteEditorTheme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(red: 217/255, green: 225/255, blue: 233/255).opacity(0.92), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 264, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(NoteEditorTheme.glassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
    }

    // MARK: - Grid

    private var thumbnailGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 156, maximum: 200), spacing: 22)],
                    spacing: 22
                ) {
                    ForEach(pages, id: \.self) { pageNumber in
                        let setting = pageNumber <= pageSettings.count
                            ? pageSettings[pageNumber - 1]
                            : NotePageSetting()
                        PagePreviewThumb(
                            viewModel: viewModel,
                            store: store,
                            pageNumber: pageNumber,
                            setting: setting,
                            isCurrent: pageNumber == viewModel.currentPage,
                            isSelected: selectedPages.contains(pageNumber),
                            selectMode: selectMode,
                            isDragging: draggingPage == pageNumber
                        ) {
                            if selectMode {
                                togglePage(pageNumber)
                            } else {
                                viewModel.goToPage(pageNumber)
                                onClose()
                            }
                        }
                        .id(pageNumber)
                        .opacity(selectMode ? 1 : (draggingPage == pageNumber ? 0.7 : 1))
                        .onDrag {
                            guard !selectMode else { return NSItemProvider() }
                            draggingPage = pageNumber
                            return NSItemProvider(object: "\(pageNumber)" as NSString)
                        }
                        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                            guard !selectMode else { return false }
                            guard let provider = providers.first else { return false }
                            provider.loadObject(ofClass: NSString.self) { object, _ in
                                guard let raw = object as? String,
                                      let fromPage = Int(raw),
                                      fromPage != pageNumber else { return }
                                DispatchQueue.main.async {
                                    viewModel.reorderPages(from: fromPage, to: pageNumber)
                                    draggingPage = nil
                                }
                            }
                            return true
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(viewModel.currentPage, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Delete confirm

    private var deleteConfirmOverlay: some View {
        ZStack {
            Color(red: 210/255, green: 222/255, blue: 234/255).opacity(0.42)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { deleteConfirmOpen = false }

            VStack(alignment: .leading, spacing: 0) {
                Text("Delete pages?")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                Text("Are you sure you want to delete the selected pages? This action cannot be undone.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textSecondary)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.bottom, 22)

                HStack {
                    Spacer()
                    ThumbnailActionButton(title: "Cancel") {
                        deleteConfirmOpen = false
                    }
                    ThumbnailActionButton(title: "Delete", tint: NoteEditorTheme.danger) {
                        viewModel.deletePages(Array(selectedPages).sorted())
                        deleteConfirmOpen = false
                        leaveSelectMode()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 440)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color(red: 248/255, green: 251/255, blue: 254/255).opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.86), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
            .padding(24)
        }
        .zIndex(50)
    }

    // MARK: - Helpers

    private func togglePage(_ pageNumber: Int) {
        if selectedPages.contains(pageNumber) {
            selectedPages.remove(pageNumber)
        } else {
            selectedPages.insert(pageNumber)
        }
    }

    private func leaveSelectMode() {
        selectMode = false
        selectedPages = []
        rotateMenuOpen = false
    }

    private func resetSelectionState() {
        selectMode = false
        selectedPages = []
        rotateMenuOpen = false
        deleteConfirmOpen = false
        draggingPage = nil
    }
}

// MARK: - Preview thumb

private struct PagePreviewThumb: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    @ObservedObject var store: NotesStore
    let pageNumber: Int
    let setting: NotePageSetting
    let isCurrent: Bool
    let isSelected: Bool
    let selectMode: Bool
    let isDragging: Bool
    let action: () -> Void

    private var landscape: Bool { abs(setting.rotation % 180) == 90 }

    private var sheetSize: CGSize {
        if landscape {
            return CGSize(width: 160, height: 112)
        }
        return CGSize(width: 112, height: 160)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 255/255, green: 253/255, blue: 241/255))
                        .frame(width: sheetSize.width, height: sheetSize.height)
                        .overlay {
                            PageThumbnailPreview(
                                viewModel: viewModel,
                                store: store,
                                pageNumber: pageNumber,
                                setting: setting,
                                sheetSize: sheetSize
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(red: 210/255, green: 220/255, blue: 230/255).opacity(0.72), lineWidth: 1)
                        )
                        .shadow(color: Color(red: 74/255, green: 92/255, blue: 115/255).opacity(0.12), radius: 10, y: 6)

                    if selectMode, isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 112/255, green: 191/255, blue: 222/255),
                                        NoteEditorTheme.accent
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .shadow(color: NoteEditorTheme.accent.opacity(0.28), radius: 8, y: 4)
                            .offset(x: sheetSize.width * 0.34, y: sheetSize.height * 0.34)
                    }
                }

                Text("Page \(pageNumber)\(isCurrent ? " (Current)" : "")")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(isCurrent ? NoteEditorTheme.accent : NoteEditorTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? NoteEditorTheme.accent.opacity(0.78)
                            : (isCurrent ? NoteEditorTheme.accent.opacity(0.45) : Color.white.opacity(0.78)),
                        lineWidth: isSelected || isCurrent ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected
                    ? NoteEditorTheme.accent.opacity(0.2)
                    : Color(red: 65/255, green: 82/255, blue: 105/255).opacity(isDragging ? 0.2 : 0.1),
                radius: isDragging ? 20 : 14,
                y: isDragging ? 12 : 8
            )
            .scaleEffect(isDragging ? 1.03 : 1)
            .rotationEffect(isDragging ? .degrees(-1) : .zero)
            .animation(.easeOut(duration: 0.18), value: isDragging)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page thumbnail image

private struct PageThumbnailPreview: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    @ObservedObject var store: NotesStore
    let pageNumber: Int
    let setting: NotePageSetting
    let sheetSize: CGSize

    @State private var image: UIImage?

    private var cacheKey: String {
        let noteStamp: String
        if let noteId = viewModel.noteId, let note = store.note(id: noteId) {
            noteStamp = "\(noteId)-\(Int(note.updatedAt.timeIntervalSince1970))"
        } else {
            noteStamp = "missing"
        }
        let liveToken = pageNumber == viewModel.currentPage
            ? "-live-\(viewModel.drawingPushGeneration)"
            : ""
        return "\(noteStamp)-p\(pageNumber)-r\(setting.rotation)-bg\(setting.background.rawValue)\(liveToken)"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: sheetSize.width, height: sheetSize.height)
            }
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .task(id: cacheKey) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        if let cached = PageThumbnailCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        guard let noteId = viewModel.noteId, let note = store.note(id: noteId) else { return }

        let pixelScale = UIScreen.main.scale
        let targetSize = CGSize(
            width: sheetSize.width * pixelScale,
            height: sheetSize.height * pixelScale
        )

        let rendered = PDFStorageService.shared.renderPageImage(
            note: note,
            store: store,
            pageNumber: pageNumber,
            livePage: viewModel.currentPage,
            liveDrawing: viewModel.canonicalLiveDrawing,
            targetSize: targetSize
        )

        guard !Task.isCancelled else { return }

        if let rendered {
            PageThumbnailCache.shared.store(rendered, for: cacheKey)
            image = rendered
        }
    }
}

private final class PageThumbnailCache {
    static let shared = PageThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 128
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

// MARK: - Action button

private struct ThumbnailActionButton: View {
    let title: String
    var showsChevron: Bool = false
    var disabled: Bool = false
    var tint: Color = NoteEditorTheme.textPrimary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(disabled ? NoteEditorTheme.textSecondary.opacity(0.5) : tint)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(disabled ? NoteEditorTheme.textSecondary.opacity(0.5) : tint)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(
                disabled ? Color.white.opacity(0.42) : Color.white.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(red: 217/255, green: 225/255, blue: 233/255).opacity(0.92), lineWidth: 1)
            )
            .shadow(color: disabled ? .clear : .black.opacity(0.06), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
