//
//  NotePageBackgroundView.swift
//  Noteworks
//
//  Draws the per-page background pattern behind the PencilKit canvas.
//  Mirrors the JSX `getBackgroundClasses` (L2562) styles:
//    • blank          — solid white
//    • dots           — 28px dot grid (Tailwind `bg-[radial-gradient]`)
//    • single-column  — vertical centerline + faint side guides
//
//  Rotation is applied via `.rotationEffect` so the pattern (and the
//  canvas above it) flips together cleanly.
//

import SwiftUI
import UIKit

struct NotePageBackgroundView: View {
    let background: NotePageBackground
    var imageData: Data? = nil

    var body: some View {
        ZStack {
            if let imageData,
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            Canvas { context, size in
                switch background {
                case .blank:
                    break
                case .dots:
                    drawDotGrid(context: context, size: size)
                case .singleColumn:
                    drawSingleColumn(context: context, size: size)
                }
            }
        }
        .clipped()
    }

    private func drawDotGrid(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 28
        let radius: CGFloat = 1
        let dotColor = Color.black.opacity(0.18)
        var y: CGFloat = spacing
        while y < size.height {
            var x: CGFloat = spacing
            while x < size.width {
                let rect = CGRect(x: x - radius, y: y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                x += spacing
            }
            y += spacing
        }
    }

    private func drawSingleColumn(context: GraphicsContext, size: CGSize) {
        let centerX = size.width / 2
        let columnWidth = min(size.width * 0.62, 720)
        let leftEdge = centerX - columnWidth / 2
        let rightEdge = centerX + columnWidth / 2

        var center = Path()
        center.move(to: CGPoint(x: centerX, y: 24))
        center.addLine(to: CGPoint(x: centerX, y: size.height - 24))
        context.stroke(center, with: .color(Color.black.opacity(0.10)),
                       style: StrokeStyle(lineWidth: 1, dash: [6, 6]))

        var leftGuide = Path()
        leftGuide.move(to: CGPoint(x: leftEdge, y: 24))
        leftGuide.addLine(to: CGPoint(x: leftEdge, y: size.height - 24))
        context.stroke(leftGuide, with: .color(Color.black.opacity(0.06)),
                       style: StrokeStyle(lineWidth: 1))

        var rightGuide = Path()
        rightGuide.move(to: CGPoint(x: rightEdge, y: 24))
        rightGuide.addLine(to: CGPoint(x: rightEdge, y: size.height - 24))
        context.stroke(rightGuide, with: .color(Color.black.opacity(0.06)),
                       style: StrokeStyle(lineWidth: 1))
    }
}
