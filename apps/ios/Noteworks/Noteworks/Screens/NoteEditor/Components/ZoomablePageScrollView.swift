//
//  ZoomablePageScrollView.swift
//  Noteworks
//
//  UIScrollView-backed zoom + pan host for the note page. Wraps the
//  page-card SwiftUI content (background pattern + `PKCanvasView` +
//  `NoteOverlayLayer`) so all three zoom together.
//
//  Gesture routing:
//    • Single-finger touches → PencilKit drawing (scroll view pan uses 2 touches).
//    • Two-finger pinch → outer scroll view zoom.
//    • Two-finger pan → scroll when zoomed past 1×.
//
//  The outer scroll view zoom applies a transform to the hosted view.
//  The coordinator bumps the embedded `PKCanvasView`'s `contentScaleFactor`
//  to `screenScale × maxScale` once the SwiftUI hierarchy has laid out,
//  so PencilKit rasterizes at higher resolution and looks sharper when zoomed.
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

        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2

        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        scrollView.addSubview(host.view)
        scrollView.contentSize = contentSize

        context.coordinator.host = host
        context.coordinator.maxZoom = maxScale
        context.coordinator.contentSize = contentSize

        DispatchQueue.main.async {
            context.coordinator.applyMaxResolutionIfPossible()
            context.coordinator.recenter(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.maxZoom = maxScale
        context.coordinator.host?.rootView = content()

        if context.coordinator.contentSize != contentSize {
            scrollView.zoomScale = 1.0
            context.coordinator.host?.view.frame = CGRect(origin: .zero, size: contentSize)
            scrollView.contentSize = contentSize
            context.coordinator.contentSize = contentSize
            DispatchQueue.main.async {
                context.coordinator.applyMaxResolutionIfPossible()
                context.coordinator.recenter(scrollView)
            }
        } else {
            context.coordinator.recenter(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<Content>?
        var contentSize: CGSize = .zero
        var maxZoom: CGFloat = 3.0

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            recenter(scrollView)
        }

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

        func applyMaxResolutionIfPossible() {
            guard let canvas = findCanvas(in: host?.view) else { return }
            let scale = UIScreen.main.scale * maxZoom
            if abs(canvas.contentScaleFactor - scale) > 0.01 {
                canvas.contentScaleFactor = scale
            }
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
