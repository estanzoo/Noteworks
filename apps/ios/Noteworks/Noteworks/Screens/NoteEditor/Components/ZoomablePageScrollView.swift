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
//    • Finger horizontal page drag at ~1× → whole-page slide navigation.
//    • Double-tap → toggle between fit and ~2.5× zoom at the tap point.
//

import SwiftUI
import UIKit
import PencilKit

struct ZoomablePageScrollView<Content: View>: UIViewRepresentable {

    let contentSize: CGSize
    var maxScale: CGFloat = 8.0
    var doubleTapZoomScale: CGFloat = 2.5
    var nextSwipeCreatesPage: Bool = false
    var atFirstPage: Bool = false
    var onSwipeNext: (() -> Void)? = nil
    var onSwipePrevious: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = maxScale
        // Allow temporary pinch-out below the default size; release snaps
        // back to `baselineZoomScale` (see `scrollViewDidEndZooming`).
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.indicatorStyle = .default
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .interactive
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear

        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false

        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]

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

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        doubleTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(doubleTap)

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        scrollView.addSubview(host.view)
        scrollView.contentSize = contentSize

        context.coordinator.host = host
        context.coordinator.maxZoom = maxScale
        context.coordinator.doubleTapZoomScale = doubleTapZoomScale
        context.coordinator.contentSize = contentSize
        context.coordinator.onSwipeNext = onSwipeNext
        context.coordinator.onSwipePrevious = onSwipePrevious
        context.coordinator.nextSwipeCreatesPage = nextSwipeCreatesPage
        context.coordinator.atFirstPage = atFirstPage
        context.coordinator.pagePanGesture = pagePan

        DispatchQueue.main.async {
            context.coordinator.updateZoomLimits(scrollView)
            context.coordinator.applyInitialFillZoomIfNeeded(scrollView)
            context.coordinator.applyCanvasResolution(for: scrollView.zoomScale)
            context.coordinator.recenter(scrollView)
            scrollView.setContentOffset(
                CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top),
                animated: false
            )
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.maxZoom = maxScale
        context.coordinator.doubleTapZoomScale = doubleTapZoomScale
        context.coordinator.onSwipeNext = onSwipeNext
        context.coordinator.onSwipePrevious = onSwipePrevious
        context.coordinator.nextSwipeCreatesPage = nextSwipeCreatesPage
        context.coordinator.atFirstPage = atFirstPage
        context.coordinator.host?.rootView = content()

        if context.coordinator.contentSize != contentSize {
            scrollView.zoomScale = 1.0
            context.coordinator.resetInitialFillZoom()
            context.coordinator.host?.view.frame = CGRect(origin: .zero, size: contentSize)
            scrollView.contentSize = contentSize
            context.coordinator.contentSize = contentSize
            DispatchQueue.main.async {
                context.coordinator.updateZoomLimits(scrollView)
                context.coordinator.applyInitialFillZoomIfNeeded(scrollView)
                context.coordinator.applyCanvasResolution(for: scrollView.zoomScale)
                context.coordinator.recenter(scrollView)
                scrollView.setContentOffset(
                    CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top),
                    animated: false
                )
            }
        } else {
            context.coordinator.updateZoomLimits(scrollView)
            context.coordinator.recenter(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var host: UIHostingController<Content>?
        var contentSize: CGSize = .zero
        var maxZoom: CGFloat = 8.0
        var doubleTapZoomScale: CGFloat = 2.5
        /// Scale that fits the entire page inside the viewport (pinch-out target).
        var fitEntirePageScale: CGFloat = 1.0
        var onSwipeNext: (() -> Void)?
        var onSwipePrevious: (() -> Void)?
        var nextSwipeCreatesPage: Bool = false
        var atFirstPage: Bool = false
        weak var pagePanGesture: UIPanGestureRecognizer?
        private var isSlidingPage = false
        private var didFireBoundaryHaptic = false
        private var didApplyInitialFillZoom = false
        /// Slight scale-up only when the page is much smaller than the viewport.
        private let initialFillMargin: CGFloat = 0.88
        private let maxInitialFillZoom: CGFloat = 1.05
        /// Default zoom after initial layout — used as the pinch-out floor.
        private(set) var baselineZoomScale: CGFloat = 1.0

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            recenter(scrollView)
            applyCanvasResolution(for: scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            snapToBaselineZoomIfNeeded(scrollView)
            recenter(scrollView)
            applyCanvasResolution(for: scrollView.zoomScale)
        }

        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            updateZoomLimits(scrollView)
            applyInitialFillZoomIfNeeded(scrollView)
            recenter(scrollView)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let location = gesture.location(in: scrollView)
            let baseline = baselineZoomScale > 0 ? baselineZoomScale : 1.0
            let isZoomedIn = scrollView.zoomScale > baseline * 1.12
            let targetScale: CGFloat
            if isZoomedIn {
                targetScale = baseline
            } else {
                targetScale = min(doubleTapZoomScale, scrollView.maximumZoomScale)
            }
            let clamped = min(max(targetScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            let rect = zoomRect(for: clamped, center: location, in: scrollView)
            scrollView.zoom(to: rect, animated: true)
        }

        @objc func handlePagePan(_ sender: UIPanGestureRecognizer) {
            guard let scrollView = sender.view as? UIScrollView,
                  let pageView = host?.view,
                  scrollView.zoomScale <= 1.08 else {
                resetPageSlide(animated: true)
                return
            }

            let translation = sender.translation(in: scrollView)
            let velocity = sender.velocity(in: scrollView)

            switch sender.state {
            case .began:
                isSlidingPage = false
                didFireBoundaryHaptic = false
            case .changed:
                if !isSlidingPage {
                    guard abs(translation.x) > 10,
                          abs(translation.x) > abs(translation.y) * 1.15 else { return }
                    isSlidingPage = true
                }
                guard isSlidingPage else { return }

                let width = max(scrollView.bounds.width, 1)
                let raw = translation.x
                let isNextSwipe = raw < 0
                let isPrevSwipe = raw > 0
                let creatingNewPage = isNextSwipe && nextSwipeCreatesPage
                let atPrevBoundary = isPrevSwipe && atFirstPage
                let displayedX: CGFloat
                if creatingNewPage || atPrevBoundary {
                    displayedX = Coordinator.rubberBand(raw, dimension: width)
                    let cueThreshold = max(width * 0.22, 80)
                    if creatingNewPage, !didFireBoundaryHaptic, abs(raw) > cueThreshold {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
                        didFireBoundaryHaptic = true
                    } else if abs(raw) < cueThreshold * 0.6 {
                        didFireBoundaryHaptic = false
                    }
                } else {
                    displayedX = raw * 0.82
                    didFireBoundaryHaptic = false
                }
                pageView.transform = CGAffineTransform(translationX: displayedX, y: 0)
            case .ended, .cancelled, .failed:
                guard isSlidingPage else {
                    resetPageSlide(animated: true)
                    didFireBoundaryHaptic = false
                    return
                }
                let width = scrollView.bounds.width
                let isNextSwipe = translation.x < 0
                let creatingNewPage = isNextSwipe && nextSwipeCreatesPage
                let atPrevBoundary = !isNextSwipe && atFirstPage
                let inResistanceZone = creatingNewPage || atPrevBoundary

                let normalDistance = max(70, width * 0.18)
                let resistDistance = max(140, width * 0.34)
                let distanceThreshold = inResistanceZone ? resistDistance : normalDistance
                let velocityThreshold: CGFloat = inResistanceZone ? 1050 : 650

                let shouldGoNext = translation.x < -distanceThreshold || velocity.x < -velocityThreshold
                let shouldGoPrevious = translation.x > distanceThreshold || velocity.x > velocityThreshold
                if shouldGoNext || shouldGoPrevious {
                    let offscreen = (shouldGoNext ? -1 : 1) * max(width, contentSize.width)
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
                didFireBoundaryHaptic = false
            default:
                break
            }
        }

        static func rubberBand(_ offset: CGFloat, dimension: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
            guard dimension > 0 else { return offset }
            let magnitude = Swift.abs(offset)
            let damped = (1.0 - 1.0 / (magnitude * coefficient / dimension + 1.0)) * dimension
            return offset >= 0 ? damped : -damped
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
            guard scrollView.zoomScale <= 1.08 else { return false }
            let velocity = pan.velocity(in: scrollView)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        func updateZoomLimits(_ scrollView: UIScrollView) {
            guard contentSize.width > 0, contentSize.height > 0,
                  scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }

            let fitW = scrollView.bounds.width / contentSize.width
            let fitH = scrollView.bounds.height / contentSize.height
            fitEntirePageScale = min(fitW, fitH)

            // Default resting zoom — pinch-out below this bounces back on release.
            let baseline = baselineZoomScale > 0 ? baselineZoomScale : 1.0
            scrollView.minimumZoomScale = baseline
            scrollView.maximumZoomScale = maxZoom

            // Only correct drift from layout changes, not an active pinch-out.
            if scrollView.zoomScale < baseline - 0.01, !scrollView.isZooming {
                scrollView.setZoomScale(baseline, animated: false)
            }
        }

        /// After pinch-out, return to the default page size the user opened with.
        func snapToBaselineZoomIfNeeded(_ scrollView: UIScrollView) {
            let baseline = baselineZoomScale > 0 ? baselineZoomScale : 1.0
            guard scrollView.zoomScale < baseline - 0.008 else { return }
            scrollView.setZoomScale(baseline, animated: true)
        }

        func resetInitialFillZoom() {
            didApplyInitialFillZoom = false
            baselineZoomScale = 1.0
        }

        /// When the fitted page is smaller than the viewport (common on
        /// landscape), scale up slightly so the first view feels natural.
        func applyInitialFillZoomIfNeeded(_ scrollView: UIScrollView) {
            guard !didApplyInitialFillZoom,
                  contentSize.width > 0, contentSize.height > 0,
                  scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }

            let fitW = scrollView.bounds.width / contentSize.width
            let fitH = scrollView.bounds.height / contentSize.height
            let fillScale = min(fitW, fitH)
            guard fillScale > 1.02 else {
                baselineZoomScale = 1.0
                didApplyInitialFillZoom = true
                updateZoomLimits(scrollView)
                return
            }

            let target = min(fillScale * initialFillMargin, maxInitialFillZoom)
            let zoom = max(1.0, target)
            scrollView.zoomScale = zoom
            baselineZoomScale = zoom
            didApplyInitialFillZoom = true
            updateZoomLimits(scrollView)
            recenter(scrollView)
        }

        func recenter(_ scrollView: UIScrollView) {
            guard let view = host?.view else { return }
            // The zoom view's `frame` already reflects the current
            // zoomScale — multiplying by zoomScale again over-counts and
            // forces xOffset to 0, which is what made the page collapse
            // against the leading edge when zoomed in.
            let zoomedWidth = view.frame.width
            let zoomedHeight = view.frame.height
            let minVerticalMargin: CGFloat = 24
            let xOffset = max((scrollView.bounds.width - zoomedWidth) * 0.5, 0)

            let top: CGFloat
            let bottom: CGFloat
            if zoomedHeight + minVerticalMargin * 2 <= scrollView.bounds.height {
                let vertical = max((scrollView.bounds.height - zoomedHeight) * 0.5, minVerticalMargin)
                top = vertical
                bottom = vertical
            } else {
                top = minVerticalMargin
                bottom = minVerticalMargin
            }

            scrollView.contentInset = UIEdgeInsets(
                top: top,
                left: xOffset,
                bottom: bottom,
                right: xOffset
            )
        }

        func applyCanvasResolution(for zoomScale: CGFloat) {
            guard let canvas = findCanvas(in: host?.view) else { return }
            let rasterScale = UIScreen.main.scale * min(maxZoom, max(1, zoomScale) * 2)
            if abs(canvas.contentScaleFactor - rasterScale) > 0.01 {
                canvas.contentScaleFactor = rasterScale
            }
        }

        private func zoomRect(for scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let origin = CGPoint(
                x: center.x - size.width * 0.5,
                y: center.y - size.height * 0.5
            )
            return CGRect(origin: origin, size: size)
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
