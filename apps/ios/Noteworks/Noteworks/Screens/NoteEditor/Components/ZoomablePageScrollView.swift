//
//  ZoomablePageScrollView.swift
//  Noteworks
//
//  Zoom + pan host for the note page.
//
//  Architecture — pure native UIScrollView zoom (image-style):
//
//  The page (background + PencilKit ink + overlays) is hosted at a single
//  fixed BASE size inside `contentRoot`, and zoom is applied entirely by
//  UIScrollView as a CATransform on `contentRoot`. We deliberately do NOT
//  collapse that transform into a frame resize, and we do NOT re-rasterize
//  PencilKit per zoom level. The whole page therefore scales as one
//  rasterised image — exactly like pinching a photo — so strokes never
//  flash, reposition, or regenerate while zooming.
//
//    - `viewForZooming` returns `contentRoot`; the system pinch recognizer
//      drives the live transform.
//    - `scrollViewDidZoom` keeps the page centered (via `contentInset`)
//      when it's smaller than the viewport, and mirrors `zoomScale` into
//      `currentZoom`.
//    - `scrollViewDidEndZooming` simply records the settled scale and
//      reports it through the binding (used only so the editor can command
//      a reset to fit on page change). The transform stays in place.
//
//  Trade-off: like a photo, content is raster-scaled above 1× (it softens
//  at high zoom) rather than re-rasterising vector-crisp.
//
//  Knobs:
//    - `bounces = false`, `alwaysBounceX/Y = false` → no pan rubber-band.
//    - `bouncesZoom = true` → pinch may briefly cross the zoom limits and
//      springs back (e.g. pinch in past fit → shrinks, then bounces back).
//    - `minimumZoomScale = 1` (fit), `maximumZoomScale = maxZoom`.
//    - `contentSize` is managed by UIScrollView (`base × zoomScale`), so
//      panning is enabled only once zoomed in past the viewport.
//
//  Other surfaces still served by this view:
//    - Page swipe (single-finger horizontal pan) via a dedicated
//      `UIPanGestureRecognizer`. Active at fit zoom, and when zoomed in
//      once the page is panned to the horizontal content edge.
//    - Double-tap to toggle between fit and `doubleTapZoomScale`.
//    - Two-finger double-tap → `onTwoFingerDoubleTap` (e.g. undo).
//    - Single-finger tap → `onPageFingerTap` (base coords).
//    - Overlay drag / resize via `UIPanGestureRecognizer` enabled
//      when `blocksPageGestures` is true.
//    - Image pinch-to-resize via `UIPinchGestureRecognizer` while
//      an image overlay is selected (page pinch waits to fail).
//    - Floating overlay-adjust toolbar tap (image select mode).
//

import SwiftUI
import UIKit
import PencilKit
import os

// MARK: - Pinch zoom debug (TestFlight / Console)

/// Set to `true` to emit `[PageZoom]` lines in Xcode / Console.app while
/// testing pinch. Filter on subsystem `com.noteworks.pagezoom`.
enum PageZoomDebug {
    static var isEnabled = true
    private static let log = Logger(subsystem: "com.noteworks.pagezoom", category: "pinch")

