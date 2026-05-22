//
//  NotePageBackgroundView.swift
//  Noteworks
//
//  Draws the per-page background pattern behind the PencilKit canvas.
//  Templates: blank, dots, ruled (legacy key `single-column`), grid,
//  and Cornell. Rotation is applied on the parent page card.
//
//  The pattern is drawn through a UIView's `draw(_:)` (wrapped via
//  `UIViewRepresentable`) instead of SwiftUI's `Canvas`. SwiftUI's
//  `Canvas` rasterizes into a backing texture at the layer's current
//  `contentsScale` at the time of draw; when the outer scroll view
//  later zooms via a CATransform3D, that backing bitmap is stretched
//  and dots/lines go blurry. A `draw(_:)`-backed UIView honours
//  `contentScaleFactor` — the zoom controller bumps that scale during
//  pinch so the pattern re-rasterises at the new resolution and stays
//  crisp.
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

/// `UIView` that draws the page pattern (dots / grid / ruled / Cornell)
/// using `CGContext` inside `draw(_:)`. Because UIKit invokes `draw(_:)`
/// at the layer's `contentsScale`, bumping that scale during zoom causes
/// the pattern to re-rasterise crisply at the new resolution.
final class BackgroundPatternUIView: UIView {
    var background: NotePageBackground = .blank {
        didSet {
            guard oldValue != background else { return }
            setNeedsDisplay()
        }
    }
    /// Pattern density multiplier — `zoomScale` from the parent. Larger
    /// values make the spacing between dots/lines proportionally larger
    /// so the pattern stays glued to page coordinates at every zoom.
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
        layer.drawsAsynchronously = false
        isUserInteractionEnabled = false
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
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
