//
//  ZoomablePageScrollView.swift
//  Noteworks
//
//  Zoom + pan host for the note page.
//
//  Architecture (rewritten to fix vector-content blur at zoom > 1):
//
//  The previous design parked the page card in a `UIHostingController`
//  and let `UIScrollView.zoomScale` apply a `CATransform3D` scale to it
//  during pinch. UIKit does NOT re-render content under a transform —
//  it just stretches the backing bitmap. PencilKit ink and SwiftUI
//  `Canvas`-drawn backgrounds are vector / procedural, so they have
//  no headroom and went visibly blurry at any zoom > 1.
//
//  The new design treats zoom as a content-size change instead of a
//  transform. The scroll view's own zoom is disabled
//  (`maximumZoomScale == minimumZoomScale == 1`). Our own pinch gesture
//  drives an internal `currentZoom` state; on each pinch update we:
//    1. Recompute the page's logical size = baseSize * currentZoom.
//    2. Resize the host view and `scrollView.contentSize` accordingly.
//    3. Publish the new logical size through a `Binding<CGFloat>`
//       (`zoom`) so `NoteEditorView` rebuilds its `pageCard` with the
//       scaled `logicalPageSize`. SwiftUI in turn lays out
//       `PencilCanvasView` and `BackgroundPatternUIView` at the real,
//       native pixel size — PencilKit renders strokes into a layer
//       that is genuinely 4x bigger, and the pattern view's `draw(_:)`
//       runs at the new size — so both stay vector-crisp at every
//       zoom level.
//
//  Pan, page-swipe, double-tap, and overlay-tap behaviour are
//  preserved 1:1. The scroll view still owns pan (works for free at
//  any contentSize). The page-swipe pan only fires when `currentZoom`
//  is at baseline. The single-finger tap callback still reports
//  normalised page coordinates (its math just divides out the zoom).
//

import SwiftUI
import UIKit
import PencilKit

/// Phase signal for `ZoomablePageScrollView.onOverlayManipulation`.
enum OverlayManipulationPhase {
    case began
    case changed
    case ended
    case cancelled
}

struct ZoomablePageScrollView<Content: View>: UIViewRepresentable {