    static func zoom(_ message: String) {
        guard isEnabled else { return }
        log.info("\(message, privacy: .public)")
    }
}

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
    /// Two-finger double-tap on the canvas (finger only).
    var onTwoFingerDoubleTap: (() -> Void)? = nil
    /// Single-finger pan driver used while an overlay is selected, fired
    /// in BASE (unzoomed) page coordinates.
    var onOverlayManipulation: ((OverlayManipulationPhase, CGPoint, CGSize) -> Void)? = nil
    /// Base-coordinate rects where the overlay pan must not begin (e.g.
    /// the floating image adjust toolbar) so toolbar buttons receive taps.
    var overlayInteractionExclusionRects: [CGRect] = []
    /// Base-coordinate rect of the image adjust toolbar while selected.
    var overlayAdjustToolbarRect: CGRect? = nil
    var onOverlayAdjustToolbarTap: ((ImageOverlayAdjustToolbarButton) -> Void)? = nil
    /// When true, the overlay pan + toolbar tap recognizers also track
    /// Apple Pencil (image select — move / resize / tap toolbar buttons).
    var overlayPanAcceptsPencil: Bool = false
    /// Base-coordinate rect of the selected image overlay. When non-nil,
    /// a two-finger pinch starting on this rect resizes the image
    /// instead of zooming the page.
    var overlayPinchTargetRect: CGRect? = nil
    /// Pinch scale is relative to gesture start (1.0 at `.began`).
    var onOverlayPinchResize: ((OverlayManipulationPhase, CGFloat) -> Void)? = nil
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
        onTwoFingerDoubleTap: (() -> Void)? = nil,
        onOverlayManipulation: ((OverlayManipulationPhase, CGPoint, CGSize) -> Void)? = nil,
        overlayInteractionExclusionRects: [CGRect] = [],
        overlayAdjustToolbarRect: CGRect? = nil,
        onOverlayAdjustToolbarTap: ((ImageOverlayAdjustToolbarButton) -> Void)? = nil,
        overlayPanAcceptsPencil: Bool = false,
        overlayPinchTargetRect: CGRect? = nil,
        onOverlayPinchResize: ((OverlayManipulationPhase, CGFloat) -> Void)? = nil,
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
        self.onTwoFingerDoubleTap = onTwoFingerDoubleTap
        self.onOverlayManipulation = onOverlayManipulation
        self.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        self.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        self.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
        self.overlayPanAcceptsPencil = overlayPanAcceptsPencil
        self.overlayPinchTargetRect = overlayPinchTargetRect
        self.onOverlayPinchResize = onOverlayPinchResize
        self._zoom = zoom
        self.content = content
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maxZoom
        // Rubber-band the zoom: a pinch may briefly cross the min/max
        // zoom limits while fingers are down, then UIScrollView animates
        // back to the limit on release. Gives the "try to zoom out past
        // fit → it shrinks, then bounces back" feel. (`bounces` stays
        // false so panning at fit has no rubber-band.)
        scrollView.bouncesZoom = true
        scrollView.bounces = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .normal
        scrollView.backgroundColor = .clear
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = false
        scrollView.isMultipleTouchEnabled = true

        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 1
        scrollView.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]

        // Page-swipe pan (single finger horizontal at fit zoom).
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

        // Double-tap to zoom toggle.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        doubleTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(doubleTap)

        // Two-finger double-tap (e.g. undo).
        let twoFingerDoubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerDoubleTap(_:))
        )
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        twoFingerDoubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        twoFingerDoubleTap.cancelsTouchesInView = false
        twoFingerDoubleTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(twoFingerDoubleTap)

        // Single-finger tap → page coords callback.
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

        // Image-adjust toolbar tap.
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

        // Overlay (sticker) drag pan — only fires when blocksPageGestures.
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
        scrollView.panGestureRecognizer.require(toFail: overlayPan)
        pagePan.require(toFail: overlayPan)
        canvasTap.require(toFail: overlayPan)

        // Image pinch-to-resize — page pinch waits for this to fail so
        // pinching a selected image resizes it instead of zooming the page.
        let overlayPinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleOverlayPinch(_:))
        )
        overlayPinch.cancelsTouchesInView = false
        overlayPinch.delegate = context.coordinator
        scrollView.addGestureRecognizer(overlayPinch)
        scrollView.pinchGestureRecognizer?.require(toFail: overlayPinch)

        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.view.isMultipleTouchEnabled = true

        let contentRoot = PinchPassthroughContentView(
            frame: CGRect(origin: .zero, size: baseContentSize)
        )
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
        context.coordinator.canvasTapGesture = canvasTap
        context.coordinator.overlayPanGesture = overlayPan
        context.coordinator.overlayPinchGesture = overlayPinch
        context.coordinator.toolbarTapGesture = toolbarTap
        context.coordinator.twoFingerDoubleTapGesture = twoFingerDoubleTap
        context.coordinator.blocksPageGestures = blocksPageGestures
        context.coordinator.onPageFingerTap = onPageFingerTap
        context.coordinator.onTwoFingerDoubleTap = onTwoFingerDoubleTap
        context.coordinator.onOverlayManipulation = onOverlayManipulation
        context.coordinator.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        context.coordinator.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        context.coordinator.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
        context.coordinator.overlayPinchTargetRect = overlayPinchTargetRect
        context.coordinator.onOverlayPinchResize = onOverlayPinchResize
        context.coordinator.overlayPanAcceptsPencil = overlayPanAcceptsPencil
        context.coordinator.applyOverlayPanTouchTypes()
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
        context.coordinator.onTwoFingerDoubleTap = onTwoFingerDoubleTap
        context.coordinator.canvasTapGesture?.isEnabled = onPageFingerTap != nil
        context.coordinator.twoFingerDoubleTapGesture?.isEnabled = onTwoFingerDoubleTap != nil
        context.coordinator.onOverlayManipulation = onOverlayManipulation
        context.coordinator.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        context.coordinator.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        context.coordinator.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
        context.coordinator.overlayPinchTargetRect = overlayPinchTargetRect
        context.coordinator.onOverlayPinchResize = onOverlayPinchResize
        context.coordinator.overlayPanAcceptsPencil = overlayPanAcceptsPencil
        context.coordinator.applyOverlayPanTouchTypes()
        context.coordinator.toolbarTapGesture?.isEnabled = onOverlayAdjustToolbarTap != nil
        context.coordinator.overlayPinchGesture?.isEnabled = onOverlayPinchResize != nil
        context.coordinator.zoomBinding = $zoom

        let scrollPanEnabled = !blocksPageGestures
        if scrollView.panGestureRecognizer.isEnabled != scrollPanEnabled {
            scrollView.panGestureRecognizer.isEnabled = scrollPanEnabled
        }

        context.coordinator.host?.rootView = content()
        context.coordinator.contentStamp = contentStamp

        // If the caller drove the zoom binding from outside (e.g. reset
        // on page change), pick it up and re-apply the content-size.
        if abs(context.coordinator.currentZoom - zoom) > 0.0005 {
            context.coordinator.currentZoom = max(1, min(maxZoom, zoom))
        }

        context.coordinator.isApplyingFromSwiftUI = true
        defer { context.coordinator.isApplyingFromSwiftUI = false }

        let baseChanged = context.coordinator.baseContentSize != baseContentSize
        if baseChanged {
            context.coordinator.baseContentSize = baseContentSize
            // Rotation / page change: reset zoom to fit so the new page
            // dimensions don't leave a stale partial zoom that hides the
            // page off-screen and silently disables panning.
            context.coordinator.currentZoom = 1
        }

        if !context.coordinator.isZooming {
            context.coordinator.syncBaseLayout(scrollView)
            context.coordinator.centerContent(in: scrollView)
            if baseChanged {
                context.coordinator.recenterScrollOffset(scrollView)
                context.coordinator.publishZoomBinding(1)
                // Run again on the next runloop tick — scrollView.bounds
                // is often briefly stale during a rotation transition,
                // and the first pass uses pre-rotation bounds.
                DispatchQueue.main.async {
                    context.coordinator.syncBaseLayout(scrollView)
                    context.coordinator.centerContent(in: scrollView)
                    context.coordinator.recenterScrollOffset(scrollView)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var host: UIHostingController<Content>?
        weak var contentRoot: PinchPassthroughContentView?
        var baseContentSize: CGSize = .zero
        var contentStamp: Int = 0
        var maxZoom: CGFloat = 8.0
        var doubleTapZoomScale: CGFloat = 2.5
        /// Mirror of `scrollView.zoomScale` (the live native zoom). 1 = fit,
        /// up to `maxZoom`. Kept in sync from the scroll-view delegate so the
        /// swipe / double-tap gates and the published binding can read it.
        var currentZoom: CGFloat = 1.0
        var onSwipeNext: (() -> Void)?
        var onSwipePrevious: (() -> Void)?
        var nextSwipeCreatesPage: Bool = false
        var atFirstPage: Bool = false
        var blocksPageGestures: Bool = false
        var onPageFingerTap: ((CGPoint?) -> Void)?
        var onTwoFingerDoubleTap: (() -> Void)?
        var onOverlayManipulation: ((OverlayManipulationPhase, CGPoint, CGSize) -> Void)?
        var overlayInteractionExclusionRects: [CGRect] = []
        var overlayAdjustToolbarRect: CGRect?
        var onOverlayAdjustToolbarTap: ((ImageOverlayAdjustToolbarButton) -> Void)?
        var overlayPanAcceptsPencil: Bool = false
        var overlayPinchTargetRect: CGRect?
        var onOverlayPinchResize: ((OverlayManipulationPhase, CGFloat) -> Void)?
        var zoomBinding: Binding<CGFloat>?
        weak var pagePanGesture: UIPanGestureRecognizer?
        weak var canvasTapGesture: UITapGestureRecognizer?
        weak var toolbarTapGesture: UITapGestureRecognizer?
        weak var twoFingerDoubleTapGesture: UITapGestureRecognizer?
        weak var overlayPanGesture: UIPanGestureRecognizer?
        weak var overlayPinchGesture: UIPinchGestureRecognizer?
        fileprivate var isApplyingFromSwiftUI = false

        /// True between `scrollViewWillBeginZooming` and
        /// `scrollViewDidEndZooming`. Layout is left entirely to UIScrollView
        /// — zoom is a single live transform on `contentRoot`, never collapsed
        /// into a frame resize, so the page scales like a rasterised image and
        /// nothing re-renders.
        private(set) var isZooming: Bool = false
        // Page swipe state.
        private var isSlidingPage = false
        private var didFireBoundaryHaptic = false
        /// Zoom captured at the start of a page-swipe pan. Used to keep the
        /// page tracking the finger 1:1 even when zoomed in (the swipe lives
        /// inside the scaled `contentRoot`).
        private var slidePanZoom: CGFloat = 1.0

        // Overlay pan state.
        private var overlayPanStartLocationInContent: CGPoint = .zero
        private var overlayPanStartZoom: CGFloat = 1.0

        /// Finger + (optionally) pencil for sticker drag and toolbar taps.
        func applyOverlayPanTouchTypes() {
            let finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
            let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
            let types: [NSNumber] = overlayPanAcceptsPencil ? [finger, pencil] : [finger]
            overlayPanGesture?.allowedTouchTypes = types
            toolbarTapGesture?.allowedTouchTypes = types
        }

        // MARK: Layout / sizing

        /// Called once at view creation. Lays out the page at fit zoom.
        func configureInitialDisplayIfNeeded(_ scrollView: UIScrollView) {
            guard baseContentSize.width > 0, baseContentSize.height > 0 else { return }
            currentZoom = 1
            syncBaseLayout(scrollView)
            centerContent(in: scrollView)
            recenterScrollOffset(scrollView)
            publishZoomBinding(1)
        }

        /// Place `contentOffset` so the centered page sits dead center.
        func recenterScrollOffset(_ scrollView: UIScrollView) {
            let inset = scrollView.contentInset
            let bounds = scrollView.bounds.size
            let content = scrollView.contentSize
            var offset: CGPoint
            if content.width <= bounds.width && content.height <= bounds.height {
                // Page fits viewport → centering inset is symmetric →
                // offset of -inset puts page in dead middle.
                offset = CGPoint(x: -inset.left, y: -inset.top)
            } else {
                // Page bigger than viewport → middle of scrollable range.
                offset = CGPoint(
                    x: (content.width - bounds.width) * 0.5,
                    y: (content.height - bounds.height) * 0.5
                )
            }
            clampOffset(&offset, in: scrollView)
            scrollView.setContentOffset(offset, animated: false)
        }

        /// Keep `contentRoot` at its base (fit) size and let `zoomScale` carry
        /// the zoom as a transform — the native UIScrollView zoom model. The
        /// page therefore scales as one rasterised image; nothing is resized
        /// or re-rendered while zooming.
        ///
        /// `contentRoot.frame` is only rewritten when the BASE size itself
        /// changes (page swap / rotation), and the current `zoomScale` is
        /// reapplied afterward so the transform survives the bounds change.
        func syncBaseLayout(_ scrollView: UIScrollView) {
            guard let contentRoot, baseContentSize.width > 0, baseContentSize.height > 0 else {
                return
            }
            let bounds = contentRoot.bounds.size
            let baseChanged = abs(bounds.width - baseContentSize.width) > 0.5
                || abs(bounds.height - baseContentSize.height) > 0.5
            if baseChanged {
                let savedScale = scrollView.zoomScale
                contentRoot.transform = .identity
                contentRoot.frame = CGRect(origin: .zero, size: baseContentSize)
                host?.view.frame = CGRect(origin: .zero, size: baseContentSize)
                scrollView.contentSize = baseContentSize
                // Reapply the zoom (UIScrollView re-derives the transform +
                // contentSize from the new bounds).
                scrollView.zoomScale = savedScale
            }
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = maxZoom
            // Honour an externally-driven zoom reset (e.g. page change sets the
            // binding back to 1). Setting zoomScale fires `scrollViewDidZoom`,
            // which recenters.
            let target = max(1, min(maxZoom, currentZoom))
            if abs(scrollView.zoomScale - target) > 0.0005 {
                scrollView.zoomScale = target
            }
        }

        /// Insets so the page sits centered when smaller than viewport.
        /// Called continuously during live zoom (via
        /// `scrollViewDidZoom`) and after commits.
        func centerContent(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds.size
            let content = scrollView.contentSize
            let horizontal = max((bounds.width - content.width) * 0.5, 0)
            let vertical = max((bounds.height - content.height) * 0.5, 0)
            let inset = UIEdgeInsets(
                top: vertical, left: horizontal,
                bottom: vertical, right: horizontal
            )
            if scrollView.contentInset != inset {
                scrollView.contentInset = inset
            }
        }

        // MARK: UIScrollViewDelegate (zoom)

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            contentRoot
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isZooming = true
            PageZoomDebug.zoom("willBegin currentZoom=\(fmt(currentZoom))")
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Native zoom: UIScrollView scales `contentRoot` via a transform
            // and keeps `contentSize = base × zoomScale`. We just track the
            // live scale and keep the page centered when it's smaller than the
            // viewport. No resize, no re-render — the whole page (background +
            // ink + overlays) scales as one image.
            currentZoom = scrollView.zoomScale
            centerContent(in: scrollView)
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            // Nothing to collapse — the transform IS the zoom and we leave it
            // in place. Just record the settled scale, recenter, and report it
            // through the binding so external resets (e.g. page change) can
            // return to fit.
            currentZoom = scale
            isZooming = false
            centerContent(in: scrollView)
            publishZoomBinding(scale)
            PageZoomDebug.zoom("didEnd zoomScale=\(fmt(scale))")
        }

        // MARK: UIScrollViewDelegate (scroll)

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // Re-center while panning a smaller-than-viewport page —
            // handled by `centerContent` via insets. Nothing to do here.
        }

        // MARK: Zoom binding

        func publishZoomBinding(_ value: CGFloat) {
            guard !isApplyingFromSwiftUI,
                  let binding = zoomBinding,
                  abs(binding.wrappedValue - value) > 0.0005 else { return }
            binding.wrappedValue = value
        }

        /// Whether the zoomed page is scrolled hard against the horizontal
        /// content edge in the direction of an intended page swipe. When the
        /// content is no wider than the viewport (no horizontal scroll range)
        /// both edges count, so a swipe can always turn the page.
        private func isAtHorizontalEdge(_ scrollView: UIScrollView, swipingNext: Bool) -> Bool {
            let inset = scrollView.contentInset
            let minX = -inset.left
            let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
            let epsilon: CGFloat = 0.5
            if maxX - minX <= epsilon { return true }
            let x = scrollView.contentOffset.x
            // Next page = swipe left = need the right edge; previous = left edge.
            return swipingNext ? (x >= maxX - epsilon) : (x <= minX + epsilon)
        }

        private func clampOffset(_ offset: inout CGPoint, in scrollView: UIScrollView) {
            let inset = scrollView.contentInset
            let content = scrollView.contentSize
            let bounds = scrollView.bounds.size
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, content.width - bounds.width + inset.right)
            let maxY = max(minY, content.height - bounds.height + inset.bottom)
            offset.x = max(minX, min(maxX, offset.x))
            offset.y = max(minY, min(maxY, offset.y))
        }

        // MARK: Overlay drag (sticker move / resize)

        @objc func handleOverlayPan(_ gesture: UIPanGestureRecognizer) {
            guard let onOverlayManipulation,
                  let scrollView = gesture.view as? UIScrollView,
                  let contentView = contentRoot ?? host?.view else { return }

            switch gesture.state {
            case .began:
                let startInScroll = gesture.location(in: scrollView)
                // `convert` is transform-aware, so this is already in base
                // (unzoomed) page coordinates.
                overlayPanStartLocationInContent = scrollView.convert(startInScroll, to: contentView)
                overlayPanStartZoom = max(0.0001, currentZoom)
                onOverlayManipulation(.began, overlayPanStartLocationInContent, .zero)

            case .changed:
                let translation = gesture.translation(in: scrollView)
                // Translation is in scroll-view (screen) space; divide by the
                // zoom to express it in base page units.
                let baseTranslation = CGSize(
                    width: translation.x / overlayPanStartZoom,
                    height: translation.y / overlayPanStartZoom
                )
                onOverlayManipulation(.changed, overlayPanStartLocationInContent, baseTranslation)

            case .ended:
                let translation = gesture.translation(in: scrollView)
                let baseTranslation = CGSize(
                    width: translation.x / overlayPanStartZoom,
                    height: translation.y / overlayPanStartZoom
                )
                onOverlayManipulation(.ended, overlayPanStartLocationInContent, baseTranslation)

            case .cancelled, .failed:
                onOverlayManipulation(.cancelled, .zero, .zero)

            default:
                break
            }
        }

        // MARK: Overlay pinch (image resize)

        @objc func handleOverlayPinch(_ gesture: UIPinchGestureRecognizer) {
            guard let onOverlayPinchResize else { return }

            switch gesture.state {
            case .began:
                onOverlayPinchResize(.began, 1.0)
            case .changed:
                onOverlayPinchResize(.changed, gesture.scale)
            case .ended:
                onOverlayPinchResize(.ended, gesture.scale)
            case .cancelled, .failed:
                onOverlayPinchResize(.cancelled, 1.0)
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
            // Transform-aware → base page coordinates.
            let localBase = scrollView.convert(location, to: contentView)
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
            // Transform-aware → base page coordinates.
            let local = scrollView.convert(location, to: contentView)
            onPageFingerTap(local)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView,
                  let contentRoot else { return }
            let tapInScroll = gesture.location(in: scrollView)
            let isZoomedIn = scrollView.zoomScale > 1.12
            let targetZoom = isZoomedIn ? CGFloat(1) : min(doubleTapZoomScale, maxZoom)
            guard abs(targetZoom - scrollView.zoomScale) > 0.01 else { return }

            currentZoom = targetZoom
            if targetZoom <= 1.01 {
                // Settle back to fit; centering insets place the page.
                scrollView.setZoomScale(1, animated: true)
            } else {
                // Zoom toward the tap point. `convert` is transform-aware so
                // it yields the base-coordinate point under the finger.
                let tapInContent = scrollView.convert(tapInScroll, to: contentRoot)
                let w = scrollView.bounds.width / targetZoom
                let h = scrollView.bounds.height / targetZoom
                let rect = CGRect(
                    x: tapInContent.x - w * 0.5,
                    y: tapInContent.y - h * 0.5,
                    width: w,
                    height: h
                )
                scrollView.zoom(to: rect, animated: true)
            }
            publishZoomBinding(targetZoom)
        }

        @objc func handleTwoFingerDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTwoFingerDoubleTap?()
        }

        // MARK: Page swipe (fit zoom, or at the horizontal edge when zoomed)

        @objc func handlePagePan(_ sender: UIPanGestureRecognizer) {
            // Apply the swipe to the hosted content view, NOT `contentRoot`:
            // `contentRoot` is the zoom view whose transform UIScrollView owns,
            // so writing a translation transform there would wipe the zoom.
            guard let scrollView = sender.view as? UIScrollView,
                  let pageView = host?.view ?? contentRoot else {
                resetPageSlide(animated: true)
                return
            }

            let translation = sender.translation(in: scrollView)
            let velocity = sender.velocity(in: scrollView)
            // When the page is zoomed, `pageView` (the hosted content) lives
            // inside the scaled `contentRoot`, so a translation written to its
            // transform is multiplied by the live zoom on screen. Divide by the
            // captured zoom so the page tracks the finger 1:1 at any zoom.
            let zoomDivisor = max(slidePanZoom, 0.0001)

            switch sender.state {
            case .began:
                isSlidingPage = false
                didFireBoundaryHaptic = false
                slidePanZoom = max(currentZoom, 0.0001)
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
                pageView.transform = CGAffineTransform(translationX: displayedX / zoomDivisor, y: 0)
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
                    let span = max(width, baseContentSize.width)
                    let exitX = (shouldGoNext ? -1 : 1) * span
                    // Slide the current page out at the live zoom (divide so the
                    // on-screen travel is a full viewport width). The incoming
                    // page enters at fit — the page change resets zoom to 1 — so
                    // its parked position below uses plain base coordinates.
                    UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseIn]) {
                        pageView.transform = CGAffineTransform(translationX: exitX / zoomDivisor, y: 0)
                    } completion: { [weak self] _ in
                        guard let self else {
                            pageView.transform = .identity
                            return
                        }
                        // Swap to the destination page's content while the
                        // page view is parked fully OFF-screen, so the old
                        // page is never shown centered mid-load (that was the
                        // ~0.1s "flash of the previous page"). Then park it on
                        // the opposite edge and slide the freshly-loaded page
                        // in, masking the SwiftUI/PencilKit content push.
                        if shouldGoNext {
                            self.onSwipeNext?()
                        } else {
                            self.onSwipePrevious?()
                        }
                        // Snap back to fit deterministically (the page change
                        // also resets the zoom binding, but that round-trips
                        // through SwiftUI). Doing it here means `contentRoot`
                        // is at scale 1 before we park the page, so the parked
                        // position + slide-in below use plain base coordinates.
                        if scrollView.zoomScale > 1.0001 {
                            scrollView.setZoomScale(1, animated: false)
                        }
                        self.currentZoom = 1
                        self.slidePanZoom = 1
                        self.publishZoomBinding(1)
                        pageView.transform = CGAffineTransform(translationX: -exitX, y: 0)
                        // Defer the slide-in one runloop so SwiftUI has applied
                        // the new page content + pushed the drawing into the
                        // still-off-screen page view before any pixel of it
                        // becomes visible.
                        DispatchQueue.main.async {
                            UIView.animate(
                                withDuration: 0.2,
                                delay: 0,
                                options: [.curveEaseOut]
                            ) {
                                pageView.transform = .identity
                            }
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
            guard let pageView = host?.view ?? contentRoot else { return }
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
                let localBase = scrollView.convert(location, to: contentView)
                return toolbarRect.contains(localBase)
            }
            if gestureRecognizer === overlayPanGesture {
                guard blocksPageGestures,
                      let pan = gestureRecognizer as? UIPanGestureRecognizer,
                      let scrollView = pan.view as? UIScrollView,
                      let contentView = contentRoot ?? host?.view else {
                    return false
                }
                let location = pan.location(in: scrollView)
                let pageFrame = contentView.convert(contentView.bounds, to: scrollView)
                guard pageFrame.contains(location) else { return false }
                let localBase = scrollView.convert(location, to: contentView)
                for rect in overlayInteractionExclusionRects where rect.contains(localBase) {
                    return false
                }
                return true
            }
            if gestureRecognizer === overlayPinchGesture {
                guard let targetRect = overlayPinchTargetRect,
                      onOverlayPinchResize != nil,
                      let pinch = gestureRecognizer as? UIPinchGestureRecognizer,
                      let scrollView = pinch.view as? UIScrollView,
                      let contentView = contentRoot ?? host?.view,
                      pinch.numberOfTouches >= 1 else {
                    return false
                }
                for touchIndex in 0..<pinch.numberOfTouches {
                    let location = pinch.location(ofTouch: touchIndex, in: scrollView)
                    let pageFrame = contentView.convert(contentView.bounds, to: scrollView)
                    guard pageFrame.contains(location) else { return false }
                    let localBase = scrollView.convert(location, to: contentView)
                    guard targetRect.contains(localBase) else { return false }
                    for rect in overlayInteractionExclusionRects where rect.contains(localBase) {
                        return false
                    }
                }
                return true
            }
            if gestureRecognizer === pagePanGesture {
                if blocksPageGestures { return false }
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                      let scrollView = pan.view as? UIScrollView else {
                    return true
                }
                let velocity = pan.velocity(in: scrollView)
                // Must be a clearly horizontal intent regardless of zoom.
                guard abs(velocity.x) > abs(velocity.y) * 1.35 else { return false }
                // At fit zoom the page swipe always owns horizontal pans.
                if currentZoom <= 1.08 { return true }
                // Zoomed in: only hijack the pan for a page change when the
                // page is already scrolled to the horizontal edge in the swipe
                // direction, so normal panning around the zoomed page keeps
                // working everywhere else.
                let swipingNext = velocity.x < 0
                return isAtHorizontalEdge(scrollView, swipingNext: swipingNext)
            }
            return true
        }

        private func fmt(_ value: CGFloat) -> String { String(format: "%.2f", value) }
    }
}

/// Host wrapper for the SwiftUI page card.
///
/// Touch routing is a 3-way split, decided per `hitTest`:
///   1. PKCanvasView wants the touch (Pencil ink, eraser etc.) → return
///      that canvas hit so PencilKit gets it.
///   2. Multi-touch is in flight → return nil so the outer
///      `UIScrollView`'s pinch recognizer can grab both fingers.
///   3. Single-finger touch on an "empty" area → return the hosting
///      view so SwiftUI overlay drag/tap gestures fire.
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

private func fmt(_ value: CGFloat) -> String { String(format: "%.2f", value) }
