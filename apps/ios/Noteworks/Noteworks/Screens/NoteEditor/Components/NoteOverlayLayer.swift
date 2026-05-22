//
//  NoteOverlayLayer.swift
//  Noteworks
//
//  Transparent SwiftUI layer rendered on top of `PKCanvasView` to host the
//  things PencilKit can't: text boxes and dropped-in images. Each overlay
//  item is positioned in normalized [0…1] page coordinates so it survives
//  rotation / device size changes; this view converts those to absolute
//  points against the page rect.
//
//  Interaction model:
//    - Text overlays: corner resize + inline edit.
//    - Image overlays: GoodNotes-style selection — blue frame, 8 handles,
//      rotation knob, floating adjust toolbar (crop / duplicate / delete…).
//

import SwiftUI
import UIKit

struct NoteOverlayLayer: View {
    let overlays: [NotePageOverlay]
    /// **Scaled** page size — `baseLogicalPageSize * canvasZoom`.
    /// Overlay positions are stored in normalized [0..1] coordinates so
    /// multiplying by the scaled page size scales them with zoom for
    /// free. Text font size scales explicitly via `zoomScale` below so
    /// SwiftUI re-rasterises labels at the new scale instead of
    /// bitmap-stretching them.
    let pageSize: CGSize
    /// Current page zoom (1.0 = fit). Used to scale text font sizes so
    /// inline text overlays stay sharp at high zoom.
    var zoomScale: CGFloat = 1.0
    let noteId: String
    /// When true (Select tool), overlays accept finger and Pencil for
    /// tap-to-select and drag-to-move.
    var manipulationMode: Bool = false
    @Binding var selectedId: String?
    /// Currently inline-editing text overlay (focused TextField). Set
    /// when the user inserts a fresh text overlay or taps an existing
    /// one again. Cleared when the user submits or taps off.
    @Binding var editingId: String?

    /// Called when the user moves / resizes an overlay. The caller writes
    /// it back into `NotesStore` with `updateOverlay(...)`.
    var onUpdate: (NotePageOverlay) -> Void

    /// Called when the user taps the "X" on a selected overlay.
    var onDelete: (NotePageOverlay) -> Void

    var onDuplicate: (NotePageOverlay) -> Void = { _ in }
    var onSelectLasso: () -> Void = {}
    var onCropImage: (NotePageOverlay) -> Void = { _ in }
    var onOverlayDragChanged: (Bool) -> Void = { _ in }

    /// Looks up the image data for a `.image` overlay. Wired to
    /// `NotesStore.loadOverlayImageData` so this view stays presentation
    /// only.
    var imageDataProvider: (String) -> Data?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(overlays) { overlay in
                NoteOverlayItem(
                    overlay: overlay,
                    pageSize: pageSize,
                    manipulationMode: manipulationMode,
                    zoomScale: zoomScale,
                    isSelected: overlay.id == selectedId,
                    isEditing: overlay.id == editingId,
                    noteId: noteId,
                    imageDataProvider: imageDataProvider,
                    onUpdate: onUpdate,
                    onDelete: {
                        if editingId == overlay.id { editingId = nil }
                        onDelete(overlay)
                        selectedId = nil
                    },
                    onDuplicate: onDuplicate,
                    onSelectLasso: onSelectLasso,
                    onCropImage: { onCropImage(overlay) },
                    onSelect: {
                        selectedId = overlay.id
                        editingId = nil
                    },
                    onDeselect: {
                        if selectedId == overlay.id {
                            selectedId = nil
                            editingId = nil
                        }
                    },
                    onStartEditing: {
                        selectedId = overlay.id
                        editingId = overlay.id
                    },
                    onCommitEditing: { newText in
                        var updated = overlay
                        updated.text = newText
                        onUpdate(updated)
                        editingId = nil
                    },
                    onDragChanged: onOverlayDragChanged
                )
            }
        }
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        // Do not clip the layer — the floating adjust toolbar sits
        // above the sticker (negative Y offset) and corner handles
        // extend outside the sticker bounds. Clipping here made those
        // controls invisible to hit-testing even when drawn on screen.
        .allowsHitTesting(manipulationMode || selectedId != nil || editingId != nil)
    }
}

