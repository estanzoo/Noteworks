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
    let pageSize: CGSize
    let noteId: String
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

    /// Looks up the image data for a `.image` overlay. Wired to
    /// `NotesStore.loadOverlayImageData` so this view stays presentation
    /// only.
    var imageDataProvider: (String) -> Data?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Empty-space tap to deselect. We use a near-clear rectangle
            // (not Color.clear) so the gesture actually fires.
            Color.white.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    if editingId != nil { editingId = nil }
                    if selectedId != nil { selectedId = nil }
                }

            ForEach(overlays) { overlay in
                NoteOverlayItem(
                    overlay: overlay,
                    pageSize: pageSize,
                    isSelected: overlay.id == selectedId,
                    isEditing: overlay.id == editingId,
                    noteId: noteId,
                    imageDataProvider: imageDataProvider,
                    onSelect: { selectedId = overlay.id },
                    onUpdate: onUpdate,
                    onDelete: {
                        if editingId == overlay.id { editingId = nil }
                        onDelete(overlay)
                        selectedId = nil
                    },
                    onDuplicate: onDuplicate,
                    onSelectLasso: onSelectLasso,
                    onCropImage: { onCropImage(overlay) },
                    onStartEditing: {
                        selectedId = overlay.id
                        editingId = overlay.id
                    },
                    onCommitEditing: { newText in
                        var updated = overlay
                        updated.text = newText
                        onUpdate(updated)
                        editingId = nil
                    }
                )
            }
        }
        .frame(width: pageSize.width, height: pageSize.height, alignment: .topLeading)
        .clipped()
    }
}

// MARK: - Single item

private struct NoteOverlayItem: View {
    let overlay: NotePageOverlay
    let pageSize: CGSize
    let isSelected: Bool
    let isEditing: Bool
    let noteId: String
    var imageDataProvider: (String) -> Data?
    var onSelect: () -> Void
    var onUpdate: (NotePageOverlay) -> Void
    var onDelete: () -> Void
    var onDuplicate: (NotePageOverlay) -> Void
    var onSelectLasso: () -> Void
    var onCropImage: () -> Void
    /// Tap-on-already-selected-text starts inline editing.
    var onStartEditing: () -> Void
    /// TextField submit / focus-loss commits the new string.
    var onCommitEditing: (String) -> Void

    /// Local working copy of the text while the user is typing. Synced
    /// from `overlay.text` when editing begins so the field starts with
    /// the latest committed value.
    @State private var draftText: String = ""
    @FocusState private var textFieldFocused: Bool

    /// Live drag/resize offsets — `@State` persists until commit so the
    /// sticker does not snap back when the gesture ends.
    @State private var dragOffset: CGSize = .zero
    @State private var resizeTranslation: CGSize = .zero
    @State private var pinchScale: CGFloat = 1.0
    @State private var rotationDelta: CGFloat = 0
    @State private var rotationTouchStartAngle: CGFloat?
    @State private var rotationAtGestureStart: CGFloat = 0
    /// Shows handles while dragging before `selectedId` commits at end.
    @State private var isDragActive = false

