//
//  NotePageBackgroundDrawing.swift
//  Noteworks
//
//  Shared layout metrics and drawing for page templates. Used by the
//  on-screen background view and PDF export so patterns stay in sync.
//

import CoreGraphics
import SwiftUI

enum NotePageBackgroundMetrics {
    static let gridSpacing: CGFloat = 28
    static let ruledSpacing: CGFloat = 28
    static let pageInset: CGFloat = 24
    static let lineOpacity: CGFloat = 0.12
    static let dividerOpacity: CGFloat = 0.14
    static let cornellCueWidthFraction: CGFloat = 0.28
    static let cornellSummaryHeightFraction: CGFloat = 0.14
}

enum NotePageBackgroundDrawing {

    // MARK: - CGContext (PDF export)

    /// `scale` multiplies every page-relative metric (spacing, inset,
    /// dot radius, line width) so the pattern stays at a fixed density
    /// in PAGE coordinates regardless of how big `rect` is. PDF export
    /// passes `scale == 1` (rect already equals base page size); the
    /// on-screen pattern view passes the current zoom so a 2x-zoomed
    /// page draws dots 2x further apart in screen points, which means
    /// they sit at the same page positions as at zoom 1.
    static func draw(
        _ background: NotePageBackground,
        in rect: CGRect,
        context cg: CGContext,
        scale: CGFloat = 1.0
    ) {
        let s = max(0.0001, scale)
        switch background {
        case .blank:
            break
        case .dots:
            drawDotGrid(in: rect, context: cg, scale: s)
        case .singleColumn:
            drawRuled(in: rect, context: cg, scale: s)
        case .grid:
            drawGrid(in: rect, context: cg, scale: s)
        case .cornell:
            drawCornell(in: rect, context: cg, scale: s)
        }
    }

    private static func drawDotGrid(in rect: CGRect, context cg: CGContext, scale: CGFloat) {
        let spacing = NotePageBackgroundMetrics.gridSpacing * scale
        let radius: CGFloat = max(0.5, 1 * scale)
        cg.saveGState()
        cg.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
        var y = spacing
        while y < rect.height {
            var x = spacing
            while x < rect.width {
                let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                cg.addEllipse(in: dot)
                cg.fillPath()
                x += spacing
            }
            y += spacing
        }
        cg.restoreGState()
    }

    private static func drawRuled(in rect: CGRect, context cg: CGContext, scale: CGFloat) {
        let inset = NotePageBackgroundMetrics.pageInset * scale
        let spacing = NotePageBackgroundMetrics.ruledSpacing * scale
        cg.saveGState()
        cg.setStrokeColor(UIColor.black.withAlphaComponent(NotePageBackgroundMetrics.lineOpacity).cgColor)
        cg.setLineWidth(max(0.5, 1 * scale))
        var y = inset + spacing
        while y < rect.height - inset {
            cg.move(to: CGPoint(x: inset, y: y))
            cg.addLine(to: CGPoint(x: rect.width - inset, y: y))
            cg.strokePath()
            y += spacing
        }
        cg.restoreGState()
    }

    private static func drawGrid(in rect: CGRect, context cg: CGContext, scale: CGFloat) {
        let spacing = NotePageBackgroundMetrics.gridSpacing * scale
        let inset = NotePageBackgroundMetrics.pageInset * scale
        cg.saveGState()
        cg.setStrokeColor(UIColor.black.withAlphaComponent(NotePageBackgroundMetrics.lineOpacity).cgColor)
        cg.setLineWidth(max(0.5, 1 * scale))
        var x = inset
        while x <= rect.width - inset {
            cg.move(to: CGPoint(x: x, y: inset))
            cg.addLine(to: CGPoint(x: x, y: rect.height - inset))
            cg.strokePath()
            x += spacing
        }
        var y = inset
        while y <= rect.height - inset {
            cg.move(to: CGPoint(x: inset, y: y))
            cg.addLine(to: CGPoint(x: rect.width - inset, y: y))
            cg.strokePath()
            y += spacing
        }
        cg.restoreGState()
    }