// MARK: - Image adjust toolbar geometry (shared with editor + scroll view)

/// Buttons on the floating image adjust toolbar (left → right).
enum ImageOverlayAdjustToolbarButton: Int, CaseIterable {
    case crop = 0
    case lasso = 1
    case cut = 2
    case duplicate = 3
    case delete = 4
    case more = 5
}

enum ImageOverlayAdjustToolbarMetrics {
    static let width: CGFloat = 280
    /// Matches padded toolbar chrome (icons + vertical padding).
    static let height: CGFloat = 48
    /// Distance from the sticker's top edge to the toolbar's top edge.
    static let gapAboveSticker: CGFloat = 52
    static let buttonCount = 6

    /// Base-coordinate rect for the floating toolbar above a sticker.
    static func frame(above stickerFrame: CGRect) -> CGRect {
        CGRect(
            x: stickerFrame.midX - width / 2,
            y: stickerFrame.minY - gapAboveSticker,
            width: width,
            height: height
        )
    }

    /// Maps a page-coordinate touch to a toolbar button (equal-width slots).
    static func button(at point: CGPoint, in toolbarFrame: CGRect) -> ImageOverlayAdjustToolbarButton? {
        guard toolbarFrame.contains(point) else { return nil }
        let localX = point.x - toolbarFrame.minX
        let slotWidth = toolbarFrame.width / CGFloat(buttonCount)
        let index = min(buttonCount - 1, max(0, Int(localX / slotWidth)))
        return ImageOverlayAdjustToolbarButton(rawValue: index)
    }
}

// MARK: - Single item

private struct NoteOverlayItem: View {
    let overlay: NotePageOverlay
    let pageSize: CGSize
    let manipulationMode: Bool
    let zoomScale: CGFloat
    let isSelected: Bool
    let isEditing: Bool
    let noteId: String
    var imageDataProvider: (String) -> Data?
    var onUpdate: (NotePageOverlay) -> Void
    var onDelete: () -> Void
    var onDuplicate: (NotePageOverlay) -> Void
    var onSelectLasso: () -> Void
    var onCropImage: () -> Void
    var onSelect: () -> Void
    var onDeselect: () -> Void
    /// Tap-on-already-selected-text starts inline editing.
    var onStartEditing: () -> Void
    /// TextField submit / focus-loss commits the new string.
    var onCommitEditing: (String) -> Void
    var onDragChanged: (Bool) -> Void

    /// Local working copy of the text while the user is typing. Synced
    /// from `overlay.text` when editing begins so the field starts with
    /// the latest committed value.
    @State private var draftText: String = ""
    @FocusState private var textFieldFocused: Bool

    /// Live resize offsets — `@State` persists until commit so the
    /// sticker does not snap back when the gesture ends.
    @State private var resizeTranslation: CGSize = .zero
    @State private var pinchScale: CGFloat = 1.0
    @State private var moveTranslation: CGSize = .zero

    private var isImage: Bool { overlay.kind == .image }
    private var isShape: Bool { overlay.kind == .shape }
    /// Image + shape share GoodNotes-style corner handles.
    private var usesFullTransformChrome: Bool { isImage || isShape }
    private var resolvedShapeType: NoteShapeType {
        NoteShapeOverlayDrawing.resolvedType(overlay.shapeType)
    }
    private var showsSelectionChrome: Bool { isSelected }
    private static let imageAccent = Color(red: 0.22, green: 0.48, blue: 0.98)

