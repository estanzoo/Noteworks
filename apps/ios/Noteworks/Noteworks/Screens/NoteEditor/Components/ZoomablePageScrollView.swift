//
//  ZoomablePageScrollView.swift
//  Noteworks
//
//  Zoom + pan host for the note page.
//
//  Architecture (rewrite using Apple's UIScrollView zoom pattern):
//
//  We let UIScrollView do what it's good at:
//    - `viewForZooming` returns `contentRoot` so the system pinch
//      recognizer drives the live zoom preview via a CATransform on
//      `contentRoot`.
//    - `scrollViewDidZoom` recenters `contentRoot` via `contentInset`
//      so the page stays magnetically centered when smaller than the
//      viewport (no top-left-corner stickiness).
//    - `scrollViewDidEndZooming(_:with:atScale:)` collapses the
//      transform into a real `contentRoot.frame` resize:
//          newZoom = currentZoom * scrollScale
//          contentRoot.frame = base * newZoom
//          scrollView.zoomScale = 1
//          contentOffset = adjusted so the same content rect stays put
//      Then publishes `newZoom` to SwiftUI so the page card rebuilds
//      at the new logical size and PencilKit re-rasterizes natively.
//
//  Knobs from the blueprint:
//    - `bounces = false`, `alwaysBounceX/Y = false` → no rubber-band.
//    - `minimumZoomScale = fitScale`, `maximumZoomScale = maxZoom /
//      currentZoom` so cumulative zoom stays within `[1, maxZoom]`.
//    - `contentSize == contentRoot.frame.size` so panning is only
//      enabled when zoomed in past the viewport.
//
//  Other surfaces still served by this view:
//    - Page swipe (single-finger pan at fit zoom) via a dedicated
//      `UIPanGestureRecognizer`.
//    - Double-tap to toggle between fit and `doubleTapZoomScale`.
//    - Single-finger tap → `onPageFingerTap` (base coords).
//    - Overlay drag / resize via `UIPanGestureRecognizer` enabled
//      when `blocksPageGestures` is true.
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
        overlayPanAcceptsPencil: Bool = false,
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
        self.overlayPanAcceptsPencil = overlayPanAcceptsPencil
        self._zoom = zoom
        self.content = content
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maxZoom
        scrollView.bouncesZoom = false
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
        context.coordinator.toolbarTapGesture = toolbarTap
        context.coordinator.blocksPageGestures = blocksPageGestures
        context.coordinator.onPageFingerTap = onPageFingerTap
        context.coordinator.onOverlayManipulation = onOverlayManipulation
        context.coordinator.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        context.coordinator.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        context.coordinator.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
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
        context.coordinator.canvasTapGesture?.isEnabled = onPageFingerTap != nil
        context.coordinator.onOverlayManipulation = onOverlayManipulation
        context.coordinator.overlayInteractionExclusionRects = overlayInteractionExclusionRects
        context.coordinator.overlayAdjustToolbarRect = overlayAdjustToolbarRect
        context.coordinator.onOverlayAdjustToolbarTap = onOverlayAdjustToolbarTap
        context.coordinator.overlayPanAcceptsPencil = overlayPanAcceptsPencil
        context.coordinator.applyOverlayPanTouchTypes()
        context.coordinator.toolbarTapGesture?.isEnabled = onOverlayAdjustToolbarTap != nil
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
            context.coordinator.applyZoomedContentSize(scrollView)
            context.coordinator.centerContent(in: scrollView)
            if baseChanged {
                context.coordinator.recenterScrollOffset(scrollView)
                context.coordinator.publishZoomBinding(1)
                // Run again on the next runloop tick — scrollView.bounds
                // is often briefly stale during a rotation transition,
                // and the first pass uses pre-rotation bounds.
                DispatchQueue.main.async {
                    context.coordinator.applyZoomedContentSize(scrollView)
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
        /// Cumulative zoom factor (baseContentSize × currentZoom = page
        /// frame size). Always >= 1.
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
        var overlayPanAcceptsPencil: Bool = false
        var zoomBinding: Binding<CGFloat>?
        weak var pagePanGesture: UIPanGestureRecognizer?
        weak var canvasTapGesture: UITapGestureRecognizer?
        weak var toolbarTapGesture: UITapGestureRecognizer?
        weak var overlayPanGesture: UIPanGestureRecognizer?
        fileprivate var isApplyingFromSwiftUI = false

        /// True between `scrollViewWillBeginZooming` and
        /// `scrollViewDidEndZooming`. While zooming, we leave layout to
        /// UIScrollView; on end, we collapse the live transform into a
        /// real `contentRoot.frame` resize.
        private(set) var isZooming: Bool = false
        // Page swipe state.
        private var isSlidingPage = false
        private var didFireBoundaryHaptic = false

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
            applyZoomedContentSize(scrollView)
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

        /// Set `contentRoot.frame` = `baseContentSize × currentZoom` and
        /// sync `scrollView.contentSize`. Also resets the live zoom
        /// transform so `zoomScale` reads as 1.
        func applyZoomedContentSize(_ scrollView: UIScrollView) {
            guard let contentRoot, baseContentSize.width > 0, baseContentSize.height > 0 else {
                return
            }
            let target = CGSize(
                width: baseContentSize.width * currentZoom,
                height: baseContentSize.height * currentZoom
            )
            let currentSize = contentRoot.bounds.size
            let needsResize = abs(currentSize.width - target.width) > 0.5
                || abs(currentSize.height - target.height) > 0.5
            if needsResize {
                contentRoot.transform = .identity
                contentRoot.frame = CGRect(origin: .zero, size: target)
                host?.view.frame = CGRect(origin: .zero, size: target)
                scrollView.contentSize = target
            }
            // After committing a zoom, `zoomScale` must be 1 so the next
            // live pinch starts from a clean state.
            if scrollView.zoomScale != 1 {
                scrollView.zoomScale = 1
            }
            // `zoomScale` is the multiplier ON TOP OF `currentZoom`.
            //   - Pinch out (scale < 1) drops cumulative zoom toward 1
            //     (fit), but not below: minScale = 1 / currentZoom.
            //   - Pinch in (scale > 1) raises cumulative zoom toward
            //     maxZoom: maxScale = maxZoom / currentZoom.
            let minScale = 1 / max(currentZoom, 0.0001)
            let maxScale = max(maxZoom / max(currentZoom, 0.0001), minScale)
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = maxScale
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
            // Keep page centered during live pinch. UIScrollView writes
            // `contentSize = contentRoot.frame.size × zoomScale` while
            // pinching, so `centerContent` reads the live size.
            centerContent(in: scrollView)
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView,
            with view: UIView?,
            atScale scale: CGFloat
        ) {
            // Collapse the live transform into a real frame resize so
            // PencilKit + the pattern view re-rasterize at native size.
            //
            // What UIScrollView has done so far during the pinch:
            //   - Set `zoomScale = scale` (applies a CATransform to
            //     `contentRoot`).
            //   - Set `contentSize = contentRoot.bounds.size × scale`.
            //   - Adjusted `contentOffset` so the pinch focal stays
            //     under the user's fingers.
            //
            // What we do now: turn the temporary scale into a real
            // content-size bump so PencilKit renders sharp.
            //
            //   newZoom = currentZoom × scale
            //   contentRoot.frame = baseContentSize × newZoom
            //   zoomScale = 1
            //   contentOffset = (viewportCenter in new content) - viewport/2
            let newZoom = min(maxZoom, max(1, currentZoom * scale))

            // Capture the content point at the viewport center BEFORE
            // we tear down the live zoom transform. After the resize,
            // we'll set `contentOffset` so the same point lands at the
            // new viewport center.
            //
            // `contentOffset` is already in the post-zoom coordinate
            // system (UIScrollView mutated it during pinch). The
            // content point at viewport center is:
            //     centerInContent_postZoom = contentOffset + bounds.size/2
            // To express that in the NEW content coords (after we resize
            // contentRoot to base × newZoom from base × currentZoom),
            // multiply by the ratio between "scale we applied" and
            // "real zoom factor we're committing":
            //     newPoint = centerInContent_postZoom × (newZoom / (currentZoom × scale))
            let postZoomCenter = CGPoint(
                x: scrollView.contentOffset.x + scrollView.bounds.width * 0.5,
                y: scrollView.contentOffset.y + scrollView.bounds.height * 0.5
            )
            let collapseRatio = newZoom / max(currentZoom * scale, 0.0001)
            let newCenter = CGPoint(
                x: postZoomCenter.x * collapseRatio,
                y: postZoomCenter.y * collapseRatio
            )

            currentZoom = newZoom
            applyZoomedContentSize(scrollView)
            centerContent(in: scrollView)

            // When page fits viewport (newZoom == 1), centering insets
            // do the work — pin offset to the inset top-left so page
            // sits dead center.
            let bounds = scrollView.bounds.size
            let inset = scrollView.contentInset
            var offset: CGPoint
            if newZoom <= 1.001 {
                offset = CGPoint(x: -inset.left, y: -inset.top)
            } else {
                offset = CGPoint(
                    x: newCenter.x - bounds.width * 0.5,
                    y: newCenter.y - bounds.height * 0.5
                )
            }
            clampOffset(&offset, in: scrollView)
            scrollView.setContentOffset(offset, animated: false)

            isZooming = false
            publishZoomBinding(newZoom)

            PageZoomDebug.zoom(
                "didEnd newZoom=\(fmt(newZoom)) "
                + "contentSize=\(fmt(scrollView.contentSize.width))×\(fmt(scrollView.contentSize.height)) "
                + "offset=(\(fmt(scrollView.contentOffset.x)),\(fmt(scrollView.contentOffset.y)))"
            )
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
                overlayPanStartLocationInContent = scrollView.convert(startInScroll, to: contentView)
                overlayPanStartZoom = max(0.0001, currentZoom)
                let baseStart = CGPoint(
                    x: overlayPanStartLocationInContent.x / overlayPanStartZoom,
                    y: overlayPanStartLocationInContent.y / overlayPanStartZoom
                )
                onOverlayManipulation(.began, baseStart, .zero)

            case .changed:
                let translation = gesture.translation(in: scrollView)
                let baseStart = CGPoint(
                    x: overlayPanStartLocationInContent.x / overlayPanStartZoom,
                    y: overlayPanStartLocationInContent.y / overlayPanStartZoom
                )
                let baseTranslation = CGSize(
                    width: translation.x / overlayPanStartZoom,
                    height: translation.y / overlayPanStartZoom
                )
                onOverlayManipulation(.changed, baseStart, baseTranslation)

            case .ended:
                let translation = gesture.translation(in: scrollView)
                let baseStart = CGPoint(
                    x: overlayPanStartLocationInContent.x / overlayPanStartZoom,
                    y: overlayPanStartLocationInContent.y / overlayPanStartZoom
                )
                let baseTranslation = CGSize(
                    width: translation.x / overlayPanStartZoom,
                    height: translation.y / overlayPanStartZoom
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
            let local = CGPoint(
                x: localScaled.x / currentZoom,
                y: localScaled.y / currentZoom
            )
            onPageFingerTap(local)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView,
                  let contentRoot else { return }
            let tapInScroll = gesture.location(in: scrollView)
            let isZoomedIn = currentZoom > 1.12
            let targetZoom = isZoomedIn ? CGFloat(1) : min(doubleTapZoomScale, maxZoom)
            guard abs(targetZoom - currentZoom) > 0.01 else { return }

            // Resize content directly; UIScrollView zoom infra not used.
            let tapInContent = scrollView.convert(tapInScroll, to: contentRoot)
            let zoomRatio = targetZoom / max(currentZoom, 0.0001)
            let tapInNewContent = CGPoint(
                x: tapInContent.x * zoomRatio,
                y: tapInContent.y * zoomRatio
            )

            currentZoom = targetZoom
            applyZoomedContentSize(scrollView)
            centerContent(in: scrollView)

            // Place tap point under finger.
            var offset = CGPoint(
                x: tapInNewContent.x - tapInScroll.x,
                y: tapInNewContent.y - tapInScroll.y
            )
            // When zoomed out (target = 1), let centering insets handle
            // placement — offset of -inset.{left,top} lands the page
            // origin at its inset position, which centerContent already
            // made symmetric.
            if targetZoom <= 1.01 {
                let inset = scrollView.contentInset
                offset = CGPoint(x: -inset.left, y: -inset.top)
            }
            clampOffset(&offset, in: scrollView)
            UIView.animate(withDuration: 0.25) {
                scrollView.setContentOffset(offset, animated: false)
            }
            publishZoomBinding(targetZoom)
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
