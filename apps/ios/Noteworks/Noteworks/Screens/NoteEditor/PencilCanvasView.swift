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
    var passesPencilTouchesThrough = false

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if shouldPassThrough(event: event) { return false }
        return super.point(inside: point, with: event)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if shouldPassThrough(event: event) { return nil }
        return super.hitTest(point, with: event)
    }

    /// Yield touches to the overlay layer beneath when Select mode (or
    /// finger-only pass-through in write tools) requests it.
    private func shouldPassThrough(event: UIEvent?) -> Bool {
        guard passesFingerTouchesThrough || passesPencilTouchesThrough else { return false }

        let touches = event?.allTouches ?? []
        // Always yield multi-finger sequences to the outer scroll view.
        if touches.count >= 2 { return true }

        // Ambiguous probe — keep canvas in chain so PencilKit receives `.began`.
        if touches.isEmpty { return false }

        let isPencil = touches.contains(where: { $0.type == .pencil })
        if isPencil {
            return passesPencilTouchesThrough
        }

        guard passesFingerTouchesThrough else { return false }

        let drawingState = drawingGestureRecognizer.state
        if drawingState == .began || drawingState == .changed { return false }
        return true
    }

    func applyTouchRoutingPolicy() {
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let fingerAndPencil = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]

        isMultipleTouchEnabled = true

        if passesFingerTouchesThrough {
            drawingGestureRecognizer.allowedTouchTypes = [pencil]
        } else {
            drawingGestureRecognizer.allowedTouchTypes = fingerAndPencil
        }

        // PKCanvasView inherits UIScrollView's pan/pinch recognizers.
        // The outer ZoomablePageScrollView owns page zoom.
        pinchGestureRecognizer?.isEnabled = false
        panGestureRecognizer.isEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTouchRoutingPolicy()
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

    /// When `false`, Apple Pencil strokes are suppressed while the view
    /// stays in the hit-test chain so finger pass-through / page zoom keep
    /// working (image / text / shape tools).
    var allowsPencilDrawing: Bool = true

    /// Finger taps reach overlays under the canvas; Pencil still draws here.
    var passesFingerTouchesThrough: Bool = false

    /// Select mode — Apple Pencil reaches overlays instead of inking.
    var passesPencilTouchesThrough: Bool = false

    /// Setter exposed so the chrome can wire its undo/redo buttons to the
    /// real canvas `UndoManager` once the view exists.
    var onCanvasReady: ((PKCanvasView) -> Void)? = nil

    /// Apple Pencil double-tap (Settings → Apple Pencil). Without
    /// `PKToolPicker`, the app must handle `UIPencilInteraction` explicitly.
    var onPencilDoubleTap: ((UIPencilInteraction) -> Void)? = nil

    func makeUIView(context: Context) -> FingerPassThroughPKCanvasView {
        let canvasView = FingerPassThroughPKCanvasView()
        canvasView.passesFingerTouchesThrough = passesFingerTouchesThrough
        canvasView.passesPencilTouchesThrough = passesPencilTouchesThrough
        canvasView.applyTouchRoutingPolicy()
        canvasView.drawingPolicy = drawingPolicy
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isMultipleTouchEnabled = true
        canvasView.drawing = drawing
        canvasView.tool = tool
        canvasView.delegate = context.coordinator
        canvasView.isUserInteractionEnabled = isDrawingEnabled
        canvasView.drawingGestureRecognizer.isEnabled = allowsPencilDrawing

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
        if canvasView.passesFingerTouchesThrough != passesFingerTouchesThrough
            || canvasView.passesPencilTouchesThrough != passesPencilTouchesThrough {
            canvasView.passesFingerTouchesThrough = passesFingerTouchesThrough
            canvasView.passesPencilTouchesThrough = passesPencilTouchesThrough
            canvasView.applyTouchRoutingPolicy()
        }
        if canvasView.drawingPolicy != drawingPolicy {
            canvasView.drawingPolicy = drawingPolicy
        }
        if canvasView.isUserInteractionEnabled != isDrawingEnabled {
            canvasView.isUserInteractionEnabled = isDrawingEnabled
        }
        if canvasView.drawingGestureRecognizer.isEnabled != allowsPencilDrawing {
            canvasView.drawingGestureRecognizer.isEnabled = allowsPencilDrawing
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