    private var basePoint: CGPoint {
        CGPoint(x: overlay.normX * pageSize.width, y: overlay.normY * pageSize.height)
    }
    private var baseSize: CGSize {
        CGSize(width: overlay.normW * pageSize.width, height: overlay.normH * pageSize.height)
    }
    /// Live size during a resize / pinch gesture.
    private var liveSize: CGSize {
        let resized = activeResizeGeometry(for: resizeTranslation)
        let pinched = CGSize(
            width: resized.size.width * pinchScale,
            height: resized.size.height * pinchScale
        )
        return CGSize(width: max(40, pinched.width), height: max(40, pinched.height))
    }
    /// Live origin during a move / pinch-resize gesture. Pinch anchors at
    /// the overlay center, so origin shifts to keep the visual center
    /// fixed while the size grows.
    private var liveOrigin: CGPoint {
        let resized = activeResizeGeometry(for: resizeTranslation)
        let pinchOriginShift = CGSize(
            width: (resized.size.width - resized.size.width * pinchScale) / 2,
            height: (resized.size.height - resized.size.height * pinchScale) / 2
        )
        return CGPoint(
            x: resized.origin.x + pinchOriginShift.width + moveTranslation.width,
            y: resized.origin.y + pinchOriginShift.height + moveTranslation.height
        )
    }

  /// Active corner/edge being resized; nil when moving only.
    @State private var activeResizeCorner: OverlayCorner?
    @State private var activeResizeEdge: OverlayEdge?

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageVisual

            if showsSelectionChrome {
                selectionInteraction
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .transaction { transaction in
            if resizeTranslation != .zero || pinchScale != 1.0 || moveTranslation != .zero {
                transaction.animation = nil
            }
        }
    }

    /// Image / text / shape drawing.
    ///
    /// MOVE and RESIZE are driven by a UIKit pan recognizer wired up
    /// inside `ZoomablePageScrollView` (see `onOverlayManipulation`).
    /// SwiftUI's `DragGesture` attached here lost the gesture race
    /// against the outer `UIScrollView`'s pan recognizer (the page
    /// panned instead of the sticker moving), so the body is left
    /// non-interactive at the SwiftUI layer and the scroll-view-
    /// level recognizer dispatches the deltas back through the
    /// `NotesStore`. Text overlays still keep SwiftUI hit-testing
    /// while inline-editing so the `TextField` actually receives
    /// keystrokes.
    private var pageVisual: some View {
        ZStack {
            content
                .frame(width: liveSize.width, height: liveSize.height)
                .background(itemBackground)
                .clipShape(RoundedRectangle(cornerRadius: usesFullTransformChrome ? 4 : 8))
                .overlay(selectionBorder)
                .allowsHitTesting(isEditing && overlay.kind == .text)
        }
        .frame(width: liveSize.width, height: liveSize.height)
        .rotationEffect(.degrees(usesFullTransformChrome ? overlay.rotationDegrees : 0))
        .offset(x: liveOrigin.x, y: liveOrigin.y)
        .allowsHitTesting(isEditing && overlay.kind == .text)
    }

    /// Corner handles + floating toolbars — small targets only; the
    /// image body between handles stays transparent to pinch.
    private var selectionInteraction: some View {
        ZStack(alignment: .topLeading) {
            fourCornerHandles

            if usesFullTransformChrome {
                ImageOverlayAdjustToolbar()
                .offset(
                    x: max(0, (liveSize.width - ImageOverlayAdjustToolbarMetrics.width) / 2),
                    y: -ImageOverlayAdjustToolbarMetrics.gapAboveSticker
                )
                .zIndex(20)
                // Taps are handled by a UIKit recognizer on the outer
                // scroll view (`onOverlayAdjustToolbarTap`) — SwiftUI
                // buttons here never receive touches because
                // `PencilCanvasView` sits above this layer in the ZStack.
                .allowsHitTesting(false)
            }

            if overlay.kind == .text {
                SimpleTextOverlayToolbar(
                    fontSize: overlay.fontSize ?? 18,
                    onDecrease: { adjustFontSize(by: -2) },
                    onIncrease: { adjustFontSize(by: 2) },
                    onEdit: onStartEditing,
                    onDelete: onDelete
                )
                .offset(x: max(0, (liveSize.width - 200) / 2), y: -46)
            }
        }
        .rotationEffect(.degrees(usesFullTransformChrome ? overlay.rotationDegrees : 0))
        .offset(x: liveOrigin.x, y: liveOrigin.y)
    }

