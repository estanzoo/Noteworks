//
//  PencilCanvasView.swift
//  Noteworks
//
//  SwiftUI wrapper around `PKCanvasView`. We deliberately do NOT use the
//  system `PKToolPicker` — the editor builds its own glass toolbar chrome
//  (mirroring the JSX `NotetakingPage`) and pushes the active tool down
//  through `tool: PKTool`. The canvas is rendered transparent so the
//  background pattern view behind it shows through.
//
//  Zoom is handled by an OUTER `ZoomablePageScrollView` that wraps this
//  canvas + the background pattern + overlay layer. PKCanvasView itself
//  has its inherited UIScrollView zoom disabled (`minimumZoomScale` and
//  `maximumZoomScale` both pinned to 1, pinch gesture turned off) so
//  the outer scroll view owns the pinch — otherwise both recognizers
//  would fight over the same touches.
//

import SwiftUI
import UIKit
import PencilKit

/// Canvas that ignores finger hit-testing so taps reach stickers below
/// while Apple Pencil still draws on this layer.
final class FingerPassThroughPKCanvasView: PKCanvasView {
    var passesFingerTouchesThrough = false

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if passesFingerTouchesThrough, !acceptsTouch(on: event) {
            return false
        }
        return super.point(inside: point, with: event)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if passesFingerTouchesThrough, !acceptsTouch(on: event) {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    /// Pencil → canvas. Finger or nil event (first hit test) → overlays below.
    private func acceptsTouch(on event: UIEvent?) -> Bool {
        guard let event else { return false }
        let touches = event.allTouches ?? []
        if touches.isEmpty { return false }
        return touches.contains { $0.type == .pencil }
    }

    func applyTouchRoutingPolicy() {
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let fingerAndPencil = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]
        if passesFingerTouchesThrough {
            drawingGestureRecognizer.allowedTouchTypes = [pencil]
        } else {
            drawingGestureRecognizer.allowedTouchTypes = fingerAndPencil
        }
    }
}

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
    /// to the overlay layer below (text / image / shape tools).
    var isDrawingEnabled: Bool = true

    /// Finger taps reach overlays under the canvas; Pencil still draws here.
    var passesFingerTouchesThrough: Bool = false

    /// Setter exposed so the chrome can wire its undo/redo buttons to the
    /// real canvas `UndoManager` once the view exists.
    var onCanvasReady: ((PKCanvasView) -> Void)? = nil

    /// Apple Pencil double-tap (Settings → Apple Pencil). Without
    /// `PKToolPicker`, the app must handle `UIPencilInteraction` explicitly.
    var onPencilDoubleTap: ((UIPencilInteraction) -> Void)? = nil

    func makeUIView(context: Context) -> FingerPassThroughPKCanvasView {
        let canvasView = FingerPassThroughPKCanvasView()
        canvasView.passesFingerTouchesThrough = passesFingerTouchesThrough
        canvasView.applyTouchRoutingPolicy()
        canvasView.drawingPolicy = drawingPolicy
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawing = drawing
        canvasView.tool = tool
        canvasView.delegate = context.coordinator
        canvasView.isUserInteractionEnabled = isDrawingEnabled

        canvasView.pinchGestureRecognizer?.isEnabled = false
        canvasView.panGestureRecognizer.isEnabled = false
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.bouncesZoom = false

        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvasView.addInteraction(pencil)

        DispatchQueue.main.async {
            onCanvasReady?(canvasView)
        }
        return canvasView
    }

    func updateUIView(_ canvasView: FingerPassThroughPKCanvasView, context: Context) {
        if canvasView.passesFingerTouchesThrough != passesFingerTouchesThrough {
            canvasView.passesFingerTouchesThrough = passesFingerTouchesThrough
            canvasView.applyTouchRoutingPolicy()
        }
        if canvasView.drawingPolicy != drawingPolicy {
            canvasView.drawingPolicy = drawingPolicy
        }
        if canvasView.isUserInteractionEnabled != isDrawingEnabled {
            canvasView.isUserInteractionEnabled = isDrawingEnabled
        }
        canvasView.tool = tool

        if canvasView.drawing != drawing && !context.coordinator.isDrawing {
            canvasView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var parent: PencilCanvasView
        var isDrawing: Bool = false

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            parent.onPencilDoubleTap?(interaction)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if parent.drawing != canvasView.drawing {
                parent.drawing = canvasView.drawing
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
