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

    override func addInteraction(_ interaction: UIInteraction) {
        if #available(iOS 16.0, *), interaction is UIEditMenuInteraction { return }
        super.addInteraction(interaction)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    /// PencilKit attaches `UIEditMenuInteraction` on iOS 17+ so a single
    /// canvas tap offers "Select All" / "Insert Space". We provide our own
    /// chrome — strip those interactions so a tap does nothing.
    func stripSystemEditMenus() {
        guard #available(iOS 16.0, *) else { return }
        for view in [self] + allSubviewsRecursive {
            for interaction in view.interactions where interaction is UIEditMenuInteraction {
                view.removeInteraction(interaction)
            }
        }
    }

    /// Yield touches to the overlay layer beneath when Select mode (or
    /// finger-only pass-through in write tools) requests it.
    private func shouldPassThrough(event: UIEvent?) -> Bool {
        guard passesFingerTouchesThrough || passesPencilTouchesThrough else { return false }

        let touches = event?.allTouches ?? []
        // Always yield multi-finger sequences to the outer scroll view.
        if touches.count >= 2 { return true }

        // Hit-test probe with no typed touches yet. Image-select must
        // yield here too — returning false kept the canvas as the hit
        // target so PencilKit still inked despite pass-through.
        if touches.isEmpty {
            return passesPencilTouchesThrough
        }

        let isPencil = touches.contains(where: { $0.type == .pencil })
        if isPencil {
            return passesPencilTouchesThrough
        }

        guard passesFingerTouchesThrough else { return false }

        let drawingState = drawingGestureRecognizer.state
        if drawingState == .began || drawingState == .changed { return false }
        return true
    }

    func applyTouchRoutingPolicy(allowsPencilDrawing: Bool) {
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        let fingerAndPencil = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)
        ]

        isMultipleTouchEnabled = true

        if passesPencilTouchesThrough {
            drawingGestureRecognizer.allowedTouchTypes = []
        } else if passesFingerTouchesThrough {
            drawingGestureRecognizer.allowedTouchTypes = [pencil]
        } else {
            drawingGestureRecognizer.allowedTouchTypes = fingerAndPencil
        }

        drawingGestureRecognizer.isEnabled = allowsPencilDrawing
        isDrawingEnabled = allowsPencilDrawing

        // PKCanvasView inherits UIScrollView's pan/pinch recognizers.
        // The outer ZoomablePageScrollView owns page zoom.
        pinchGestureRecognizer?.isEnabled = false
        panGestureRecognizer.isEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTouchRoutingPolicy(allowsPencilDrawing: drawingGestureRecognizer.isEnabled)
        stripSystemEditMenus()
        // PencilKit sometimes attaches edit-menu interactions one runloop
        // after the view lands in the hierarchy.
        DispatchQueue.main.async { [weak self] in
            self?.stripSystemEditMenus()
        }
    }
}

private extension UIView {
    var allSubviewsRecursive: [UIView] {
        subviews + subviews.flatMap(\.allSubviewsRecursive)
    }
}

struct PencilCanvasView: UIViewRepresentable {

    /// Live drawing — bound to the parent so strokes flow up and page
    /// swaps flow down. Stored in **base** (zoom == 1) coordinates so
    /// it round-trips through disk regardless of the current zoom.
    @Binding var drawing: PKDrawing

    /// Incremented only when the view model deliberately replaces the
    /// page drawing (page load, clear page). Live strokes update the
    /// binding via the delegate but must NOT be pushed back into the
    /// canvas — reassigning `canvasView.drawing` clears PencilKit's undo
    /// stack and invalidates stroke identifiers.
    var drawingPushGeneration: Int = 0

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

    /// Fired after every user-driven drawing mutation (stroke, erase,
    /// undo, redo). Passes the base-coordinate drawing from before the
    /// change so the editor can record a unified undo step.
    var onDrawingChanged: ((PKDrawing) -> Void)? = nil

    /// Apple Pencil double-tap (Settings → Apple Pencil). Without
    /// `PKToolPicker`, the app must handle `UIPencilInteraction` explicitly.
    var onPencilDoubleTap: ((UIPencilInteraction) -> Void)? = nil