    // MARK: Handle geometry

    private enum OverlayCorner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }

        var offset: CGSize {
            switch self {
            case .topLeading: return CGSize(width: -11, height: -11)
            case .topTrailing: return CGSize(width: 11, height: -11)
            case .bottomLeading: return CGSize(width: -11, height: 11)
            case .bottomTrailing: return CGSize(width: 11, height: 11)
            }
        }
    }

    private enum OverlayEdge {
        case top, bottom, leading, trailing
    }

    // MARK: Content variants

    @ViewBuilder
    private var content: some View {
        switch overlay.kind {
        case .text:
            textContent
        case .image:
            ImageOverlayContent(noteId: noteId, filename: overlay.imageFilename ?? "", provider: imageDataProvider)
        case .shape:
            NoteShapeOverlayDrawing.shapeView(
                type: resolvedShapeType,
                color: NoteShapeOverlayDrawing.strokeColor(hex: overlay.colorHex)
            )
        }
    }

    /// Text overlay body — switches between a static `Text` and an inline
    /// `TextField` based on `isEditing`. The TextField uses `axis: .vertical`
    /// so the overlay box grows naturally as the user types multi-line
    /// content. The draft text is committed on every keystroke so the
    /// content survives the user dismissing the keyboard, tapping off,
    /// or page changes without an explicit save step.
    @ViewBuilder
    private var textContent: some View {
        let textColor = Color(hex: overlay.colorHex) ?? NoteEditorTheme.textPrimary
        // Scale point size by zoom so the text actually renders at the
        // resolution corresponding to its on-screen size — SwiftUI then
        // rasterises it crisply instead of bitmap-stretching a fixed-
        // size label.
        let scaledFontSize = max(2, (overlay.fontSize ?? 18) * zoomScale)
        let textFont = Font.system(size: scaledFontSize, weight: .medium)
        let scaledPadding: CGFloat = 8 * zoomScale
        if isEditing {
            TextField("Type text…", text: $draftText, axis: .vertical)
                .font(textFont)
                .foregroundStyle(textColor)
                .focused($textFieldFocused)
                .submitLabel(.done)
                .padding(scaledPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onAppear {
                    draftText = overlay.text ?? ""
                    DispatchQueue.main.async {
                        textFieldFocused = true
                    }
                }
                .onChange(of: draftText) { _, newText in
                    var updated = overlay
                    updated.text = newText
                    onUpdate(updated)
                }
                .onSubmit {
                    onCommitEditing(draftText)
                }
        } else {
            Text(overlay.text?.isEmpty == false ? overlay.text! : "Tap to edit")
                .font(textFont)
                .foregroundStyle(
                    overlay.text?.isEmpty == false
                        ? textColor
                        : textColor.opacity(0.45)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(scaledPadding)
        }
    }

    @ViewBuilder
    private var itemBackground: some View {
        if overlay.kind == .text {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(showsSelectionChrome ? 0.6 : 0.0))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.001))
        }
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if showsSelectionChrome {
            RoundedRectangle(cornerRadius: usesFullTransformChrome ? 4 : 8)
                .strokeBorder(Self.imageAccent, lineWidth: 1.5)
        }
    }

    private func adjustFontSize(by delta: CGFloat) {
        var updated = overlay
        let next = max(12, min(72, (updated.fontSize ?? 18) + delta))
        updated.fontSize = next
        onUpdate(updated)
    }

    // MARK: Handles

    /// Four blue corner handles — shared by text and image overlays.
    /// Visual only; the actual drag-to-resize is driven by the UIKit
    /// pan recognizer in `ZoomablePageScrollView` (the touch point
    /// is hit-tested against the handle bounding boxes there).
    private var fourCornerHandles: some View {
        ZStack(alignment: .topLeading) {
            ForEach(OverlayCorner.allCases, id: \.self) { corner in
                resizeHandle
                    .offset(handleOffset(for: corner))
            }
        }
        .allowsHitTesting(false)
    }

    private func handleOffset(for corner: OverlayCorner) -> CGSize {
        let pad: CGFloat = 11
        let handleSize: CGFloat = 36
        switch corner {
        case .topLeading:
            return CGSize(width: -pad, height: -pad)
        case .topTrailing:
            return CGSize(width: max(0, liveSize.width - handleSize + pad), height: -pad)
        case .bottomLeading:
            return CGSize(width: -pad, height: max(0, liveSize.height - handleSize + pad))
        case .bottomTrailing:
            return CGSize(
                width: max(0, liveSize.width - handleSize + pad),
                height: max(0, liveSize.height - handleSize + pad)
            )
        }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Self.imageAccent)
            .frame(width: 11, height: 11)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    // MARK: Gestures

    // SwiftUI move/resize gestures used to live here; they consistently
    // lost the gesture race against the outer scroll view's pan
    // recognizer, leaving stickers unmovable. Manipulation is now
    // driven by a UIKit `UIPanGestureRecognizer` in
    // `ZoomablePageScrollView` and routed through
    // `NoteEditorView.handleOverlayManipulation`. This view stays
    // pure presentation so the SwiftUI tree never claims a touch the
    // scroll view also wants.

    private func activeResizeGeometry(for translation: CGSize) -> (origin: CGPoint, size: CGSize) {
        if let corner = activeResizeCorner {
            return resized(corner: corner, edge: nil, translation: translation)
        }
        if let edge = activeResizeEdge {
            return resized(corner: nil, edge: edge, translation: translation)
        }
        return (basePoint, baseSize)
    }

    /// Geometry math kept for the (still-SwiftUI-driven) pinch-to-
    /// resize gesture path, which is not yet exercised by the new
    /// UIKit pan flow. Left in place so re-introducing pinch-to-
    /// resize doesn't require rewriting the math from scratch.
    private func resized(corner: OverlayCorner?, edge: OverlayEdge?, translation: CGSize) -> (CGPoint, CGSize) {
        var newOriginX = basePoint.x
        var newOriginY = basePoint.y
        var newW = baseSize.width
        var newH = baseSize.height

        if let corner {
            switch corner {
            case .topLeading:
                newOriginX = basePoint.x + translation.width
                newOriginY = basePoint.y + translation.height
                newW = baseSize.width - translation.width
                newH = baseSize.height - translation.height
            case .topTrailing:
                newOriginY = basePoint.y + translation.height
                newW = baseSize.width + translation.width
                newH = baseSize.height - translation.height
            case .bottomLeading:
                newOriginX = basePoint.x + translation.width
                newW = baseSize.width - translation.width
                newH = baseSize.height + translation.height
            case .bottomTrailing:
                newW = baseSize.width + translation.width
                newH = baseSize.height + translation.height
            }
        } else if let edge {
            switch edge {
            case .top:
                newOriginY = basePoint.y + translation.height
                newH = baseSize.height - translation.height
            case .bottom:
                newH = baseSize.height + translation.height
            case .leading:
                newOriginX = basePoint.x + translation.width
                newW = baseSize.width - translation.width
            case .trailing:
                newW = baseSize.width + translation.width
            }
        }

        newW = max(40, newW)
        newH = max(40, newH)

        let preserveAspect = isImage || (isShape && resolvedShapeType.locksAspectWhileResizing)
        if preserveAspect, baseSize.width > 0, baseSize.height > 0, let corner {
            let aspect = baseSize.width / baseSize.height
            let prefersWidth = abs(translation.width) >= abs(translation.height)
            if prefersWidth {
                newH = newW / aspect
            } else {
                newW = newH * aspect
            }
            switch corner {
            case .topLeading:
                newOriginX = basePoint.x + (baseSize.width - newW)
                newOriginY = basePoint.y + (baseSize.height - newH)
            case .topTrailing:
                newOriginY = basePoint.y + (baseSize.height - newH)
            case .bottomLeading:
                newOriginX = basePoint.x + (baseSize.width - newW)
            case .bottomTrailing:
                break
            }
        }
        return (CGPoint(x: newOriginX, y: newOriginY), CGSize(width: newW, height: newH))
    }
}

