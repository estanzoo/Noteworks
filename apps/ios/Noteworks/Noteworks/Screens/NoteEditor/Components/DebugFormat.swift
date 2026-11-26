//
//  DebugFormat.swift
//  Noteworks
//
//  Shared geometry formatter for the editor's debug log channels
//  (`InkCanvasDebug`, `PageZoomDebug`) so both print at the same
//  precision. Only call it from inside a log message autoclosure so the
//  formatting never runs while logging is disabled.
//

import UIKit

enum DebugFormat {
    static func fmt(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    static func fmt(_ p: CGPoint) -> String { "(\(fmt(p.x)),\(fmt(p.y)))" }
    static func fmt(_ s: CGSize) -> String { "(\(fmt(s.width))x\(fmt(s.height)))" }
    static func fmt(_ i: UIEdgeInsets) -> String {
        "(t:\(fmt(i.top)) l:\(fmt(i.left)) b:\(fmt(i.bottom)) r:\(fmt(i.right)))"
    }
    static func fmt(_ r: CGRect) -> String { "[\(fmt(r.origin)) \(fmt(r.size))]" }
}