    /// Size of the page card at zoom 1 (i.e. the size SwiftUI computes
    /// from the available viewport, before any pinch zoom is applied).
    let baseContentSize: CGSize
    var maxZoom: CGFloat = 8.0
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
    /// the page card; a `CGPoint` means **base-coordinate** page
    /// position (i.e. divided by the current zoom). The caller can use
    /// it directly against the unzoomed `pageSize`.
    var onPageFingerTap: ((CGPoint?) -> Void)? = nil
    /// Single-finger pan driver used while an overlay is selected, fired
    /// in BASE (unzoomed) page coordinates. The caller (NoteEditorView)
    /// resolves which overlay the touch started on (body vs. corner
    /// handle) and applies the delta to the overlay's normalized rect.
    /// Wired to a UIKit `UIPanGestureRecognizer` because SwiftUI
    /// gestures attached inside a `UIHostingController` hosted in a
    /// `UIScrollView` consistently lose the gesture race against the
    /// scroll view's pan — even with that pan disabled — which is what
    /// caused the "page pans instead of sticker moves" bug.
    ///
    /// Only enabled while `blocksPageGestures` is true (i.e. when the
    /// caller has marked an overlay as selected / editing / dragging).
    var onOverlayManipulation: ((OverlayManipulationPhase, CGPoint, CGSize) -> Void)? = nil
    /// Base-coordinate rects where the overlay pan must not begin (e.g.
    /// the floating image adjust toolbar) so toolbar buttons receive taps.
    var overlayInteractionExclusionRects: [CGRect] = []
    /// Base-coordinate rect of the image adjust toolbar while selected.
    /// A dedicated `UITapGestureRecognizer` hit-tests this region and
    /// fires `onOverlayAdjustToolbarTap` — SwiftUI `Button`s on the
    /// toolbar never receive touches because `PencilCanvasView` sits
    /// above the overlay layer in the page ZStack.
    var overlayAdjustToolbarRect: CGRect? = nil
    var onOverlayAdjustToolbarTap: ((ImageOverlayAdjustToolbarButton) -> Void)? = nil
    /// Reports the current zoom factor (1.0 = fit). The caller multiplies
    /// the logical page size by this to drive its SwiftUI layout.
    @Binding var zoom: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        baseContentSize: CGSize,
        maxZoom: CGFloat = 8.0,
        doubleTapZoomScale: CGFloat = 2.5,
        nextSwipeCreatesPage: Bool = false,
        atFirstPage: Bool = false,
        blocksPageGestures: Bool = false,
        contentStamp: Int = 0,
        onSwipeNext: (() -> Void)? = nil,
        onSwipePrevious: (() -> Void)? = nil,
        onPageFingerTap: ((CGPoint?) -> Void)? = nil,
        onOverlayManipulation: ((OverlayManipulationPhase, CGPoint, CGSize) -> Void)? = nil,
        overlayInteractionExclusionRects: [CGRect] = [],
        overlayAdjustToolbarRect: CGRect? = nil,
        onOverlayAdjustToolbarTap: ((ImageOverlayAdjustToolbarButton) -> Void)? = nil,
        zoom: Binding<CGFloat>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.baseContentSize = baseContentSize
        self.maxZoom = maxZoom
        self.doubleTapZoomScale = doubleTapZoomScale
        self.nextSwipeCreatesPage = nextSwipeCreatesPage
        self.atFirstPage = atFirstPage
        self.blocksPageGestures = blocksPageGestures
        self.contentStamp = contentStamp
        self.onSwipeNext = onSwipeNext
        self.onSwipePrevious = onSwipePrevious
        self.onPageFingerTap = onPageFingerTap
        self.onOverlayManipulation = onOverlayManipulation
        self.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        self.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        self.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
        self._zoom = zoom
        self.content = content
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        // Built-in zoom is disabled — we drive zoom ourselves via a
        // custom pinch recognizer that resizes the content view.
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.bouncesZoom = false
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
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = false
        scrollView.isMultipleTouchEnabled = true
        scrollView.isScrollEnabled = true

        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 1
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]

        // Our own pinch recognizer — drives content-size zoom instead
        // of CATransform3D scale.
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = context.coordinator
        scrollView.addGestureRecognizer(pinch)

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

        let toolbarTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleOverlayAdjustToolbarTap(_:))
        )
        toolbarTap.numberOfTapsRequired = 1
        toolbarTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        toolbarTap.cancelsTouchesInView = false
        toolbarTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(toolbarTap)
        toolbarTap.require(toFail: doubleTap)
        canvasTap.require(toFail: toolbarTap)

        // Drives image / text / shape sticker manipulation (move +
        // corner-handle resize). Only ever recognizes when an overlay
        // is selected (gated by `blocksPageGestures` in
        // `gestureRecognizerShouldBegin`). Reports pan deltas in BASE
        // (unzoomed) page coordinates back through
        // `onOverlayManipulation` so the caller can update the
        // overlay's normalized rect. Lives at the scroll-view level
        // (rather than as a SwiftUI gesture on the overlay body)
        // because SwiftUI gestures lost the gesture race against the
        // scroll view's own pan recognizer, leaving stickers
        // unmovable.
        let overlayPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleOverlayPan(_:))
        )
        overlayPan.minimumNumberOfTouches = 1
        overlayPan.maximumNumberOfTouches = 1
        overlayPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        overlayPan.cancelsTouchesInView = false
        overlayPan.delegate = context.coordinator
        scrollView.addGestureRecognizer(overlayPan)
        // When the overlay pan begins, the scroll view's pan + the
        // page-swipe pan must defer so the overlay drag is the only
        // recognizer driving the motion.
        scrollView.panGestureRecognizer.require(toFail: overlayPan)
        pagePan.require(toFail: overlayPan)
        canvasTap.require(toFail: overlayPan)

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.isMultipleTouchEnabled = true

        let contentRoot = PinchPassthroughContentView(frame: CGRect(origin: .zero, size: baseContentSize))
        contentRoot.isMultipleTouchEnabled = true
        contentRoot.hostingView = host.view
        contentRoot.addSubview(host.view)
        host.view.frame = contentRoot.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(contentRoot)
        scrollView.contentSize = baseContentSize

        context.coordinator.host = host
        context.coordinator.contentRoot = contentRoot
        context.coordinator.contentStamp = contentStamp
        context.coordinator.maxZoom = maxZoom
        context.coordinator.doubleTapZoomScale = doubleTapZoomScale
        context.coordinator.baseContentSize = baseContentSize
        context.coordinator.currentZoom = max(1, zoom)
        context.coordinator.onSwipeNext = onSwipeNext
        context.coordinator.onSwipePrevious = onSwipePrevious
        context.coordinator.nextSwipeCreatesPage = nextSwipeCreatesPage
        context.coordinator.atFirstPage = atFirstPage
        context.coordinator.pagePanGesture = pagePan
        context.coordinator.pinchGesture = pinch
        context.coordinator.canvasTapGesture = canvasTap
        context.coordinator.overlayPanGesture = overlayPan
        context.coordinator.toolbarTapGesture = toolbarTap
        context.coordinator.blocksPageGestures = blocksPageGestures
        context.coordinator.onPageFingerTap = onPageFingerTap
        context.coordinator.onOverlayManipulation = onOverlayManipulation
        context.coordinator.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        context.coordinator.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        context.coordinator.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
        context.coordinator.zoomBinding = $zoom

        DispatchQueue.main.async {
            context.coordinator.configureInitialDisplayIfNeeded(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.maxZoom = maxZoom
        context.coordinator.doubleTapZoomScale = doubleTapZoomScale
        context.coordinator.onSwipeNext = onSwipeNext
        context.coordinator.onSwipePrevious = onSwipePrevious
        context.coordinator.nextSwipeCreatesPage = nextSwipeCreatesPage
        context.coordinator.atFirstPage = atFirstPage
        context.coordinator.blocksPageGestures = blocksPageGestures
        context.coordinator.onPageFingerTap = onPageFingerTap
        context.coordinator.canvasTapGesture?.isEnabled = onPageFingerTap != nil
        context.coordinator.onOverlayManipulation = onOverlayManipulation
        context.coordinator.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        context.coordinator.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        context.coordinator.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
        context.coordinator.toolbarTapGesture?.isEnabled = onOverlayAdjustToolbarTap != nil
        context.coordinator.zoomBinding = $zoom

        // Suppress the scroll view's built-in single-finger pan while
        // an overlay (image / text / shape sticker) is selected or
        // being dragged. Without this, the scroll-pan recognizer
        // wins the gesture race against the SwiftUI drag gesture on
        // the overlay body — the user sees the page pan instead of
        // the sticker moving, even though the hit-test lands cleanly
        // on the overlay. Pinch lives on a separate recognizer and
        // stays enabled so two-finger zoom continues to work with a
        // sticker selected.
        let scrollPanEnabled = !blocksPageGestures
        if scrollView.panGestureRecognizer.isEnabled != scrollPanEnabled {
            scrollView.panGestureRecognizer.isEnabled = scrollPanEnabled
        }

        // Always push the fresh rootView — SwiftUI's hosting controller
        // diffs internally, so this is cheap, and it ensures zoom-driven
        // size changes in the caller (e.g. `pageCard(logicalPageSize:
        // base * zoom)`) actually propagate. The earlier stamp-gated
        // path missed zoom updates because zoom isn't part of
        // `contentStamp`.
        context.coordinator.host?.rootView = content()
        context.coordinator.contentStamp = contentStamp

        // If the caller drove the zoom binding from outside our pinch
        // recognizer (e.g. resetting to 1.0 on page change), pick it
        // up and re-apply the content-size update.
        if abs(context.coordinator.currentZoom - zoom) > 0.0005 {
            context.coordinator.currentZoom = max(1, min(maxZoom, zoom))
        }

        context.coordinator.isApplyingFromSwiftUI = true
        defer { context.coordinator.isApplyingFromSwiftUI = false }

        if context.coordinator.baseContentSize != baseContentSize {
            context.coordinator.baseContentSize = baseContentSize
            context.coordinator.resetInitialFillZoom()
            context.coordinator.applyZoom(to: scrollView, animated: false)
            DispatchQueue.main.async {
                context.coordinator.configureInitialDisplayIfNeeded(scrollView)
            }
        } else if !context.coordinator.isPinching {
            // Skip layout work mid-pinch — the live `CGAffineTransform`
            // on `contentRoot` is handling the visual scale, and any
            // `recenter` call here would reset the content insets in
            // response to the transformed view's bounding box, which
            // makes the page jitter under the user's fingers.
            context.coordinator.applyZoom(to: scrollView, animated: false)
            context.coordinator.recenter(scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var host: UIHostingController<Content>?
        weak var contentRoot: PinchPassthroughContentView?
        /// Base (zoom == 1) size of the page card. The on-screen size is
        /// `baseContentSize * currentZoom`.
        var baseContentSize: CGSize = .zero
        var contentStamp: Int = 0
        var maxZoom: CGFloat = 8.0
        var doubleTapZoomScale: CGFloat = 2.5
        var currentZoom: CGFloat = 1.0
        var onSwipeNext: (() -> Void)?
        var onSwipePrevious: (() -> Void)?
        var nextSwipeCreatesPage: Bool = false
        var atFirstPage: Bool = false
        var blocksPageGestures: Bool = false
        var onPageFingerTap: ((CGPoint?) -> Void)?
        var onOverlayManipulation: ((OverlayManipulationPhase, CGPoint, CGSize) -> Void)?
        var overlayInteractionExclusionRects: [CGRect] = []
        var overlayAdjustToolbarRect: CGRect?
        var onOverlayAdjustToolbarTap: ((ImageOverlayAdjustToolbarButton) -> Void)?
        var zoomBinding: Binding<CGFloat>?
        weak var pagePanGesture: UIPanGestureRecognizer?
        weak var pinchGesture: UIPinchGestureRecognizer?
        weak var canvasTapGesture: UITapGestureRecognizer?
        weak var toolbarTapGesture: UITapGestureRecognizer?
        weak var overlayPanGesture: UIPanGestureRecognizer?
        /// Captured at `.began` so `.changed` / `.ended` can report
        /// translations in BASE (unzoomed) page coordinates regardless
        /// of any zoom change mid-drag (which shouldn't happen, but is
        /// defensive).
        private var overlayPanStartLocationInContent: CGPoint = .zero
        private var overlayPanStartZoom: CGFloat = 1.0
        private var isSlidingPage = false
        private var didFireBoundaryHaptic = false
        private var didConfigureInitialDisplay = false
        private var configuredLayoutBounds: CGSize = .zero
        private let minLayoutWidth: CGFloat = 200
        private let minLayoutHeight: CGFloat = 150
        /// Zoom captured at pinch `.began` so we can compute the new
        /// zoom as `pinchStartZoom * gesture.scale` (rather than
        /// accumulating per-frame deltas, which drifts).
        private var pinchStartZoom: CGFloat = 1.0
        /// The content-coordinate point under the two-finger focal at
        /// `.began`. Pinned under the live focal location on every
        /// `.changed` frame so the page tracks the user's fingers.
        private var pinchAnchorInContent: CGPoint = .zero
        /// True while a pinch is in progress (.began through .ended).
        /// `updateUIView` consults this so it doesn't re-run layout in
        /// the middle of a pinch — the live `CGAffineTransform` on
        /// `contentRoot` is doing the visual work, and any layout
        /// reset would jitter the page under the user's fingers.
        fileprivate var isPinching: Bool = false
        /// Focal location in scrollView coordinates at `.began`, used
        /// as the anchor point for the live-pinch `CGAffineTransform`
        /// so the page appears to scale from the pinch focus point
        /// rather than from the origin.
        private var pinchFocalInScroll: CGPoint = .zero
        /// Most-recent focal location during `.changed`. We can't
        /// just call `gesture.location(in:)` again at `.ended`: the
        /// gesture's `.ended` event fires the moment one of the two
        /// touches lifts, and `location(in:)` then returns the
        /// midpoint of whichever touches the recognizer still
        /// considers active — which has visibly moved from the
        /// two-finger midpoint the user was looking at the instant
        /// before. Re-anchoring against that stale post-lift
        /// midpoint pulls the page systematically toward the screen
        /// centre on every release.
        private var lastFocalInScroll: CGPoint = .zero
        /// Live zoom factor applied as a `CGAffineTransform` during a
        /// pinch in progress. When the gesture ends we collapse this
        /// transform into a real content-size resize (`applyZoom`),
        /// which is what makes vector content (ink, pattern) sharp at
        /// the new zoom. During the gesture the transform causes some
        /// short-lived bitmap stretching, which is the right tradeoff:
        /// reassigning `PKCanvasView.drawing` 60×/sec mid-pinch makes
        /// PencilKit re-rasterise from scratch every frame and produces
        /// the bad "strokes flicker / lag behind" effect the user is
        /// reporting.
        private var liveZoomScale: CGFloat = 1.0

        // MARK: Layout

        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            // While we're mid-pinch (or just landed from one), the
            // pinch handler is the sole authority on
            // contentInset/contentOffset. Letting `recenter` run
            // re-asserts a centered inset, which makes UIScrollView
            // silently clamp the offset we just set, and the page
            // visibly snaps away from where the user's fingers left
            // it. The recenter logic is still invoked explicitly
            // from `applyZoom`, so we don't lose it — we just stop
            // running it on every layout pass during the transition.
            if isPinching { return }

            let bounds = scrollView.bounds.size
            if didConfigureInitialDisplay, configuredLayoutBounds.width > 0 {
                let widthGrowth = bounds.width / configuredLayoutBounds.width
                let heightGrowth = bounds.height / configuredLayoutBounds.height
                if widthGrowth > 1.12 || heightGrowth > 1.12 {
                    didConfigureInitialDisplay = false
                }
            }
            configureInitialDisplayIfNeeded(scrollView)
            recenter(scrollView)
        }

        func configureInitialDisplayIfNeeded(_ scrollView: UIScrollView) {
            guard !didConfigureInitialDisplay,
                  baseContentSize.width > 0, baseContentSize.height > 0 else { return }
            let bounds = scrollView.bounds.size
            guard bounds.width >= minLayoutWidth, bounds.height >= minLayoutHeight else { return }

            didConfigureInitialDisplay = true
            configuredLayoutBounds = bounds
            currentZoom = 1
            applyZoom(to: scrollView, animated: false)
            if !isApplyingFromSwiftUI,
               let binding = zoomBinding,
               abs(binding.wrappedValue - 1) > 0.0005 {
                binding.wrappedValue = 1
            }
            recenter(scrollView)
            // Initial offset: place the page centred in the
            // viewport. The inset is now a generous neutral scroll
            // headroom (not a centering tool), so we have to do the
            // centering math explicitly here.
            let zoomedWidth = baseContentSize.width * currentZoom
            let zoomedHeight = baseContentSize.height * currentZoom
            let centeredX = (zoomedWidth - scrollView.bounds.width) * 0.5
            let centeredY = (zoomedHeight - scrollView.bounds.height) * 0.5
            scrollView.setContentOffset(
                CGPoint(x: centeredX, y: centeredY),
                animated: false
            )
        }

        func resetInitialFillZoom() {
            didConfigureInitialDisplay = false
            configuredLayoutBounds = .zero
            currentZoom = 1
            if !isApplyingFromSwiftUI,
               let binding = zoomBinding,
               abs(binding.wrappedValue - 1) > 0.0005 {
                binding.wrappedValue = 1
            }
        }

        /// Pushes `currentZoom` into the live `contentSize` + host frame.
        /// This is the heart of the architecture — by genuinely changing
        /// the page's size, SwiftUI rebuilds the page card at the new
        /// dimensions and PencilKit + the pattern UIView render at
        /// native resolution.
        ///
        /// Only mutates view frames when they actually differ from the
        /// target — re-assigning the same frames every `updateUIView`
        /// pass was tripping SwiftUI into reinstantiating leaf views
        /// (notably `ImageOverlayContent`, which lost its `@State image`
        /// every frame and never finished decoding).
        func applyZoom(to scrollView: UIScrollView, animated: Bool) {
            let scaled = CGSize(
                width: baseContentSize.width * currentZoom,
                height: baseContentSize.height * currentZoom
            )
            guard scaled.width > 0, scaled.height > 0 else { return }
            let currentFrame = contentRoot?.frame.size ?? .zero
            let needsResize = abs(currentFrame.width - scaled.width) > 0.5
                || abs(currentFrame.height - scaled.height) > 0.5
            let apply = {
                self.contentRoot?.frame = CGRect(origin: .zero, size: scaled)
                self.host?.view.frame = CGRect(origin: .zero, size: scaled)
                scrollView.contentSize = scaled
                self.recenter(scrollView)
            }
            if needsResize {
                if animated {
                    UIView.animate(
                        withDuration: 0.22,
                        delay: 0,
                        options: [.curveEaseInOut],
                        animations: apply
                    )
                } else {
                    apply()
                }
            }
            // Only publish the binding when it actually changed, and
            // never from inside `updateUIView` (which is signalled by
            // `isApplyingFromSwiftUI`) — pushing the same value back
            // mid-render would cause a runaway re-render loop.
            if !isApplyingFromSwiftUI,
               let binding = zoomBinding,
               abs(binding.wrappedValue - currentZoom) > 0.0005 {
                binding.wrappedValue = currentZoom
            }
        }
        /// Set to true while `updateUIView` is mid-flight so
        /// `applyZoom` knows not to write back to the binding.
        fileprivate var isApplyingFromSwiftUI = false

        func recenter(_ scrollView: UIScrollView) {
            // Previous implementation force-centered the page (via
            // huge symmetric insets) whenever the zoomed page was
            // smaller than the viewport. That collapsed the legal
            // contentOffset range to a single value, so the
            // post-pinch `setContentOffset` would silently get
            // clamped back to centre — the page visibly snapped
            // away from wherever the user's fingers had left it.
            //
            // Replace the forced-centering with a generous, neutral
            // inset that just lets the user scroll the page right
            // up to either viewport edge (keeping a small `keep`
            // strip on-screen so the page never goes completely
            // out of view). The user is the one who positions the
            // page; we don't second-guess them.
            let keep: CGFloat = 24
            let horizontal = max(scrollView.bounds.width - keep, 0)
            let vertical = max(scrollView.bounds.height - keep, 0)

            scrollView.contentInset = UIEdgeInsets(
                top: vertical,
                left: horizontal,
                bottom: vertical,
                right: horizontal
            )
        }

        // MARK: Pinch

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView,
                  let contentRoot else { return }
            switch gesture.state {
            case .began:
                isPinching = true
                pinchStartZoom = currentZoom
                pinchFocalInScroll = gesture.location(in: scrollView)
                lastFocalInScroll = pinchFocalInScroll
                pinchAnchorInContent = scrollView.convert(pinchFocalInScroll, to: contentRoot)
                liveZoomScale = 1.0
                // Disable scroll-view pan during pinch so a small finger
                // drift in the focal point doesn't fight our manual
                // offset adjustment.
                scrollView.panGestureRecognizer.isEnabled = false
                // Also disable the page-swipe pan during pinch.
                // Otherwise, when the user lifts one of their two
                // pinching fingers, the pan recognizer can latch onto
                // the remaining finger, fire its `handlePagePan` after
                // we've bumped `currentZoom` past the swipe threshold,
                // and call `resetPageSlide(animated: true)` — which
                // animates `contentRoot.transform` to identity over
                // 0.18s, dragging the page away from where the user's
                // fingers left it.
                pagePanGesture?.isEnabled = false
            case .changed:
                let proposedTotal = pinchStartZoom * gesture.scale
                let clampedTotal = min(maxZoom, max(1, proposedTotal))
                let live = clampedTotal / max(0.0001, pinchStartZoom)
                liveZoomScale = live
                // Cache the focal *while both fingers are still
                // down*. We'll re-anchor against this in `.ended`
                // rather than re-asking the gesture, which would
                // give us the post-lift (centre-biased) midpoint.
                lastFocalInScroll = gesture.location(in: scrollView)

                // Apply a transform around the focal anchor so the page
                // visually scales from where the fingers are. This is
                // O(1) per frame — no per-stroke re-rasterisation, so
                // PencilKit ink doesn't flicker. Final-quality crisp
                // rendering is committed in `.ended` by collapsing the
                // transform into a real content-size resize.
                applyLivePinchTransform(in: scrollView, contentRoot: contentRoot)
            case .ended, .cancelled, .failed:
                // Snapshot the world AS THE USER SAW IT just before we
                // started rewriting it. Everything from here on has
                // to be expressed relative to these snapshots — we
                // can't trust `scrollView.contentOffset` after
                // `applyZoom`, because the contentInset change inside
                // `recenter` causes UIScrollView to silently mutate
                // contentOffset to keep it in legal range, which
                // shifts our reference frame and produces a wrong
                // landing point.
                //
                // Use the focal we cached during the LAST `.changed`
                // event, not `gesture.location(in:)` queried now.
                // The latter sees the post-lift state of the touches
                // and reports a midpoint that has drifted toward
                // screen centre, which makes the re-anchor math
                // place the page systematically off-centre — i.e.
                // the page snaps toward the middle on every release.
                let focalAtEnd = lastFocalInScroll
                let offsetAtEnd = scrollView.contentOffset
                let startZoom = pinchStartZoom
                let anchorBeforeResize = pinchAnchorInContent
                let finalZoom = min(maxZoom, max(1, pinchStartZoom * liveZoomScale))

                // Where the finger lived in SCREEN space at release.
                // Screen-space derivation:
                //   screen(P, offset) = scrollView.frame.origin
                //                       + P            (content-space point)
                //                       - offset       (scrollView.contentOffset)
                // The `scrollView.frame.origin` term cancels out below
                // because the scrollView itself does not move, so we
                // can work in scrollView-bounds space directly:
                //   finger_screen_relative = focalAtEnd - offsetAtEnd
                let fingerScreenRelative = CGPoint(
                    x: focalAtEnd.x - offsetAtEnd.x,
                    y: focalAtEnd.y - offsetAtEnd.y
                )

                // Collapse the live transform into a real
                // content-size resize so PencilKit + the pattern view
                // re-rasterise at the new native dimensions.
                //
                // Everything below this point — the transform reset,
                // contentSize/contentInset update, AND the
                // re-anchored contentOffset — has to commit to
                // CoreAnimation as a single atomic transaction.
                // Otherwise the user sees a frame in between where
                // the page has been resized but the offset hasn't
                // been corrected yet, which is the snap they were
                // reporting. `CATransaction.setDisableActions(true)`
                // suppresses the implicit animation UIScrollView
                // would otherwise interpolate across that gap.
                let zoomRatio = finalZoom / max(0.0001, startZoom)
                let anchorInNewBounds = CGPoint(
                    x: anchorBeforeResize.x * zoomRatio,
                    y: anchorBeforeResize.y * zoomRatio
                )

                // Snapshot the live-transform rendering of the scroll
                // view (i.e. the page exactly as the user is looking
                // at it the instant before release) and place it as
                // a sibling of the scroll view. While the snapshot
                // hangs over the screen we can:
                //   - reset the live transform to identity,
                //   - resize contentRoot / contentSize / contentInset,
                //   - re-anchor contentOffset,
                //   - push the new zoom value down through the SwiftUI
                //     binding (which schedules `updateUIView` to
                //     re-rasterise PencilKit ink + the pattern view
                //     at the new native size on the next runloop)
                // …all hidden from the user. Once SwiftUI has
                // propagated the new zoom down to PencilKit and the
                // pattern view (next runloop tick or two), we
                // cross-fade the snapshot out. The cross-fade lands
                // on identical pixels (the page's visual size and
                // position are unchanged between snapshot and final
                // state) so the user sees no flash.
                //
                // The snapshot is parented to `scrollView.superview`
                // — NOT to the scroll view itself — so scrolling
                // beneath it doesn't drag the cover off-screen.
                let snapshot = scrollView.snapshotView(afterScreenUpdates: false)
                if let snapshot, let parent = scrollView.superview {
                    snapshot.frame = scrollView.frame
                    snapshot.isUserInteractionEnabled = false
                    parent.insertSubview(snapshot, aboveSubview: scrollView)
                }

                UIView.performWithoutAnimation {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)

                    contentRoot.transform = .identity
                    currentZoom = finalZoom
                    applyZoom(to: scrollView, animated: false)
                    liveZoomScale = 1.0
                    // Don't blindly re-enable the scroll-pan: while an
                    // overlay is selected the SwiftUI sticker-drag
                    // gesture needs to win, and `updateUIView` is the
                    // sole authority for that flag.
                    scrollView.panGestureRecognizer.isEnabled = !blocksPageGestures
                    pagePanGesture?.isEnabled = true

                    // Solve for the contentOffset that lands
                    // `anchorInNewBounds` (in content space) at the
                    // same SCREEN position the finger was at on
                    // release:
                    //   anchorInNewBounds - newOffset == fingerScreenRelative
                    //   newOffset = anchorInNewBounds - fingerScreenRelative
                    var offset = CGPoint(
                        x: anchorInNewBounds.x - fingerScreenRelative.x,
                        y: anchorInNewBounds.y - fingerScreenRelative.y
                    )
                    clampOffset(&offset, in: scrollView)
                    scrollView.setContentOffset(offset, animated: false)

                    CATransaction.commit()
                }

                // Keep `isPinching` true through any follow-up layout
                // passes that UIScrollView schedules synchronously
                // before yielding the runloop — they would otherwise
                // re-run `recenter` and re-clamp our offset. The next
                // runloop tick is safe: the layout has settled, and
                // SwiftUI will have rebuilt the page card at the new
                // logical size, so subsequent `recenter` calls produce
                // the same inset we just set.
                DispatchQueue.main.async { [weak self] in
                    self?.isPinching = false
                }

                // Remove the snapshot only after BOTH (a) one runloop
                // tick has elapsed and (b) one display refresh has
                // rendered the underlying view. By that point SwiftUI
                // has propagated the new zoom down to PencilKit and
                // the pattern view, so the underlying view shows the
                // same pixels as the snapshot. Double-async is a
                // cheap way to wait two runloop hops without relying
                // on `CADisplayLink`. We fade rather than yank so any
                // residual mismatch (e.g. PKCanvasView re-rasterising
                // its ink) is hidden by the cross-fade.
                if let snapshot {
                    DispatchQueue.main.async {
                        DispatchQueue.main.async {
                            UIView.animate(
                                withDuration: 0.08,
                                delay: 0,
                                options: [.curveEaseOut, .allowUserInteraction]
                            ) {
                                snapshot.alpha = 0
                            } completion: { _ in
                                snapshot.removeFromSuperview()
                            }
                        }
                    }
                }
            default:
                break
            }
        }

        /// During pinch `.changed`: apply a `CGAffineTransform` to the
        /// content root so the bounds-coord point under the user's
        /// fingers at `.began` stays glued to the user's current
        /// finger position throughout the gesture. The transform is
        /// **temporary** — collapsed into a real content-size resize
        /// on `.ended`.
        ///
        /// Math (default anchorPoint 0.5, 0.5):
        ///
        /// A point `q` in `contentRoot`'s bounds renders at screen
        /// position `center + T(q - center)` where `center` is the
        /// view's centre in bounds coords and `T` is the affine
        /// transform (`T.a == T.d == scale`, plus a translation `(tx,
        /// ty)`). For a fixed point `p` (the focal-content anchor) we
        /// want:
        ///
        ///     center + scale * (p - center) + (tx, ty) == focalNow - viewOrigin
        ///
        /// where `viewOrigin` is contentRoot's frame origin in
        /// scrollView coords AT THE START of the pinch. Solving:
        ///
        ///     (tx, ty) = (focalNow - viewOrigin) - center - scale * (p - center)
        ///
        /// Using a `CGAffineTransform(a:b:c:d:tx:ty)` directly avoids
        /// the order-of-operations subtlety with `translatedBy` /
        /// `scaledBy`, which compose into the view's pre-transform
        /// coordinate space and were producing the wrong focal point.
        private func applyLivePinchTransform(
            in scrollView: UIScrollView,
            contentRoot: UIView
        ) {
            let scale = liveZoomScale
            let focal = pinchAnchorInContent

            // contentRoot.bounds is the *un-transformed* bounds, which
            // is what bounds-coord points like `pinchAnchorInContent`
            // were captured in.
            let bounds = contentRoot.bounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)

            // Where the view's frame origin lives in scrollView coords
            // at the start of the pinch. Because the gesture pan is
            // disabled during pinch, scrollView.contentOffset doesn't
            // drift — but we still translate by it so the transform
            // works regardless of where the page sits on screen.
            let focalNow = pinchGesture?.location(in: scrollView) ?? pinchFocalInScroll
            // We want the focal point to track `focalNow` rather than
            // `pinchFocalInScroll`. The delta is just an extra screen
            // translation we add on top of the focal-preserving math.
            let dx = focalNow.x - pinchFocalInScroll.x
            let dy = focalNow.y - pinchFocalInScroll.y

            let tx = (1 - scale) * (focal.x - center.x) + dx
            let ty = (1 - scale) * (focal.y - center.y) + dy

            contentRoot.transform = CGAffineTransform(
                a: scale, b: 0,
                c: 0, d: scale,
                tx: tx, ty: ty
            )
        }

        private func clampOffset(_ offset: inout CGPoint, in scrollView: UIScrollView) {
            let minX = -scrollView.contentInset.left
            let minY = -scrollView.contentInset.top
            let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
            let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
            offset.x = max(minX, min(maxX, offset.x))
            offset.y = max(minY, min(maxY, offset.y))
        }

        // MARK: Overlay manipulation

        /// UIKit-driven single-finger pan that moves / resizes the
        /// currently-selected sticker. Reports start point AND running
        /// translation in BASE (unzoomed) page coordinates so the
        /// caller can hit-test against the overlay's normalized rect
        /// and apply the delta directly.
        @objc func handleOverlayPan(_ gesture: UIPanGestureRecognizer) {
            guard let onOverlayManipulation,
                  let scrollView = gesture.view as? UIScrollView,
                  let contentView = contentRoot ?? host?.view else { return }

            switch gesture.state {
            case .began:
                let startInScroll = gesture.location(in: scrollView)
                overlayPanStartLocationInContent = scrollView.convert(startInScroll, to: contentView)
                overlayPanStartZoom = max(0.0001, currentZoom)
                let baseStart = CGPoint(
                    x: overlayPanStartLocationInContent.x / overlayPanStartZoom,
                    y: overlayPanStartLocationInContent.y / overlayPanStartZoom
                )
                onOverlayManipulation(.began, baseStart, .zero)

            case .changed:
                let translationInScroll = gesture.translation(in: scrollView)
                let baseStart = CGPoint(
                    x: overlayPanStartLocationInContent.x / overlayPanStartZoom,
                    y: overlayPanStartLocationInContent.y / overlayPanStartZoom
                )
                let baseTranslation = CGSize(
                    width: translationInScroll.x / overlayPanStartZoom,
                    height: translationInScroll.y / overlayPanStartZoom
                )
                onOverlayManipulation(.changed, baseStart, baseTranslation)

            case .ended:
                let translationInScroll = gesture.translation(in: scrollView)
                let baseStart = CGPoint(
                    x: overlayPanStartLocationInContent.x / overlayPanStartZoom,
                    y: overlayPanStartLocationInContent.y / overlayPanStartZoom
                )
                let baseTranslation = CGSize(
                    width: translationInScroll.x / overlayPanStartZoom,
                    height: translationInScroll.y / overlayPanStartZoom
                )
                onOverlayManipulation(.ended, baseStart, baseTranslation)

            case .cancelled, .failed:
                onOverlayManipulation(.cancelled, .zero, .zero)

            default:
                break
            }
        }

        // MARK: Taps

        @objc func handleOverlayAdjustToolbarTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let onOverlayAdjustToolbarTap,
                  let toolbarRect = overlayAdjustToolbarRect,
                  let scrollView = gesture.view as? UIScrollView,
                  let contentView = contentRoot ?? host?.view else { return }

            let location = gesture.location(in: scrollView)
            let localScaled = scrollView.convert(location, to: contentView)
            let zoom = max(0.0001, currentZoom)
            let localBase = CGPoint(
                x: localScaled.x / zoom,
                y: localScaled.y / zoom
            )
            guard let button = ImageOverlayAdjustToolbarMetrics.button(at: localBase, in: toolbarRect) else {
                return
            }
            onOverlayAdjustToolbarTap(button)
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
            let localScaled = scrollView.convert(location, to: contentView)
            // Map back to base coordinates so the caller's hit-test
            // math against `pageSize` (which is the *unzoomed* logical
            // size) lines up.
            let local = CGPoint(
                x: localScaled.x / currentZoom,
                y: localScaled.y / currentZoom
            )
            onPageFingerTap(local)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let tapLocationInScroll = gesture.location(in: scrollView)
            let isZoomedIn = currentZoom > 1.12
            let targetZoom: CGFloat
            if isZoomedIn {
                targetZoom = 1
            } else {
                targetZoom = min(doubleTapZoomScale, maxZoom)
            }

            // Capture the content point under the tap BEFORE resizing.
            let previousZoom = currentZoom
            let anchorInContent: CGPoint
            if let contentRoot {
                anchorInContent = scrollView.convert(tapLocationInScroll, to: contentRoot)
            } else {
                anchorInContent = .zero
            }

            currentZoom = targetZoom
            applyZoom(to: scrollView, animated: true)

            // After the content size has been updated (immediate, even
            // when frames animate via the easeInOut wrapper), shift
            // the offset so the tapped content point lands under the
            // tap's scroll-coord location.
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView, let contentRoot = self.contentRoot else { return }
                let zoomRatio = self.currentZoom / max(0.0001, previousZoom)
                let scaledAnchorInContent = CGPoint(
                    x: anchorInContent.x * zoomRatio,
                    y: anchorInContent.y * zoomRatio
                )
                let anchorInScroll = contentRoot.convert(scaledAnchorInContent, to: scrollView)
                let dx = anchorInScroll.x - tapLocationInScroll.x
                let dy = anchorInScroll.y - tapLocationInScroll.y
                var offset = scrollView.contentOffset
                offset.x += dx
                offset.y += dy
                let minX = -scrollView.contentInset.left
                let minY = -scrollView.contentInset.top
                let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
                let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
                offset.x = max(minX, min(maxX, offset.x))
                offset.y = max(minY, min(maxY, offset.y))
                scrollView.setContentOffset(offset, animated: true)
            }
        }

        // MARK: Page swipe (only at fit zoom)

        @objc func handlePagePan(_ sender: UIPanGestureRecognizer) {
            guard let scrollView = sender.view as? UIScrollView,
                  let pageView = contentRoot ?? host?.view,
                  currentZoom <= 1.08 else {
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
                    let offscreen = (shouldGoNext ? -1 : 1) * max(width, baseContentSize.width)
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

        private func resetPageSlide(animated: Bool) {
            guard let pageView = contentRoot ?? host?.view else { return }
            // A no-op transform reset still pushes an implicit CALayer
            // animation; if it happens to overlap with a pinch's
            // transform write, the live pinch reads stale interpolated
            // values and the page visibly jitters. Skip when the
            // transform is already identity.
            if pageView.transform.isIdentity { return }
            let changes = { pageView.transform = .identity }
            if animated {
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: changes)
            } else {
                changes()
            }
        }

        // MARK: Gesture delegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === toolbarTapGesture {
                guard let toolbarRect = overlayAdjustToolbarRect,
                      let tap = gestureRecognizer as? UITapGestureRecognizer,
                      let scrollView = tap.view as? UIScrollView,
                      let contentView = contentRoot ?? host?.view else {
                    return false
                }
                let location = tap.location(in: scrollView)
                let localScaled = scrollView.convert(location, to: contentView)
                let zoom = max(0.0001, currentZoom)
                let localBase = CGPoint(
                    x: localScaled.x / zoom,
                    y: localScaled.y / zoom
                )
                return toolbarRect.contains(localBase)
            }
            if gestureRecognizer === overlayPanGesture {
                // Only meaningful while an overlay is selected
                // (`blocksPageGestures == true` is set in
                // `NoteEditorView` exactly when there's a sticker
                // selected / being edited / mid-drag) and only when
                // the touch lands on the page card itself (not the
                // grey margin around it).
                guard blocksPageGestures,
                      let pan = gestureRecognizer as? UIPanGestureRecognizer,
                      let scrollView = pan.view as? UIScrollView,
                      let contentView = contentRoot ?? host?.view else {
                    return false
                }
                let location = pan.location(in: scrollView)
                let pageFrame = contentView.convert(contentView.bounds, to: scrollView)
                guard pageFrame.contains(location) else { return false }
                let localScaled = scrollView.convert(location, to: contentView)
                let zoom = max(0.0001, currentZoom)
                let localBase = CGPoint(
                    x: localScaled.x / zoom,
                    y: localScaled.y / zoom
                )
                for rect in overlayInteractionExclusionRects where rect.contains(localBase) {
                    return false
                }
                return true
            }
            if gestureRecognizer === pagePanGesture {
                if blocksPageGestures { return false }
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                      let scrollView = pan.view as? UIScrollView else {
                    return true
                }
                guard currentZoom <= 1.08 else { return false }
                let velocity = pan.velocity(in: scrollView)
                return abs(velocity.x) > abs(velocity.y) * 1.35
            }
            return true
        }
    }
}

