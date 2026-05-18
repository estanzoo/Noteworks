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
//  Interaction model (kept simple for v1):
//    - Tap an overlay to select it (shows hairline border, "X" to delete,
//      bottom-right resize handle).
//    - Tap empty space (or another overlay) to deselect.
//    - Drag an overlay anywhere on the body to move it.
//    - Drag the bottom-right handle to resize. Images preserve aspect.
//    - Double-tap a text overlay (or single-tap when already selected) to
//      pop the inline editor.
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
    /// Tap-on-already-selected-text starts inline editing.
    var onStartEditing: () -> Void
    /// TextField submit / focus-loss commits the new string.
    var onCommitEditing: (String) -> Void

    /// Local working copy of the text while the user is typing. Synced
    /// from `overlay.text` when editing begins so the field starts with
    /// the latest committed value.
    @State private var draftText: String = ""
    @FocusState private var textFieldFocused: Bool

    /// Drag offsets are tracked locally so we don't write to disk on every
    /// micro-gesture event; we only push back into the store on
    /// `.onEnded`.
    @State private var dragOffset: CGSize = .zero
    /// Resize gesture deltas — origin shifts when dragging top/left edges,
    /// size shifts on all edges. Both committed on `.onEnded`.
    @State private var resizeOriginDelta: CGSize = .zero
    @State private var resizeSizeDelta: CGSize = .zero
    /// Live scale from pinch gesture (1.0 == no change). Committed on
    /// `.onEnded`.
    @State private var pinchScale: CGFloat = 1.0

    private var basePoint: CGPoint {
        CGPoint(x: overlay.normX * pageSize.width, y: overlay.normY * pageSize.height)
    }
    private var baseSize: CGSize {
        CGSize(width: overlay.normW * pageSize.width, height: overlay.normH * pageSize.height)
    }
    /// Live size during a resize / pinch gesture.
    private var liveSize: CGSize {
        let pinched = CGSize(
            width: baseSize.width * pinchScale,
            height: baseSize.height * pinchScale
        )
        return CGSize(
            width: max(40, pinched.width + resizeSizeDelta.width),
            height: max(40, pinched.height + resizeSizeDelta.height)
        )
    }
    /// Live origin during a move / pinch-resize gesture. Pinch anchors at
    /// the overlay center, so origin shifts to keep the visual center
    /// fixed while the size grows.
    private var liveOrigin: CGPoint {
        let pinchOriginShift = CGSize(
            width: (baseSize.width - baseSize.width * pinchScale) / 2,
            height: (baseSize.height - baseSize.height * pinchScale) / 2
        )
        return CGPoint(
            x: basePoint.x + dragOffset.width + resizeOriginDelta.width + pinchOriginShift.width,
            y: basePoint.y + dragOffset.height + resizeOriginDelta.height + pinchOriginShift.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(width: liveSize.width, height: liveSize.height)
                .background(itemBackground)
                .overlay(selectionBorder)
                .contentShape(Rectangle())
                .gesture(combinedGesture)
                .overlay(alignment: .top) {
                    if isSelected {
                        deleteHandle
                            .offset(y: -32)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isSelected {
                        cornerHandle(.topLeading)
                            .offset(x: -12, y: -12)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        cornerHandle(.topTrailing)
                            .offset(x: 12, y: -12)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isSelected {
                        cornerHandle(.bottomLeading)
                            .offset(x: -12, y: 12)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        cornerHandle(.bottomTrailing)
                            .offset(x: 12, y: 12)
                    }
                }
        }
        .offset(x: liveOrigin.x, y: liveOrigin.y)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    // MARK: Handle geometry

    private enum OverlayCorner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    // MARK: Content variants

    @ViewBuilder
    private var content: some View {
        switch overlay.kind {
        case .text:
            textContent
        case .image:
            ImageOverlayContent(noteId: noteId, filename: overlay.imageFilename ?? "", provider: imageDataProvider)
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
                .fill(Color.white.opacity(isSelected ? 0.6 : 0.0))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.001))   // hit-target only
        }
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: overlay.kind == .text ? 8 : 6)
                .strokeBorder(NoteEditorTheme.accent.opacity(0.65), lineWidth: 1)
        }
    }

    // MARK: Handles

    private var deleteHandle: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(NoteEditorTheme.danger))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete overlay")
    }

    /// 22pt visible circle with a 44pt invisible hit area so the corner
    /// handles are comfortable to grab even with a finger.
    private func cornerHandle(_ corner: OverlayCorner) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(NoteEditorTheme.accent, lineWidth: 2))
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(resizeGesture(for: corner))
    }

    // MARK: Gestures

    /// Drag-to-move and pinch-to-resize on the overlay body. Pinch is a
    /// MagnificationGesture; drag is a DragGesture with `minimumDistance: 0`
    /// so movement starts the moment the finger touches the overlay. Tap
    /// behavior (select / edit text) is detected from the drag's end state
    /// when total translation is below a small threshold.
    private var combinedGesture: some Gesture {
        SimultaneousGesture(moveGesture, pinchGesture)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let translation = value.translation
                let isStillTap = abs(translation.width) < 4 && abs(translation.height) < 4
                if isStillTap { return }
                if !isSelected { onSelect() }
                dragOffset = translation
            }
            .onEnded { value in
                let translation = value.translation
                let isTap = abs(translation.width) < 4 && abs(translation.height) < 4
                if isTap {
                    // Tap fallback: first tap selects, subsequent tap on a
                    // text overlay enters inline edit mode.
                    if !isSelected { onSelect() }
                    else if overlay.kind == .text { onStartEditing() }
                    dragOffset = .zero
                    return
                }
                // Clamp the dropped origin to the page rect so an overlay
                // can never be left fully off-screen.
                let dropped = CGPoint(
                    x: max(0, min(pageSize.width - baseSize.width, basePoint.x + translation.width)),
                    y: max(0, min(pageSize.height - baseSize.height, basePoint.y + translation.height))
                )
                var updated = overlay
                updated.normX = dropped.x / pageSize.width
                updated.normY = dropped.y / pageSize.height
                dragOffset = .zero
                onUpdate(updated)
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
                if !isSelected { onSelect() }
                pinchScale = max(0.3, min(4, scale))
            }
            .onEnded { scale in
                let clamped = max(0.3, min(4, scale))
                var newW = baseSize.width * clamped
                var newH = baseSize.height * clamped
                // Keep aspect for images. Texts share the same path so the
                // outer frame grows uniformly.
                if baseSize.width > 0, baseSize.height > 0 {
                    let aspect = baseSize.width / baseSize.height
                    newH = newW / aspect
                }
                // Anchor at center: origin shifts so the visual center
                // stays put through the pinch.
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

    /// Drag from a corner handle — resizes anchored at the opposite corner.
    /// Images preserve aspect ratio; text overlays free-scale.
    private func resizeGesture(for corner: OverlayCorner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let (newOrigin, newSize) = resized(corner: corner, translation: value.translation)
                resizeOriginDelta = CGSize(
                    width: newOrigin.x - basePoint.x,
                    height: newOrigin.y - basePoint.y
                )
                resizeSizeDelta = CGSize(
                    width: newSize.width - baseSize.width,
                    height: newSize.height - baseSize.height
                )
            }
            .onEnded { value in
                let (newOrigin, newSize) = resized(corner: corner, translation: value.translation)
                let clampedOrigin = CGPoint(
                    x: max(0, min(pageSize.width - newSize.width, newOrigin.x)),
                    y: max(0, min(pageSize.height - newSize.height, newOrigin.y))
                )
                var updated = overlay
                updated.normX = clampedOrigin.x / pageSize.width
                updated.normY = clampedOrigin.y / pageSize.height
                updated.normW = newSize.width / pageSize.width
                updated.normH = newSize.height / pageSize.height
                resizeOriginDelta = .zero
                resizeSizeDelta = .zero
                onUpdate(updated)
            }
    }

    /// Geometry math for a corner-anchored resize. Returns the new
    /// top-left origin and size given the drag translation. Images
    /// preserve aspect ratio.
    private func resized(corner: OverlayCorner, translation: CGSize) -> (CGPoint, CGSize) {
        var newOriginX = basePoint.x
        var newOriginY = basePoint.y
        var newW = baseSize.width
        var newH = baseSize.height

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

        newW = max(40, newW)
        newH = max(40, newH)

        // Preserve aspect for images. The dominant axis (whichever has
        // moved further in absolute terms) wins so the gesture matches
        // user intent.
        if overlay.kind == .image, baseSize.width > 0, baseSize.height > 0 {
            let aspect = baseSize.width / baseSize.height
            let prefersWidth = abs(translation.width) >= abs(translation.height)
            if prefersWidth {
                newH = newW / aspect
            } else {
                newW = newH * aspect
            }
            // Re-anchor origin after aspect correction.
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