    private static func drawCornell(in rect: CGRect, context cg: CGContext, scale: CGFloat) {
        let inset = NotePageBackgroundMetrics.pageInset * scale
        let spacing = NotePageBackgroundMetrics.ruledSpacing * scale
        let cueX = rect.width * NotePageBackgroundMetrics.cornellCueWidthFraction
        let summaryTop = rect.height * (1 - NotePageBackgroundMetrics.cornellSummaryHeightFraction)
        let notesBottom = summaryTop - spacing

        cg.saveGState()
        cg.setLineWidth(max(0.5, 1 * scale))

        cg.setStrokeColor(UIColor.black.withAlphaComponent(NotePageBackgroundMetrics.dividerOpacity).cgColor)
        cg.move(to: CGPoint(x: cueX, y: inset))
        cg.addLine(to: CGPoint(x: cueX, y: notesBottom))
        cg.strokePath()
        cg.move(to: CGPoint(x: inset, y: summaryTop))
        cg.addLine(to: CGPoint(x: rect.width - inset, y: summaryTop))
        cg.strokePath()

        cg.setStrokeColor(UIColor.black.withAlphaComponent(NotePageBackgroundMetrics.lineOpacity).cgColor)
        var y = inset + spacing
        while y < notesBottom {
            cg.move(to: CGPoint(x: cueX + spacing * 0.5, y: y))
            cg.addLine(to: CGPoint(x: rect.width - inset, y: y))
            cg.strokePath()
            y += spacing
        }
        cg.restoreGState()
    }

    // MARK: - SwiftUI GraphicsContext (on-screen)

    static func draw(
        _ background: NotePageBackground,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        switch background {
        case .blank:
            break
        case .dots:
            drawDotGrid(size: size, context: &context)
        case .singleColumn:
            drawRuled(size: size, context: &context)
        case .grid:
            drawGrid(size: size, context: &context)
        case .cornell:
            drawCornell(size: size, context: &context)
        }
    }

    private static func drawDotGrid(size: CGSize, context: inout GraphicsContext) {
        let spacing = NotePageBackgroundMetrics.gridSpacing
        let radius: CGFloat = 1
        let dotColor = Color.black.opacity(0.18)
        var y = spacing
        while y < size.height {
            var x = spacing
            while x < size.width {
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                x += spacing
            }
            y += spacing
        }
    }

    private static func drawRuled(size: CGSize, context: inout GraphicsContext) {
        let inset = NotePageBackgroundMetrics.pageInset
        let spacing = NotePageBackgroundMetrics.ruledSpacing
        let color = Color.black.opacity(NotePageBackgroundMetrics.lineOpacity)
        let style = StrokeStyle(lineWidth: 1)
        var y = inset + spacing
        while y < size.height - inset {
            var path = Path()
            path.move(to: CGPoint(x: inset, y: y))
            path.addLine(to: CGPoint(x: size.width - inset, y: y))
            context.stroke(path, with: .color(color), style: style)
            y += spacing
        }
    }

    private static func drawGrid(size: CGSize, context: inout GraphicsContext) {
        let spacing = NotePageBackgroundMetrics.gridSpacing
        let inset = NotePageBackgroundMetrics.pageInset
        let color = Color.black.opacity(NotePageBackgroundMetrics.lineOpacity)
        let style = StrokeStyle(lineWidth: 1)
        var x = inset
        while x <= size.width - inset {
            var path = Path()
            path.move(to: CGPoint(x: x, y: inset))
            path.addLine(to: CGPoint(x: x, y: size.height - inset))
            context.stroke(path, with: .color(color), style: style)
            x += spacing
        }
        var y = inset
        while y <= size.height - inset {
            var path = Path()
            path.move(to: CGPoint(x: inset, y: y))
            path.addLine(to: CGPoint(x: size.width - inset, y: y))
            context.stroke(path, with: .color(color), style: style)
            y += spacing
        }
    }

    private static func drawCornell(size: CGSize, context: inout GraphicsContext) {
        let inset = NotePageBackgroundMetrics.pageInset
        let spacing = NotePageBackgroundMetrics.ruledSpacing
        let cueX = size.width * NotePageBackgroundMetrics.cornellCueWidthFraction
        let summaryTop = size.height * (1 - NotePageBackgroundMetrics.cornellSummaryHeightFraction)
        let notesBottom = summaryTop - spacing
        let dividerColor = Color.black.opacity(NotePageBackgroundMetrics.dividerOpacity)
        let lineColor = Color.black.opacity(NotePageBackgroundMetrics.lineOpacity)
        let style = StrokeStyle(lineWidth: 1)

        var cueDivider = Path()
        cueDivider.move(to: CGPoint(x: cueX, y: inset))
        cueDivider.addLine(to: CGPoint(x: cueX, y: notesBottom))
        context.stroke(cueDivider, with: .color(dividerColor), style: style)

        var summaryDivider = Path()
        summaryDivider.move(to: CGPoint(x: inset, y: summaryTop))
        summaryDivider.addLine(to: CGPoint(x: size.width - inset, y: summaryTop))
        context.stroke(summaryDivider, with: .color(dividerColor), style: style)

        var y = inset + spacing
        while y < notesBottom {
            var path = Path()
            path.move(to: CGPoint(x: cueX + spacing * 0.5, y: y))
            path.addLine(to: CGPoint(x: size.width - inset, y: y))
            context.stroke(path, with: .color(lineColor), style: style)
            y += spacing
        }
    }
}
