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

    /// Called when the user moves / resizes an overlay. The caller writes
    /// it back into `NotesStore` with `updateOverlay(...)`.
    var onUpdate: (NotePageOverlay) -> Void

    /// Called when the user taps the "X" on a selected overlay.
    var onDelete: (NotePageOverlay) -> Void

    /// Called when the user finishes editing a text overlay's content.
    var onEditText: (NotePageOverlay) -> Void

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
                    if selectedId != nil { selectedId = nil }
                }

            ForEach(overlays) { overlay in
                NoteOverlayItem(
                    overlay: overlay,
                    pageSize: pageSize,
                    isSelected: overlay.id == selectedId,
                    noteId: noteId,
                    imageDataProvider: imageDataProvider,
                    onSelect: { selectedId = overlay.id },
                    onUpdate: onUpdate,
                    onDelete: { onDelete(overlay); selectedId = nil },
                    onEditText: onEditText
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
    let noteId: String
    var imageDataProvider: (String) -> Data?
    var onSelect: () -> Void
    var onUpdate: (NotePageOverlay) -> Void
    var onDelete: () -> Void
    var onEditText: (NotePageOverlay) -> Void

    /// Drag offsets are tracked locally so we don't write to disk on every
    /// micro-gesture event; we only push back into the store on
    /// `.onEnded`.
    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero

    private var basePoint: CGPoint {
        CGPoint(x: overlay.normX * pageSize.width, y: overlay.normY * pageSize.height)
    }
    private var baseSize: CGSize {
        CGSize(width: overlay.normW * pageSize.width, height: overlay.normH * pageSize.height)
    }
    /// Live size during a resize gesture.
    private var liveSize: CGSize {
        CGSize(
            width: max(40, baseSize.width + resizeDelta.width),
            height: max(40, baseSize.height + resizeDelta.height)
        )
    }
    /// Live origin during a move gesture.
    private var liveOrigin: CGPoint {
        CGPoint(x: basePoint.x + dragOffset.width, y: basePoint.y + dragOffset.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(width: liveSize.width, height: liveSize.height)
                .background(itemBackground)
                .overlay(selectionBorder)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        deleteHandle
                            .offset(x: 10, y: -10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        resizeHandle
                            .offset(x: 10, y: 10)
                    }
                }
                .gesture(moveGesture)
                .onTapGesture {
                    if !isSelected { onSelect() }
                    else if overlay.kind == .text { onEditText(overlay) }
                }
        }
        .offset(x: liveOrigin.x, y: liveOrigin.y)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    // MARK: Content variants

    @ViewBuilder
    private var content: some View {
        switch overlay.kind {
        case .text:
            Text(overlay.text?.isEmpty == false ? overlay.text! : "Tap to edit")
                .font(.system(size: overlay.fontSize ?? 18, weight: .medium))
                .foregroundStyle(Color(hex: overlay.colorHex) ?? NoteEditorTheme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
        case .image:
            ImageOverlayContent(noteId: noteId, filename: overlay.imageFilename ?? "", provider: imageDataProvider)
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

    private var resizeHandle: some View {
        Circle()
            .fill(NoteEditorTheme.accent)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .frame(width: 18, height: 18)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .gesture(resizeGesture)
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isSelected { onSelect() }
                dragOffset = value.translation
            }
            .onEnded { value in
                // Clamp the dropped origin to the page rect so an overlay
                // can never be left fully off-screen.
                let dropped = CGPoint(
                    x: max(0, min(pageSize.width - baseSize.width, basePoint.x + value.translation.width)),
                    y: max(0, min(pageSize.height - baseSize.height, basePoint.y + value.translation.height))
                )
                var updated = overlay
                updated.normX = dropped.x / pageSize.width
                updated.normY = dropped.y / pageSize.height
                dragOffset = .zero
                onUpdate(updated)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                resizeDelta = value.translation
            }
            .onEnded { value in
                var newW = max(40, baseSize.width + value.translation.width)
                var newH = max(40, baseSize.height + value.translation.height)
                // Images keep aspect — fit within whichever delta the user
                // pulled further so the gesture feels natural.
                if overlay.kind == .image, baseSize.width > 0, baseSize.height > 0 {
                    let aspect = baseSize.width / baseSize.height
                    if abs(value.translation.width) > abs(value.translation.height) {
                        newH = newW / aspect
                    } else {
                        newW = newH * aspect
                    }
                }
                let maxW = pageSize.width - basePoint.x
                let maxH = pageSize.height - basePoint.y
                newW = min(newW, maxW)
                newH = min(newH, maxH)
                var updated = overlay
                updated.normW = newW / pageSize.width
                updated.normH = newH / pageSize.height
                resizeDelta = .zero
                onUpdate(updated)
            }
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
