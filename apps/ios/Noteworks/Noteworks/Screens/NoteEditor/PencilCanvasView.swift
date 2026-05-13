//
//  PencilCanvasView.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//
//  SwiftUI wrapper around `PKCanvasView`. We deliberately do NOT use the
//  system `PKToolPicker` — the editor builds its own glass toolbar chrome
//  (mirroring the JSX `NotetakingPage`) and pushes the active tool down
//  through `tool: PKTool`. The canvas is rendered transparent so the
//  background pattern view behind it shows through.
//

import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {

    /// Live drawing — bound to the parent so strokes flow up and page
    /// swaps flow down.
    @Binding var drawing: PKDrawing

    /// Currently active tool (pen / highlighter / eraser / lasso). Pushed
    /// from the parent's toolbar; we apply it on every `updateUIView`.
    var tool: PKTool

    /// `.anyInput` accepts both finger and Pencil. `.pencilOnly` lets the
    /// finger pan/zoom the canvas as a `UIScrollView`.
    var drawingPolicy: PKCanvasViewDrawingPolicy = .anyInput

    /// When `false`, the canvas ignores touches so taps/drags fall through
    /// to the overlay layer above (used by the text + image tools — those
    /// shouldn't accidentally leave stray strokes on the page).
    var isDrawingEnabled: Bool = true

    /// Setter exposed so the chrome can wire its undo/redo buttons to the
    /// real canvas `UndoManager` once the view exists.
    var onCanvasReady: ((PKCanvasView) -> Void)? = nil

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = drawingPolicy
        // Transparent so the background pattern (dots / single-column /
        // blank) drawn behind the canvas is visible.
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawing = drawing
        canvasView.tool = tool
        canvasView.delegate = context.coordinator
        canvasView.isUserInteractionEnabled = isDrawingEnabled

        // PKCanvasView IS-A UIScrollView, so it has its own pinch gesture
        // recognizer. When this canvas is hosted inside `ZoomablePageScrollView`
        // we want the OUTER scroll view to own the pinch — otherwise both
        // recognizers fight over the same touches and zoom feels jittery.
        // Disabling pinch here leaves drawing untouched (PencilKit uses its
        // own internal recognizers) while letting the outer scroll handle
        // the two-finger zoom + pan gestures cleanly.
        canvasView.pinchGestureRecognizer?.isEnabled = false
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.bouncesZoom = false

        // We're not showing PKToolPicker; nothing else to set up here.
        DispatchQueue.main.async {
            onCanvasReady?(canvasView)
        }
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if canvasView.drawingPolicy != drawingPolicy {
            canvasView.drawingPolicy = drawingPolicy
        }
        if canvasView.isUserInteractionEnabled != isDrawingEnabled {
            canvasView.isUserInteractionEnabled = isDrawingEnabled
        }
        // Apply the latest tool every refresh — PencilKit's tool object is
        // a value type so cheap to recreate.
        canvasView.tool = tool

        // Only swap the drawing on external changes (e.g. page flip), not
        // while the user is mid-stroke.
        if canvasView.drawing != drawing && !context.coordinator.isDrawing {
            canvasView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var isDrawing: Bool = false

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.drawing != canvasView.drawing {
                    self.parent.drawing = canvasView.drawing
                }
            }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isDrawing = false
        }
    }
}

// MARK: - Preview

#Preview {
    PencilCanvasView(
        drawing: .constant(PKDrawing()),
        tool: PKInkingTool(.pen, color: .black, width: 4)
    )
}