    func makeUIView(context: Context) -> FingerPassThroughPKCanvasView {
        let canvasView = FingerPassThroughPKCanvasView()
        canvasView.passesFingerTouchesThrough = passesFingerTouchesThrough
        canvasView.passesPencilTouchesThrough = passesPencilTouchesThrough
        canvasView.drawingPolicy = drawingPolicy
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isMultipleTouchEnabled = true
        context.coordinator.appliedZoom = max(0.0001, zoomScale)
        context.coordinator.lastConsumedPushGeneration = drawingPushGeneration
        context.coordinator.lastKnownBaseDrawing = drawing
        canvasView.drawing = scaledDisplayDrawing(from: drawing, zoom: zoomScale)
        canvasView.tool = tool
        canvasView.delegate = context.coordinator
        canvasView.isUserInteractionEnabled = isDrawingEnabled
        canvasView.applyTouchRoutingPolicy(allowsPencilDrawing: allowsPencilDrawing)

        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.bouncesZoom = false

        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvasView.addInteraction(pencil)

        canvasView.stripSystemEditMenus()

        DispatchQueue.main.async {
            onCanvasReady?(canvasView)
        }
        return canvasView
    }

    func updateUIView(_ canvasView: FingerPassThroughPKCanvasView, context: Context) {
        let routingChanged = canvasView.passesFingerTouchesThrough != passesFingerTouchesThrough
            || canvasView.passesPencilTouchesThrough != passesPencilTouchesThrough
        canvasView.passesFingerTouchesThrough = passesFingerTouchesThrough
        canvasView.passesPencilTouchesThrough = passesPencilTouchesThrough
        if routingChanged
            || canvasView.drawingGestureRecognizer.isEnabled != allowsPencilDrawing
            || canvasView.isDrawingEnabled != allowsPencilDrawing {
            canvasView.applyTouchRoutingPolicy(allowsPencilDrawing: allowsPencilDrawing)
        }
        if canvasView.drawingPolicy != drawingPolicy {
            canvasView.drawingPolicy = drawingPolicy
        }
        if canvasView.isUserInteractionEnabled != isDrawingEnabled {
            canvasView.isUserInteractionEnabled = isDrawingEnabled
        }
        canvasView.tool = tool
        context.coordinator.parent = self

        if context.coordinator.isDrawing {
            // Don't yank the canvas out from under the user mid-stroke.
            return
        }

        let safeZoom = max(0.0001, zoomScale)
        let zoomChanged = abs(context.coordinator.appliedZoom - safeZoom) > 0.0005

        if zoomChanged {
            // Zoom changed → push the freshly-scaled drawing into the
            // canvas exactly ONCE. PencilKit re-rasterises the strokes
            // at the new size, producing genuinely-crisp ink.
            pushDrawingToCanvas(
                canvasView,
                coordinator: context.coordinator,
                zoom: safeZoom
            )
            context.coordinator.appliedZoom = safeZoom
            return
        }

        // Only push when the view model explicitly replaced the page
        // drawing. Echoing live binding updates back into the canvas
        // replaces PKDrawing wholesale and breaks undo/redo.
        guard context.coordinator.lastConsumedPushGeneration != drawingPushGeneration else {
            return
        }

        pushDrawingToCanvas(
            canvasView,
            coordinator: context.coordinator,
            zoom: safeZoom
        )
        context.coordinator.lastConsumedPushGeneration = drawingPushGeneration
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func scaledDisplayDrawing(from baseDrawing: PKDrawing, zoom: CGFloat) -> PKDrawing {
        baseDrawing.transformed(
            using: CGAffineTransform(scaleX: zoom, y: zoom)
        )
    }

    private func pushDrawingToCanvas(
        _ canvasView: PKCanvasView,
        coordinator: Coordinator,
        zoom: CGFloat
    ) {
        coordinator.suppressNextDelegateChange = true
        coordinator.lastKnownBaseDrawing = drawing
        canvasView.drawing = scaledDisplayDrawing(from: drawing, zoom: zoom)
    }

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
        /// Last `drawingPushGeneration` consumed by `updateUIView`.
        var lastConsumedPushGeneration: Int = 0
        /// Base-coordinate drawing last emitted to the binding — used to
        /// build undo steps when PencilKit reports a new stroke.
        var lastKnownBaseDrawing: PKDrawing?

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
            let previousDrawing = lastKnownBaseDrawing ?? baseDrawing
            lastKnownBaseDrawing = baseDrawing
            if parent.drawing != baseDrawing {
                parent.drawing = baseDrawing
            }
            parent.onDrawingChanged?(previousDrawing)
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
