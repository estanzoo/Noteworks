//
//  ZoomablePageScrollView.swift
//  Noteworks
//
//  UIScrollView-backed zoom + pan host for the note page. The page card
//  (background → overlays → PencilKit) lives in one `UIHostingController`.
//  `contentStamp` gates `rootView` updates so overlay drag frames do not
//  rebuild the tree (which caused snap-back / bounce).
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
    /// Suppresses horizontal page-swipe while an overlay is selected.
    var blocksPageGestures: Bool = false
    /// Bump when persisted page data changes — not during live overlay drag.
    var contentStamp: Int = 0
    var onSwipeNext: (() -> Void)? = nil
    var onSwipePrevious: (() -> Void)? = nil
    /// Fired on a single-finger tap. `nil` means the grey margin outside
    /// the page card; a point means page-content coordinates (top-left of
    /// the hosted page). Used for overlay select / deselect without
    /// putting tap targets on the image body (which would steal pinch).
    var onPageFingerTap: ((CGPoint?) -> Void)? = nil
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = maxScale
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.indicatorStyle = .default
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .interactive
        scrollView.decelerationRate = .normal
        scrollView.backgroundColor = .clear

        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false

        // Critical for finger-drag on overlays (image / text / shape).
        // Without these, `UIScrollView` swallows the touch before the
        // SwiftUI `DragGesture` on the overlay can recognize:
        //   - `delaysContentTouches = true` (default) makes the scroll
        //     view sit on the touch for ~150ms before delivering it down,
        //     long enough for its pan recognizer to be the first to see
        //     the user's movement.
        //   - `canCancelContentTouches = true` (default) lets the scroll
        //     view yank the touch back from a subview that has already
        //     started tracking it, so even a winning SwiftUI drag gets
        //     cancelled mid-gesture once the scroll view's pan kicks in.
        // The previous workaround was to flip `blocksPageGestures` to
        // true whenever an overlay was selected — but that meant the
        // very first finger drag on an unselected image always lost to
        // the scroll view, exactly the bug we just hit. Disabling both
        // hands every touch directly to whichever child claims it
        // first; empty-canvas pan/scroll still works because the canvas
        // doesn't claim those touches (its drawing recognizer is
        // pencil-only), so the scroll view's pan gets them by default.
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = false
        scrollView.isMultipleTouchEnabled = true
        scrollView.isScrollEnabled = true
        scrollView.pinchGestureRecognizer?.isEnabled = true

        // Pinch-to-zoom needs two fingers exclusively — if the built-in
        // pan recognizer also accepts 2 touches it wins the gesture
        // race and page zoom silently stops working.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 1
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

        let canvasTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCanvasFingerTap(_:))
        )
        canvasTap.numberOfTapsRequired = 1
        canvasTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        canvasTap.cancelsTouchesInView = false
        canvasTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(canvasTap)
        canvasTap.require(toFail: doubleTap)

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.isMultipleTouchEnabled = true

        let contentRoot = PinchPassthroughContentView(frame: CGRect(origin: .zero, size: contentSize))
        contentRoot.isMultipleTouchEnabled = true
        contentRoot.hostingView = host.view
        contentRoot.addSubview(host.view)
        host.view.frame = contentRoot.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(contentRoot)
        scrollView.contentSize = contentSize

        context.coordinator.host = host
        context.coordinator.contentRoot = contentRoot
        context.coordinator.contentStamp = contentStamp
        context.coordinator.maxZoom = maxScale
        context.coordinator.doubleTapZoomScale = doubleTapZoomScale
        context.coordinator.contentSize = contentSize
        context.coordinator.onSwipeNext = onSwipeNext
        context.coordinator.onSwipePrevious = onSwipePrevious
        context.coordinator.nextSwipeCreatesPage = nextSwipeCreatesPage
        context.coordinator.atFirstPage = atFirstPage
        context.coordinator.pagePanGesture = pagePan
        context.coordinator.canvasTapGesture = canvasTap
        context.coordinator.blocksPageGestures = blocksPageGestures
        context.coordinator.onPageFingerTap = onPageFingerTap

        DispatchQueue.main.async {
            context.coordinator.configureInitialDisplayIfNeeded(scrollView)
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
        context.coordinator.blocksPageGestures = blocksPageGestures
        context.coordinator.onPageFingerTap = onPageFingerTap
        context.coordinator.canvasTapGesture?.isEnabled = onPageFingerTap != nil
        // IMPORTANT: never set `scrollView.isScrollEnabled = false` based
        // on `blocksPageGestures`. That flag also disables the scroll
        // view's built-in pinch / double-tap zoom recognizers, which is
        // the "can't zoom in after importing an image" bug. We suppress
        // only the horizontal page-swipe gesture (handled surgically in
        // `gestureRecognizerShouldBegin(_:)`) so the user can still
        // pinch-zoom freely with an overlay selected.

        if context.coordinator.contentStamp != contentStamp {
            context.coordinator.host?.rootView = content()
            context.coordinator.contentStamp = contentStamp
        }

        if context.coordinator.contentSize != contentSize {
            scrollView.zoomScale = 1.0
            context.coordinator.resetInitialFillZoom()
            context.coordinator.contentRoot?.frame = CGRect(origin: .zero, size: contentSize)
            context.coordinator.contentRoot?.hostingView = context.coordinator.host?.view
            context.coordinator.host?.view.frame = context.coordinator.contentRoot?.bounds ?? CGRect(origin: .zero, size: contentSize)
            scrollView.contentSize = contentSize
            context.coordinator.contentSize = contentSize
            context.coordinator.host?.rootView = content()
            context.coordinator.contentStamp = contentStamp
            DispatchQueue.main.async {
                context.coordinator.configureInitialDisplayIfNeeded(scrollView)
            }
        } else {
            context.coordinator.updateZoomLimits(scrollView)
            context.coordinator.recenter(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var host: UIHostingController<Content>?
        weak var contentRoot: PinchPassthroughContentView?
        var contentSize: CGSize = .zero
        var contentStamp: Int = 0
        var maxZoom: CGFloat = 8.0
        var doubleTapZoomScale: CGFloat = 2.5
        var fitEntirePageScale: CGFloat = 1.0
        var onSwipeNext: (() -> Void)?
        var onSwipePrevious: (() -> Void)?
        var nextSwipeCreatesPage: Bool = false
        var atFirstPage: Bool = false
        var blocksPageGestures: Bool = false
        var onPageFingerTap: ((CGPoint?) -> Void)?
        weak var pagePanGesture: UIPanGestureRecognizer?
        weak var canvasTapGesture: UITapGestureRecognizer?
        private var isSlidingPage = false
        private var didFireBoundaryHaptic = false
        private var didConfigureInitialDisplay = false
        private var configuredLayoutBounds: CGSize = .zero
        private(set) var baselineZoomScale: CGFloat = 1.0
        private let minLayoutWidth: CGFloat = 200
        private let minLayoutHeight: CGFloat = 150

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentRoot ?? host?.view
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
            let bounds = scrollView.bounds.size
            if didConfigureInitialDisplay, configuredLayoutBounds.width > 0 {
                let widthGrowth = bounds.width / configuredLayoutBounds.width
                let heightGrowth = bounds.height / configuredLayoutBounds.height
                if widthGrowth > 1.12 || heightGrowth > 1.12 {
                    didConfigureInitialDisplay = false
                }
            }
            updateZoomLimits(scrollView)
            configureInitialDisplayIfNeeded(scrollView)
            recenter(scrollView)
        }

        @objc func handleCanvasFingerTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let onPageFingerTap,
                  let scrollView = gesture.view as? UIScrollView,
                  let hostView = host?.view else { return }

            let location = gesture.location(in: scrollView)
            let contentView = contentRoot ?? hostView
            let pageFrame = contentView.convert(contentView.bounds, to: scrollView)
            if !pageFrame.contains(location) {
                onPageFingerTap(nil)
                return
            }
            let local = scrollView.convert(location, to: contentView)
            onPageFingerTap(local)
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
                  let pageView = contentRoot ?? host?.view,
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
                    guard abs(translation.x) > 14,
                          abs(translation.x) > abs(translation.y) * 1.25 else { return }
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
                    displayedX = raw * 0.92
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
            // Only the horizontal page-swipe pan is suppressed while an
            // overlay is selected. Double-tap zoom (the other recognizer
            // delegated to this Coordinator) stays live; the scroll
            // view's built-in pinch is unaffected because it isn't
            // delegated through here.
            if gestureRecognizer === pagePanGesture {
                if blocksPageGestures { return false }
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                      let scrollView = pan.view as? UIScrollView else {
                    return true
                }
                guard scrollView.zoomScale <= 1.08 else { return false }
                let velocity = pan.velocity(in: scrollView)
                return abs(velocity.x) > abs(velocity.y) * 1.35
            }
            return true
        }

        func updateZoomLimits(_ scrollView: UIScrollView) {
            guard contentSize.width > 0, contentSize.height > 0,
                  scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }

            let fitW = scrollView.bounds.width / contentSize.width
            let fitH = scrollView.bounds.height / contentSize.height
            fitEntirePageScale = min(fitW, fitH)

            let baseline = baselineZoomScale > 0 ? baselineZoomScale : 1.0
            scrollView.minimumZoomScale = baseline
            scrollView.maximumZoomScale = maxZoom

            if scrollView.zoomScale < baseline - 0.01, !scrollView.isZooming {
                scrollView.setZoomScale(baseline, animated: false)
            }
        }

        func snapToBaselineZoomIfNeeded(_ scrollView: UIScrollView) {
            let baseline = baselineZoomScale > 0 ? baselineZoomScale : 1.0
            guard scrollView.zoomScale < baseline - 0.008 else { return }
            scrollView.setZoomScale(baseline, animated: true)
        }

        func resetInitialFillZoom() {
            didConfigureInitialDisplay = false
            configuredLayoutBounds = .zero
            baselineZoomScale = 1.0
        }

        func configureInitialDisplayIfNeeded(_ scrollView: UIScrollView) {
            guard !didConfigureInitialDisplay,
                  contentSize.width > 0, contentSize.height > 0 else { return }
            let bounds = scrollView.bounds.size
            guard bounds.width >= minLayoutWidth, bounds.height >= minLayoutHeight else { return }

            scrollView.zoomScale = 1.0
            baselineZoomScale = 1.0
            didConfigureInitialDisplay = true
            configuredLayoutBounds = bounds

            updateZoomLimits(scrollView)
            applyCanvasResolution(for: 1.0)
            recenter(scrollView)
            scrollView.setContentOffset(
                CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top),
                animated: false
            )
        }

        func recenter(_ scrollView: UIScrollView) {
            guard let view = contentRoot ?? host?.view else { return }
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
            guard let pageView = contentRoot ?? host?.view else { return }
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

/// Host wrapper for the SwiftUI page card. Yields finger / multi-touch
/// sequences to the outer `UIScrollView` so pinch-to-zoom is never
/// swallowed by the `UIHostingController` subtree, and passes through
/// taps on visually empty regions of the page card.
final class PinchPassthroughContentView: UIView {
    /// The `UIHostingController` root — when every SwiftUI child is
    /// non-interactive (normal canvas mode), UIKit still returns this
    /// view from `hitTest`, which prevents the scroll view's pinch
    /// recognizer from tracking both fingers. We yield to the scroll
    /// view instead.
    weak var hostingView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self { return nil }

        // When every SwiftUI child is non-interactive, UIKit returns the
        // hosting root. Yield finger touches to the scroll view for pinch,
        // but still route Apple Pencil to the canvas beneath.
        if hit === hostingView, let hostingView {
            if let canvas = findCanvas(in: hostingView) {
                let local = convert(point, to: canvas)
                if let canvasHit = canvas.hitTest(local, with: event) {
                    return canvasHit
                }
            }
            return nil
        }
        return hit
    }

    private func findCanvas(in view: UIView) -> FingerPassThroughPKCanvasView? {
        if let canvas = view as? FingerPassThroughPKCanvasView { return canvas }
        for sub in view.subviews {
            if let canvas = findCanvas(in: sub) { return canvas }
        }
        return nil
    }
}