// MARK: - Simple text toolbar

private struct SimpleTextOverlayToolbar: View {
    let fontSize: CGFloat
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onEdit) {
                Text("Aa")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoteEditorTheme.textPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Text("\(Int(fontSize.rounded()))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NoteEditorTheme.textPrimary)
                .frame(minWidth: 28)

            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.plain)

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NoteEditorTheme.danger)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }
}

// MARK: - Image adjust toolbar (GoodNotes-style)

/// Visual-only chrome; taps are routed through UIKit on the scroll view.
private struct ImageOverlayAdjustToolbar: View {
    var body: some View {
        HStack(spacing: 4) {
            toolbarIcon("crop", accessibilityLabel: "Crop")
            toolbarIcon("lasso", accessibilityLabel: "Lasso")
            toolbarIcon("scissors", accessibilityLabel: "Cut")
            toolbarIcon("plus.square.on.square", accessibilityLabel: "Duplicate")
            toolbarIcon("trash", tint: NoteEditorTheme.danger, accessibilityLabel: "Delete")
            toolbarIcon("ellipsis", accessibilityLabel: "More")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: ImageOverlayAdjustToolbarMetrics.width)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func toolbarIcon(
        _ symbol: String,
        tint: Color = NoteEditorTheme.textPrimary,
        accessibilityLabel: String? = nil
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 36, height: 32)
            .accessibilityLabel(accessibilityLabel ?? symbol)
    }
}

