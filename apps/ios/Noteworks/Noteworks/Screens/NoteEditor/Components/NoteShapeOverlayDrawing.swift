//
//  NoteShapeOverlayDrawing.swift
//  Noteworks
//
//  Vector shape rendering for shape overlays (SwiftUI + PDF export).
//

import SwiftUI
import UIKit

enum NoteShapeOverlayDrawing {

    static func resolvedType(_ raw: String?) -> NoteShapeType {
        guard let raw, let type = NoteShapeType(rawValue: raw) else { return .rectangle }
        return type
    }

    static func strokeColor(hex: String?) -> Color {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count == 6,
              let value = UInt64(raw, radix: 16) else {
            return NoteEditorTheme.textPrimary
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - SwiftUI

    @ViewBuilder
    static func shapeView(type: NoteShapeType, color: Color, lineWidth: CGFloat = 2.5) -> some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            shapePath(type: type, in: rect)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - Core Graphics (PDF)

    static func draw(
        type: NoteShapeType,
        in rect: CGRect,
        colorHex: String?,
        lineWidth: CGFloat = 2.5,
        context cg: CGContext
    ) {
        let path = cgPath(type: type, in: rect)
        cg.saveGState()
        cg.setStrokeColor((uiColorFromHex(colorHex) ?? .label).cgColor)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.addPath(path)
        cg.strokePath()
        cg.restoreGState()
    }

    static func shapePath(type: NoteShapeType, in rect: CGRect) -> Path {
        Path { path in
            append(to: &path, type: type, in: rect)
        }
    }

    static func cgPath(type: NoteShapeType, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        switch type {
        case .rectangle:
            path.addRect(rect.insetBy(dx: 1.5, dy: 1.5))
        case .circle:
            path.addEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))
        case .triangle:
            let inset = rect.insetBy(dx: 2, dy: 2)
            path.move(to: CGPoint(x: inset.midX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            path.closeSubpath()
        case .diamond:
            let inset = rect.insetBy(dx: 2, dy: 2)
            path.move(to: CGPoint(x: inset.midX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.midY))
            path.closeSubpath()
        case .line:
            path.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
        case .arrow:
            let inset = rect.insetBy(dx: 4, dy: 4)
            let tailY = inset.midY
            let headX = inset.maxX
            let tailX = inset.minX
            path.move(to: CGPoint(x: tailX, y: tailY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: tailY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: inset.minY))
            path.addLine(to: CGPoint(x: headX, y: tailY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: inset.maxY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: tailY))
        }
        return path
    }

    private static func append(to path: inout Path, type: NoteShapeType, in rect: CGRect) {
        switch type {
        case .rectangle:
            path.addRect(rect.insetBy(dx: 1.5, dy: 1.5))
        case .circle:
            path.addEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))
        case .triangle:
            let inset = rect.insetBy(dx: 2, dy: 2)
            path.move(to: CGPoint(x: inset.midX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            path.closeSubpath()
        case .diamond:
            let inset = rect.insetBy(dx: 2, dy: 2)
            path.move(to: CGPoint(x: inset.midX, y: inset.minY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX, y: inset.midY))
            path.closeSubpath()
        case .line:
            path.move(to: CGPoint(x: rect.minX + 4, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
        case .arrow:
            let inset = rect.insetBy(dx: 4, dy: 4)
            let tailY = inset.midY
            let headX = inset.maxX
            let tailX = inset.minX
            path.move(to: CGPoint(x: tailX, y: tailY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: tailY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: inset.minY))
            path.addLine(to: CGPoint(x: headX, y: tailY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: inset.maxY))
            path.addLine(to: CGPoint(x: headX - inset.width * 0.22, y: tailY))
        }
    }

    private static func uiColorFromHex(_ hex: String?) -> UIColor? {
        guard let hex else { return nil }
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }
}
