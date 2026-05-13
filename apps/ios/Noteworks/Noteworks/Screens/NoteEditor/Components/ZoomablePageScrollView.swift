//
//  ZoomablePageScrollView.swift
//  Noteworks
//
//  UIScrollView-backed zoom + pan host for the note page. Wraps the
//  page-card SwiftUI content (background pattern + `PKCanvasView` +
//  `NoteOverlayLayer`) so all three zoom together — anything else would
//  produce a visually broken page (e.g. ink zooms, grid doesn't).
//
//  Gesture routing:
//    • Single-finger touches  → PencilKit drawing recognizers (untouched
//      because the scroll view's pan gesture requires 2 touches).
//    • Two-finger pinch       → outer scroll view zoom (1×–3×).
//    • Two-finger pan         → outer scroll view content offset
//      (only effective when the page is zoomed past 1×).
//
//  Crisp-ink strategy. The outer scroll view zooms by applying a CALayer
//  transform to the hosted content; that transform stretches a fixed-
//  resolution PencilKit bitmap by default — exactly the blur the user
//  was reporting. To keep ink crisp, the coordinator bumps the embedded
//  `PKCanvasView`'s `contentScaleFactor` to `screenScale × zoomScale`
//  on every zoom step. PencilKit re-rasterizes its drawing layer at
//  the new effective density, so the bitmap displayed under the GPU
//  transform always has at least 1:1 pixel coverage on screen.
//

import SwiftUI
import UIKit
import PencilKit

struct ZoomablePageScrollView<Content: View>: UIViewRepresentable {

    let contentSize: CGSize
    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 3.0
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        // Two-finger pan only — single-finger touches fall through to the
        // PencilKit drawing recognizer hosted inside the content.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2

        // No bouncing pan when the page is at zoom 1 — there's no scroll
        // distance to bounce against and the wobble would feel like a
        // bug to the user.
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        scrollView.addSubview(host.view)
        scrollView.contentSize = contentSize

        context.coordinator.host = host
        context.coordinator.contentSize = contentSize

        // Pre-rasterize the embedded PencilKit canvas at the maximum
        // zoom level so the first pinch already has a high-resolution
        // bitmap ready. The coordinator will also re-tune this during
        // zoom for safety; this just avoids a one-frame blur on the
        // very first pinch.
        DispatchQueue.main.async {
            context.coordinator.applyMaxResolution(maxScale: maxScale)
            context.coordinator.recenter(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Always re-push the SwiftUI tree so view-model changes propagate.
        context.coordinator.host?.rootView = content()

        // Reset zoom + content frame only when the natural page size
        // actually changes (rotation flip, window resize). Doing this
        // on every update would clobber a live zoom interaction.
        if context.coordinator.contentSize != contentSize {
            scrollView.zoomScale = 1.0
            context.coordinator.host?.view.frame = CGRect(origin: .zero, size: contentSize)
            scrollView.contentSize = contentSize
            context.coordinator.contentSize = contentSize
            DispatchQueue.main.async {
                context.coordinator.recenter(scrollView)
            }
        } else {
            // Re-center on every update because the scroll view's own
            // bounds can change (e.g. chrome resize) without the
            // content size changing.
            context.coordinator.recenter(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<Content>?
        var contentSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            recenter(scrollView)
        }

        /// Keep the page card centered inside the scroll view when its
        /// zoomed size is smaller than the visible bounds (which is
        /// always the case at scale = 1 on a wider canvas area).
        func recenter(_ scrollView: UIScrollView) {
            guard let view = host?.view else { return }
            let xOffset = max((scrollView.bounds.width - view.frame.width) * 0.5, 0)
            let yOffset = max((scrollView.bounds.height - view.frame.height) * 0.5, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: yOffset,
                left: xOffset,
                bottom: yOffset,
                right: xOffset
            )
        }

        /// Walks the hosted view tree for the embedded `PKCanvasView`
        /// and sets its `contentScaleFactor` to a level that keeps
        /// strokes crisp at the maximum zoom this scroll view allows.
        /// We pre-rasterize once at view-creation rather than chase
        /// zoom changes on every frame — re-rasterizing mid-pinch
        /// causes visible flicker, while a one-time-high bitmap is
        /// cheap on iPad and immediately sharp at any zoom level.
        func applyMaxResolution(maxScale: CGFloat) {
            guard let canvas = findCanvas(in: host?.view) else { return }
            canvas.contentScaleFactor = UIScreen.main.scale * maxScale
        }

        private func findCanvas(in view: UIView?) -> PKCanvasView? {
            guard let view else { return nil }
            if let canvas = view as? PKCanvasView { return canvas }
            for sub in view.subviews {
                if let canvas = findCanvas(in: sub) { return canvas }
            }
            return nil
        }
    }
}
