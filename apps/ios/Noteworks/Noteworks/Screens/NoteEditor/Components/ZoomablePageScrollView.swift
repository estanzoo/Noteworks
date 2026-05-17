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
    /// When `true`, a "next" swipe would create a brand-new page rather
    /// than just navigate to an existing one. We use this signal to add
    /// a progressive rubber-band feel during the drag, raise the commit
    /// distance, and fire a subtle haptic when the finger enters the
    /// "create" zone — so the user can _feel_ the difference between
    /// navigating between existing pages and creating one.
    var nextSwipeCreatesPage: Bool = false
    /// When `true`, the user is on page 1 and a "previous" swipe can't
    /// go anywhere. The drag rubber-bands at the boundary and the
    /// callback still fires once enough commitment is shown so the
    /// caller can surface a status notification.
    var atFirstPage: Bool = false
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
        context.coordinator.nextSwipeCreatesPage = nextSwipeCreatesPage
        context.coordinator.atFirstPage = atFirstPage
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
        context.coordinator.nextSwipeCreatesPage = nextSwipeCreatesPage
        context.coordinator.atFirstPage = atFirstPage
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
        var nextSwipeCreatesPage: Bool = false
        var atFirstPage: Bool = false
        weak var pagePanGesture: UIPanGestureRecognizer?
        private var isSlidingPage = false
        /// One-shot guard so we don't buzz on every frame the finger sits
        /// past the "create page" cue threshold — fires once per gesture
        /// when entering the zone, resets when the gesture ends or the
        /// finger pulls back below the threshold.
        private var didFireBoundaryHaptic = false

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
                // "Resistance zones": the swipe would either create a new
                // page (next-direction past the last page) or rubber-band
                // at the first-page boundary. In both cases we want the
                // page to lag behind the finger so the user feels the
                // boundary instead of breezing through it.
                let creatingNewPage = isNextSwipe && nextSwipeCreatesPage
                let atPrevBoundary = isPrevSwipe && atFirstPage
                let displayedX: CGFloat
                if creatingNewPage || atPrevBoundary {
                    displayedX = Coordinator.rubberBand(raw, dimension: width)
                    // Light haptic the first time the finger crosses
                    // into the "create page" cue zone — small, intentional
                    // nudge so the user feels they're past the edge of
                    // existing pages, not a navigation tap.
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

                // Inside the resistance zone we require noticeably more
                // commitment before committing — both a longer raw drag
                // and a higher flick velocity. That makes the boundary
                // _feel_ like a boundary instead of just being slightly
                // stickier than usual.
                let normalDistance = max(70, width * 0.18)
                let resistDistance = max(140, width * 0.34)
                let distanceThreshold = inResistanceZone ? resistDistance : normalDistance
                let velocityThreshold: CGFloat = inResistanceZone ? 1050 : 650

                // Match GoodNotes / Notability: swipe left → next page (page exits left);
                // swipe right → previous page (page exits right).
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

        /// Apple's standard rubber-band curve: small offsets pass through
        /// almost linearly, large offsets are aggressively damped. Output
        /// asymptotes at `dimension` so a full-screen finger drag still
        /// only moves the page ~35 % of the way.
        ///
        ///     f(x) = sign(x) · d · (1 − 1 / (c · |x| / d + 1))
        ///
        /// `c = 0.55` matches `UIScrollView`'s default bounce feel.
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