/// Host wrapper for the SwiftUI page card.
///
/// Touch routing is a 3-way split, decided per `hitTest`:
///   1. PKCanvasView wants the touch (Pencil ink, eraser etc.) → return
///      that canvas hit so PencilKit gets it.
///   2. Multi-touch is in flight → return nil so the outer
///      `UIScrollView`'s pinch recognizer can grab both fingers
///      (PencilKit's canvas is non-pinchable, and the hosting view
///      doesn't yield multi-touch sequences cleanly).
///   3. Single-finger touch on an "empty" area of the SwiftUI tree
///      (where `super.hitTest` returns the hosting view itself) →
///      return the hosting view. SwiftUI attaches its gesture
///      recognizers to that root, so returning it is what lets
///      overlay drag / tap gestures (move + resize the image / text
///      stickers) actually fire. Returning `nil` here — the previous
///      behaviour — silently ate every single-finger gesture on the
///      overlay layer, which is why images couldn't be moved.
final class PinchPassthroughContentView: UIView {
    weak var hostingView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self { return nil }

        if hit === hostingView, let hostingView {
            if let canvas = findCanvas(in: hostingView) {
                let local = convert(point, to: canvas)
                if let canvasHit = canvas.hitTest(local, with: event) {
                    return canvasHit
                }
            }
            // Multi-touch (pinch) → yield to the scroll view so its
            // pinch recognizer can track both fingers. Single touch →
            // hand the hit back to the hosting view so SwiftUI's
            // overlay-drag / tap gestures can recognize it.
            let touchCount = event?.allTouches?.count ?? 0
            if touchCount >= 2 { return nil }
            return hostingView
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