    private var isImage: Bool { overlay.kind == .image }
    private var isShape: Bool { overlay.kind == .shape }
    /// Image + shape share GoodNotes-style handles (corners, edges, rotate).
    private var usesFullTransformChrome: Bool { isImage || isShape }
    private var resolvedShapeType: NoteShapeType {
        NoteShapeOverlayDrawing.resolvedType(overlay.shapeType)
    }
    private var showsSelectionChrome: Bool { isSelected || isDragActive }
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
            x: resized.origin.x + dragOffset.width + pinchOriginShift.width,
            y: resized.origin.y + dragOffset.height + pinchOriginShift.height
        )
    }

  /// Active corner/edge being resized; nil when moving only.
    @State private var activeResizeCorner: OverlayCorner?
    @State private var activeResizeEdge: OverlayEdge?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                content
                    .frame(width: liveSize.width, height: liveSize.height)
                    .background(itemBackground)
                    .clipShape(RoundedRectangle(cornerRadius: usesFullTransformChrome ? 4 : 8))
                    .overlay(selectionBorder)
                    .contentShape(Rectangle())
                    // Drag is the primary gesture for an overlay — the
                    // user expects to grab an image with a finger and
                    // move it without any pre-selection step. Putting
                    // it before tap (and keeping tap *simultaneous*
                    // rather than high-priority) means SwiftUI starts
                    // recognising the drag from the very first touch
                    // event at `minimumDistance: 2`, beating the outer
                    // `UIScrollView.panGestureRecognizer` (~10pt) to
                    // the punch. Tap still fires on touch-up with no
                    // movement, which is all `handleTap()` needs to
                    // select or open the inline text editor.
                    .gesture(moveGesture)
                    .simultaneousGesture(TapGesture().onEnded { handleTap() })
                    .simultaneousGesture(pinchGesture)

                if showsSelectionChrome {
                    fourCornerHandles
                    if usesFullTransformChrome {
                        imageEdgeHandles
                        rotationHandle
                    }
                }
            }
            .frame(width: liveSize.width, height: liveSize.height)
            .rotationEffect(.degrees(usesFullTransformChrome ? overlay.rotationDegrees + rotationDelta : 0))
            .offset(x: liveOrigin.x, y: liveOrigin.y)

            if showsSelectionChrome, usesFullTransformChrome {
                ImageOverlayAdjustToolbar(
                    onCrop: isImage ? onCropImage : {},
                    onLasso: onSelectLasso,
                    onCut: onDelete,
                    onDuplicate: { onDuplicate(overlay) },
                    onDelete: onDelete
                )
                .offset(x: liveOrigin.x + max(0, (liveSize.width - 280) / 2), y: liveOrigin.y - 52)
            }

            if showsSelectionChrome, overlay.kind == .text {
                SimpleTextOverlayToolbar(
                    fontSize: overlay.fontSize ?? 18,
                    onDecrease: { adjustFontSize(by: -2) },
                    onIncrease: { adjustFontSize(by: 2) },
                    onEdit: onStartEditing,
                    onDelete: onDelete
                )
                .offset(x: liveOrigin.x + max(0, (liveSize.width - 200) / 2), y: liveOrigin.y - 46)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .transaction { transaction in
            if dragOffset != .zero || resizeTranslation != .zero || pinchScale != 1.0 || rotationDelta != 0 {
                transaction.animation = nil
            }
        }
    }

    private func handleTap() {
        guard !isEditing else { return }
        if !isSelected {
            onSelect()
        } else if overlay.kind == .text {
            onStartEditing()
        }
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
        let textFont = Font.system(size: overlay.fontSize ?? 18, weight: .medium)
        if isEditing {
            TextField("Type text…", text: $draftText, axis: .vertical)
                .font(textFont)
                .foregroundStyle(textColor)
                .focused($textFieldFocused)
                .submitLabel(.done)
                .padding(8)
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
                .padding(8)
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
    private var fourCornerHandles: some View {
        ForEach(OverlayCorner.allCases, id: \.self) { corner in
            resizeHandle
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                .offset(corner.offset)
                .gesture(resizeGesture(for: corner))
        }
    }

    private var imageEdgeHandles: some View {
        Group {
            edgeHandle(.top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -11)
                .gesture(resizeGesture(for: .top))
            edgeHandle(.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: 11)
                .gesture(resizeGesture(for: .bottom))
            edgeHandle(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: -11)
                .gesture(resizeGesture(for: .leading))
            edgeHandle(.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 11)
                .gesture(resizeGesture(for: .trailing))
        }
    }

    private var rotationHandle: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Self.imageAccent.opacity(0.85))
                .frame(width: 1.5, height: 22)
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Self.imageAccent, lineWidth: 2))
                .overlay {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Self.imageAccent)
                }
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .gesture(rotationGesture)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: 38)
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Self.imageAccent)
            .frame(width: 11, height: 11)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    private func edgeHandle(_ edge: OverlayEdge) -> some View {
        Circle()
            .fill(Self.imageAccent)
            .frame(width: 9, height: 9)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isDragActive = true
                dragOffset = value.translation
            }
            .onEnded { value in
                let w = liveSize.width
                let h = liveSize.height
                let dropped = CGPoint(
                    x: max(0, min(pageSize.width - w, basePoint.x + value.translation.width)),
                    y: max(0, min(pageSize.height - h, basePoint.y + value.translation.height))
                )
                var updated = overlay
                updated.normX = dropped.x / pageSize.width
                updated.normY = dropped.y / pageSize.height
                dragOffset = .zero
                isDragActive = false
                onUpdate(updated)
                if !isSelected { onSelect() }
            }
    }

    /// Two-finger pinch on the overlay body. Anchors at the visual center
    /// so the image grows/shrinks under the user's fingers naturally.
    /// Aspect ratio is preserved for images; text overlays scale uniformly
    /// too (so the font-size box scales — actual font size stays the same
    /// since we resize the frame only).
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                pinchScale = max(0.3, min(4, scale))
            }
            .onEnded { scale in
                let clamped = max(0.3, min(4, scale))
                var newW = baseSize.width * clamped
                var newH = baseSize.height * clamped
                if baseSize.width > 0, baseSize.height > 0 {
                    let aspect = baseSize.width / baseSize.height
                    newH = newW / aspect
                }
                let dx = (baseSize.width - newW) / 2
                let dy = (baseSize.height - newH) / 2
                let originX = max(0, min(pageSize.width - newW, basePoint.x + dx))
                let originY = max(0, min(pageSize.height - newH, basePoint.y + dy))
                newW = max(40, min(newW, pageSize.width - originX))
                newH = max(40, min(newH, pageSize.height - originY))

                var updated = overlay
                updated.normX = originX / pageSize.width
                updated.normY = originY / pageSize.height
                updated.normW = newW / pageSize.width
                updated.normH = newH / pageSize.height
                pinchScale = 1.0
                onUpdate(updated)
            }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = CGPoint(
                    x: liveOrigin.x + liveSize.width / 2,
                    y: liveOrigin.y + liveSize.height / 2
                )
                let touch = CGPoint(
                    x: center.x + value.translation.width,
                    y: center.y + value.translation.height + liveSize.height / 2 + 34
                )
                let degrees = atan2(touch.y - center.y, touch.x - center.x) * 180 / .pi + 90
                if rotationTouchStartAngle == nil {
                    rotationTouchStartAngle = degrees
                    rotationAtGestureStart = overlay.rotationDegrees
                }
                if let start = rotationTouchStartAngle {
                    rotationDelta = degrees - start
                }
            }
            .onEnded { _ in
                var updated = overlay
                updated.rotationDegrees = rotationAtGestureStart + rotationDelta
                rotationDelta = 0
                rotationTouchStartAngle = nil
                onUpdate(updated)
            }
    }

    /// Drag from a corner or edge handle — resizes anchored at the opposite side.
    /// Images preserve aspect ratio; text overlays free-scale.
    private func resizeGesture(for corner: OverlayCorner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                activeResizeCorner = corner
                activeResizeEdge = nil
                resizeTranslation = value.translation
            }
            .onEnded { value in
                let (newOrigin, newSize) = resized(corner: corner, edge: nil, translation: value.translation)
                resizeTranslation = .zero
                activeResizeCorner = nil
                activeResizeEdge = nil
                commitResize(origin: newOrigin, size: newSize)
            }
    }

    private func resizeGesture(for edge: OverlayEdge) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                activeResizeEdge = edge
                activeResizeCorner = nil
                resizeTranslation = value.translation
            }
            .onEnded { value in
                let (newOrigin, newSize) = resized(corner: nil, edge: edge, translation: value.translation)
                resizeTranslation = .zero
                activeResizeCorner = nil
                activeResizeEdge = nil
                commitResize(origin: newOrigin, size: newSize)
            }
    }

    private func activeResizeGeometry(for translation: CGSize) -> (origin: CGPoint, size: CGSize) {
        if let corner = activeResizeCorner {
            return resized(corner: corner, edge: nil, translation: translation)
        }
        if let edge = activeResizeEdge {
            return resized(corner: nil, edge: edge, translation: translation)
        }
        return (basePoint, baseSize)
    }

    private func commitResize(origin: CGPoint, size: CGSize) {
        let clampedOrigin = CGPoint(
            x: max(0, min(pageSize.width - size.width, origin.x)),
            y: max(0, min(pageSize.height - size.height, origin.y))
        )
        var updated = overlay
        updated.normX = clampedOrigin.x / pageSize.width
        updated.normY = clampedOrigin.y / pageSize.height
        updated.normW = size.width / pageSize.width
        updated.normH = size.height / pageSize.height
        onUpdate(updated)
    }

    /// Geometry math for a corner- or edge-anchored resize.
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

