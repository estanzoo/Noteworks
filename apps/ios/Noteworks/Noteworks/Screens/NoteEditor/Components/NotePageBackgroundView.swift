//
//  NotePageBackgroundView.swift
//  Noteworks
//
//  Draws the per-page background pattern behind the PencilKit canvas.
//  Templates: blank, dots, ruled (legacy key `single-column`), grid,
//  and Cornell. Rotation is applied on the parent page card.
//
//  The pattern is drawn through a `CATiledLayer`-backed UIView (wrapped via
//  `UIViewRepresentable`) instead of SwiftUI's `Canvas`. SwiftUI's
//  `Canvas` rasterizes into a backing texture at the layer's current
//  `contentsScale` at the time of draw; when the outer scroll view later
//  zooms via a CATransform, that single bitmap is stretched and dots/lines
//  go blurry. The whole-page zoom is photo-style (one raster, no re-render)
//  for the ink, but the background is cheap and identity-free to redraw, so
//  here we use a `CATiledLayer`: it renders only the visible tiles at the
//  CURRENT on-screen scale and re-tessellates crisp tiles (with a short
//  fade) as the page zooms. The pattern therefore stays sharp at any zoom
//  with memory bounded to the visible area — the classic map / PDF
//  infinite-zoom technique — rather than softening like a fixed bitmap.
//

import SwiftUI
import UIKit

struct NotePageBackgroundView: View {
    let background: NotePageBackground
    var imageData: Data? = nil
    /// Current page zoom (1.0 = fit). Used to scale the pattern's
    /// spacing/insets so dots and lines stay locked to the same page
    /// coordinates as the user zooms in — without this, a 28pt dot
    /// spacing applied to a 2x-zoomed page would produce twice as
    /// many dots in the same physical area.
    var zoomScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let imageData,
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            BackgroundPatternUIView.Representable(background: background, zoomScale: zoomScale)
        }
        .clipped()
    }
}

/// `CATiledLayer` that drops the default tile fade-in to a quick blend, so
/// freshly re-rendered crisp tiles replace the stretched ones smoothly as
/// the page zooms instead of popping.
final class BackgroundTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0.12 }
}

/// `UIView` that draws the page pattern (dots / grid / ruled / Cornell)
/// using `CGContext`, backed by a `CATiledLayer`. The tiled layer renders
/// only the visible tiles at the current on-screen scale, so as the outer
/// scroll view zooms the page the pattern re-tessellates crisp at the new
/// resolution (bounded memory) instead of stretching one fixed bitmap.
final class BackgroundPatternUIView: UIView {
    override class var layerClass: AnyClass { BackgroundTiledLayer.self }

    var background: NotePageBackground = .blank {
        didSet {
            guard oldValue != background else { return }
            setNeedsDisplay()
        }
    }
    /// Pattern density multiplier in PAGE coordinates. With the photo-style
    /// page zoom this stays at 1 (the tiled layer handles zoom), but it is
    /// kept so the spacing/inset math can still be scaled if needed.
    var patternScale: CGFloat = 1.0 {
        didSet {
            guard abs(oldValue - patternScale) > 0.0005 else { return }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
        if let tiled = layer as? CATiledLayer {
            // 512pt tiles keep the tile count low for a full page; the bias
            // grants extra zoomed-in detail levels (2^7 = 128x headroom) so
            // the pattern stays crisp well past the ink supersample ceiling.
            tiled.tileSize = CGSize(width: 512, height: 512)
            tiled.levelsOfDetail = 1
            tiled.levelsOfDetailBias = 7
        }
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        // CATiledLayer clips `cg` to the tile being drawn; we draw the full
        // page pattern each time and let the clip select the tile, so dots
        // and lines stay aligned across tile boundaries.
        NotePageBackgroundDrawing.draw(
            background,
            in: bounds,
            context: cg,
            scale: patternScale
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    struct Representable: UIViewRepresentable {
        let background: NotePageBackground
        let zoomScale: CGFloat

        func makeUIView(context: Context) -> BackgroundPatternUIView {
            let view = BackgroundPatternUIView()
            view.background = background
            view.patternScale = zoomScale
            return view
        }

        func updateUIView(_ uiView: BackgroundPatternUIView, context: Context) {
            uiView.background = background
            uiView.patternScale = zoomScale
        }
    }
}
