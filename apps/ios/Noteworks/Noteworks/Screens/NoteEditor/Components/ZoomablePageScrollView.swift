//
//  ZoomablePageScrollView.swift
//  Noteworks
//
//  UIScrollView-backed zoom + pan host for the note page. Wraps the
//  page-card SwiftUI content (background pattern + `PKCanvasView` +
//  `NoteOverlayLayer`) so all three zoom together.
//
//  Gesture routing:
//    • Apple Pencil touches → PencilKit drawing.
//    • Finger pinch / pan → outer scroll view zoom and movement.
//    • Finger horizontal page drag at 1× → whole-page slide navigation.
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
    var onSwipeNext: (() -> Void)? = nil
    var onSwipePrevious: (() -> Void)? = nil
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

        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        let pagePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePagePan(_:))
        )
        pagePan.maximumNumberOfTouches = 1
        pagePan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pagePan.cancelsTouchesInView = false
        pagePan.delegate = context.coordinator
        scrollView.addGestureRecognizer(pagePan)
        scrollView.panGestureRecognizer.require(toFail: pagePan)

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
        context.coordinator.onSwipeNext = onSwipeNext
        context.coordinator.onSwipePrevious = onSwipePrevious
        context.coordinator.pagePanGesture = pagePan

        DispatchQueue.main.async {
            context.coordinator.applyMaxResolutionIfPossible()
            context.coordinator.recenter(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.maxZoom = maxScale
        context.coordinator.onSwipeNext = onSwipeNext
        context.coordinator.onSwipePrevious = onSwipePrevious
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

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var host: UIHostingController<Content>?
        var contentSize: CGSize = .zero
        var maxZoom: CGFloat = 3.0
        var onSwipeNext: (() -> Void)?
        var onSwipePrevious: (() -> Void)?
        weak var pagePanGesture: UIPanGestureRecognizer?
        private var isSlidingPage = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            recenter(scrollView)
        }

        @objc func handlePagePan(_ sender: UIPanGestureRecognizer) {
            guard let scrollView = sender.view as? UIScrollView,
                  let pageView = host?.view,
                  scrollView.zoomScale <= 1.05 else {
                resetPageSlide(animated: true)
                return
            }

            let translation = sender.translation(in: scrollView)
            let velocity = sender.velocity(in: scrollView)

            switch sender.state {
            case .began:
                isSlidingPage = false
            case .changed:
                if !isSlidingPage {
                    guard abs(translation.x) > 10,
                          abs(translation.x) > abs(translation.y) * 1.15 else { return }
                    isSlidingPage = true
                }
                guard isSlidingPage else { return }
                let resistance: CGFloat = 0.82
                pageView.transform = CGAffineTransform(translationX: translation.x * resistance, y: 0)
            case .ended, .cancelled, .failed:
                guard isSlidingPage else {
                    resetPageSlide(animated: true)
                    return
                }
                let threshold = max(70, scrollView.bounds.width * 0.18)
                // Match GoodNotes / Notability: swipe left → next page (page exits left);
                // swipe right → previous page (page exits right).
                let shouldGoNext = translation.x < -threshold || velocity.x < -650
                let shouldGoPrevious = translation.x > threshold || velocity.x > 650
                if shouldGoNext || shouldGoPrevious {
                    let offscreen = (shouldGoNext ? -1 : 1) * max(scrollView.bounds.width, contentSize.width)
                    UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
                        pageView.transform = CGAffineTransform(translationX: offscreen, y: 0)
                    } completion: { [weak self] _ in
                        pageView.transform = .identity
                        if shouldGoNext {
                            self?.onSwipeNext?()
                        } else {
                            self?.onSwipePrevious?()
                        }
                    }
                } else {
                    resetPageSlide(animated: true)
                }
                isSlidingPage = false
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pagePanGesture,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView = pan.view as? UIScrollView else {
                return true
            }
            guard scrollView.zoomScale <= 1.05 else { return false }
            let velocity = pan.velocity(in: scrollView)
            return abs(velocity.x) > abs(velocity.y) * 1.2
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

        private func resetPageSlide(animated: Bool) {
            guard let pageView = host?.view else { return }
            let changes = { pageView.transform = .identity }
            if animated {
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: changes)
            } else {
                changes()
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