private struct ImageOverlayAdjustToolbar: View {
    var onCrop: () -> Void
    var onLasso: () -> Void
    var onCut: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            toolbarIcon("crop", action: onCrop, accessibilityLabel: "Crop")
            toolbarIcon("lasso", action: onLasso, accessibilityLabel: "Lasso")
            toolbarIcon("scissors", action: onCut, accessibilityLabel: "Cut")
            toolbarIcon("plus.square.on.square", action: onDuplicate, accessibilityLabel: "Duplicate")
            toolbarIcon("trash", action: onDelete, tint: NoteEditorTheme.danger, accessibilityLabel: "Delete")
            toolbarIcon("ellipsis", action: {}, accessibilityLabel: "More")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
        action: @escaping () -> Void,
        tint: Color = NoteEditorTheme.textPrimary,
        accessibilityLabel: String? = nil
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? symbol)
    }
}

// MARK: - Image content (lazy loader)

/// Loads the image bytes once and caches the decoded `UIImage` so a busy
/// page doesn't re-decode on every gesture frame.
private struct ImageOverlayContent: View {
    let noteId: String
    let filename: String
    let provider: (String) -> Data?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                placeholder
            }
        }
        .task(id: filename) {
            if let data = provider(filename), let img = UIImage(data: data) {
                self.image = img
            }
        }
    }

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
