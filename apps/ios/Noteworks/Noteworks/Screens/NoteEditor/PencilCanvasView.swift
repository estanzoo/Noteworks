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
    /// swaps flow down. Stored in **base** (zoom == 1) coordinates so
    /// it round-trips through disk regardless of the current zoom.
    @Binding var drawing: PKDrawing

    /// Currently active tool (pen / highlighter / eraser / lasso). Pushed
    /// from the parent's toolbar; we apply it on every `updateUIView`.
    var tool: PKTool

    /// Live zoom factor (1.0 = fit). The canvas's frame grows by this
    /// factor in the parent layout, so we apply the same scale to the
    /// drawing we hand to PencilKit, and the inverse scale to the
    /// drawing PencilKit hands back, so persisted strokes always live
    /// in base coordinates.
    var zoomScale: CGFloat = 1.0

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
        context.coordinator.appliedZoom = max(0.0001, zoomScale)
        context.coordinator.lastPublishedBaseDrawing = drawing
        canvasView.drawing = drawing.transformed(using: CGAffineTransform(scaleX: zoomScale, y: zoomScale))
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
        context.coordinator.parent = self

        if context.coordinator.isDrawing {
            // Don't yank the canvas out from under the user mid-stroke.
            // We re-sync at the next tool-end via the delegate path.
            return
        }

        let safeZoom = max(0.0001, zoomScale)
        let zoomChanged = abs(context.coordinator.appliedZoom - safeZoom) > 0.0005

        if zoomChanged {
            // Zoom changed → push the freshly-scaled drawing into the
            // canvas exactly ONCE. PencilKit re-rasterises the strokes
            // at the new size, producing genuinely-crisp ink.
            let displayDrawing = drawing.transformed(
                using: CGAffineTransform(scaleX: safeZoom, y: safeZoom)
            )
            context.coordinator.suppressNextDelegateChange = true
            context.coordinator.lastPublishedBaseDrawing = drawing
            canvasView.drawing = displayDrawing
            context.coordinator.appliedZoom = safeZoom
            return
        }

        // Same zoom as last time: only reassign the canvas drawing when
        // the binding's drawing genuinely differs from what we last
        // received from (or pushed to) the canvas. Floating-point
        // round-trip from the
        //   canvas → 1/zoom → parent.drawing → ×zoom → displayDrawing
        // path means `canvasView.drawing` and the freshly-recomputed
        // `displayDrawing` are almost never byte-identical, so a naive
        // `!=` check would reassign on every stroke and produce the
        // flicker / disappear-reappear glitch the user is reporting.
        if let last = context.coordinator.lastPublishedBaseDrawing,
           last == drawing {
            // The binding's value came from our own delegate echo —
            // the canvas already has the correct content, leave it
            // alone.
            return
        }

        // Binding changed from outside (page load, undo, clear-page).
        // Push the (newly-scaled) drawing into the canvas once.
        let displayDrawing = drawing.transformed(
            using: CGAffineTransform(scaleX: safeZoom, y: safeZoom)
        )
        context.coordinator.suppressNextDelegateChange = true
        context.coordinator.lastPublishedBaseDrawing = drawing
        canvasView.drawing = displayDrawing
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var parent: PencilCanvasView
        var isDrawing: Bool = false
        /// Zoom we last pushed into the canvas. Used to detect when we
        /// need to rescale the display drawing.
        var appliedZoom: CGFloat = 1.0
        /// Set to true when we programmatically assign
        /// `canvasView.drawing`, so the immediately-following
        /// `canvasViewDrawingDidChange` callback doesn't echo the
        /// scaled drawing back into the binding (which would
        /// permanently scale persisted strokes on every zoom change).
        var suppressNextDelegateChange = false
        /// The base-coordinate `PKDrawing` we most recently either
        /// (a) published up to the binding via the delegate, or
        /// (b) pushed into the canvas via `updateUIView`.
        ///
        /// We compare incoming binding values against this so we can
        /// tell "the binding changed because of our own delegate echo"
        /// (skip — canvas is already correct) from "the binding changed
        /// because of an external mutation like a page swap or undo"
        /// (reassign the canvas drawing). Without this distinction the
        /// round-trip
        ///   canvas → ×(1/zoom) → binding → ×zoom → canvas
        /// causes floating-point drift that makes the canvas content
        /// never byte-equal what we'd recompute, so a naive `!=` check
        /// would reassign every stroke and flicker the ink.
        var lastPublishedBaseDrawing: PKDrawing?

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            parent.onPencilDoubleTap?(interaction)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if suppressNextDelegateChange {
                suppressNextDelegateChange = false
                return
            }
            // Map the canvas's drawing (in scaled coords) back to base
            // coords before publishing — so the view model always holds
            // base-coordinate strokes regardless of the current zoom.
            let inverse = 1.0 / max(0.0001, appliedZoom)
            let baseDrawing = canvasView.drawing.transformed(
                using: CGAffineTransform(scaleX: inverse, y: inverse)
            )
            lastPublishedBaseDrawing = baseDrawing
            if parent.drawing != baseDrawing {
                parent.drawing = baseDrawing
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
