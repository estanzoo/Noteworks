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
//    • Two-finger pinch       → outer scroll view zoom.
//    • Two-finger pan         → outer scroll view content offset
//      (only effective when the page is zoomed past 1×).
//
//  Crisp pencil rendering trick: after a zoom interaction ends, the
//  embedded `PKCanvasView` has its `contentScaleFactor` bumped to
//  `screenScale × zoomScale`, forcing PencilKit to re-rasterize strokes
//  at the new effective resolution. Without this, the GPU rescales a
//  fixed-resolution bitmap and the ink looks blurry at 2×–4×.
//

import SwiftUI
import UIKit
import PencilKit

struct ZoomablePageScrollView<Content: View>: UIViewRepresentable {

    let contentSize: CGSize
    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 4.0
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

        // The page card is the only content; bouncing it at edges feels
        // jittery, especially when the user is mid-stroke.
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
        // Initial centering — runs after the scroll view's bounds settle.
        DispatchQueue.main.async {
            context.coordinator.recenter(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Always re-push the SwiftUI tree so view-model changes propagate.
        context.coordinator.host?.rootView = content()

        // Reset zoom + content frame only when the natural page size
        // actually changes (rotation flip, window resize). Doing this on
        // every update would clobber a live zoom interaction.
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
            // bounds can change (e.g. chrome resize) without the content
            // size changing.
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

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // Re-rasterize PencilKit at the new effective resolution so
            // ink stays crisp at high zoom. We deliberately only do this
            // at zoom-end (not on every frame) to keep mid-pinch
            // interaction smooth — temporary blur during the pinch is
            // imperceptible.
            findCanvas(in: view)?.contentScaleFactor = UIScreen.main.scale * scale
        }

        /// Keep the page card centered inside the scroll view when its
        /// zoomed size is smaller than the visible bounds. At scale=1
        /// the page is always smaller than the canvas area, so this is
        /// what produces the "page floating with a margin" look.
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

        /// Recursive search through the hosted view tree for the
        /// `PKCanvasView` we need to retune the content scale on. The
        /// hosting controller flattens SwiftUI into a UIView hierarchy
        /// where the canvas can be a couple of layers deep, so a plain
        /// `subviews.first` won't always hit it.
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