// MARK: - Image content (lazy loader)

/// Loads the image bytes through a process-wide cache so a busy page
/// doesn't re-decode on every gesture frame. The cache survives
/// SwiftUI view-tree rebuilds (which happen on every zoom step), so
/// the placeholder doesn't flash back in when the parent re-emits.
private struct ImageOverlayContent: View {
    let noteId: String
    let filename: String
    let provider: (String) -> Data?

    var body: some View {
        Group {
            if let image = OverlayImageCache.shared.image(for: cacheKey, provider: { provider(filename) }) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                placeholder
            }
        }
    }

    private var cacheKey: String { "\(noteId)/\(filename)" }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.05))
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NoteEditorTheme.textMuted)
        }
    }
}

/// Process-wide cache of decoded overlay `UIImage`s. Key: `noteId/filename`.
/// Survives SwiftUI view-tree teardowns so zoom-induced rerenders don't
/// flash the placeholder.
final class OverlayImageCache {
    static let shared = OverlayImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 256
    }

    func image(for key: String, provider: () -> Data?) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let data = provider(), let image = UIImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    func evict(key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}

// MARK: - Color hex helper

private extension Color {
    init?(hex: String?) {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count == 6,
              let value = UInt64(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

extension Color {
    /// Encodes a `Color` to 6-digit RRGGBB so it round-trips through the
    /// JSON store. Used by the text-overlay editor sheet.
    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((max(0, min(1, r)) * 255).rounded())
        let gi = Int((max(0, min(1, g)) * 255).rounded())
        let bi = Int((max(0, min(1, b)) * 255).rounded())
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}
