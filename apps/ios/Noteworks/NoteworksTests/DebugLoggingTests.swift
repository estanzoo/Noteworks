//
//  DebugLoggingTests.swift
//  NoteworksTests
//
//  Covers the editor debug log channels: both ship disabled (CR-12), a
//  disabled channel never evaluates its message, and both share one
//  formatter (CR-16).
//

import Testing
import UIKit
@testable import Noteworks

@MainActor
struct DebugLoggingTests {

    @Test func debugChannelsDefaultToDisabled() {
        #expect(InkCanvasDebug.isEnabled == false)
        #expect(PageZoomDebug.isEnabled == false)
    }

    @Test func disabledChannelsDoNotBuildMessages() {
        var evaluated = false
        func message() -> String { evaluated = true; return "x" }
        InkCanvasDebug.log(message())
        PageZoomDebug.zoom(message())
        #expect(evaluated == false)
    }

    @Test func sharedFormatterUsesTwoDecimals() {
        #expect(DebugFormat.fmt(CGFloat(1.234)) == "1.23")
        #expect(InkCanvasDebug.fmt(1.5) == DebugFormat.fmt(CGFloat(1.5)))
        #expect(DebugFormat.fmt(CGRect(x: 1, y: 2, width: 3, height: 4))
                == "[(1.00,2.00) (3.00x4.00)]")
    }
}
