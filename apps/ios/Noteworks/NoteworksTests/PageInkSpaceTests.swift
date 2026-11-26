//
//  PageInkSpaceTests.swift
//  NoteworksTests
//
//  Unit tests for the canonical ↔ display ink conversions (CR-01).
//

import CoreGraphics
import PencilKit
import Testing
@testable import Noteworks

struct PageInkSpaceTests {

    private let sample = InkTest.drawing(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 450))

    @Test func canonicalWidthIsThePDFPageWidth() {
        #expect(PageInkSpace.canonicalWidth == 612)
        #expect(PageInkSpace.canonicalWidth == PDFStorageService.pdfLogicalPageSize.width)
    }

    @Test(arguments: [InkTest.portraitWidth, InkTest.landscapeWidth])
    func displayToCanonicalRoundTrip(width: CGFloat) {
        let canonical = PageInkSpace.toCanonical(sample, fromDisplayWidth: width)
        let back = PageInkSpace.fromCanonical(canonical, toDisplayWidth: width)
        #expect(InkTest.matches(back, sample))
    }

    @Test func identityAtCanonicalWidth() {
        let width = PageInkSpace.canonicalWidth
        #expect(PageInkSpace.scaleFactor(fromWidth: width, toWidth: width) == nil)
        #expect(PageInkSpace.toCanonical(sample, fromDisplayWidth: width) == sample)
        #expect(PageInkSpace.fromCanonical(sample, toDisplayWidth: width) == sample)
    }

    @Test func nonPositiveWidthReturnsInputUnchanged() {
        #expect(PageInkSpace.scaleFactor(fromWidth: 0, toWidth: 800) == nil)
        #expect(PageInkSpace.scaleFactor(fromWidth: 800, toWidth: -1) == nil)
        #expect(PageInkSpace.toCanonical(sample, fromDisplayWidth: 0) == sample)
        #expect(PageInkSpace.fromCanonical(sample, toDisplayWidth: 0) == sample)
    }

    @Test func factorWithinToleranceOfOneIsIdentity() {
        #expect(PageInkSpace.scaleFactor(fromWidth: 800, toWidth: 800.00001) == nil)
        #expect(PageInkSpace.scaleFactor(fromWidth: 800, toWidth: 801) != nil)
    }

    @Test(arguments: [InkTest.portraitWidth, InkTest.landscapeWidth])
    func canonicalFactorsForPortraitAndLandscape(width: CGFloat) throws {
        let toCanonical = try #require(PageInkSpace.scaleFactor(fromWidth: width, toWidth: PageInkSpace.canonicalWidth))
        let toDisplay = try #require(PageInkSpace.scaleFactor(fromWidth: PageInkSpace.canonicalWidth, toWidth: width))
        #expect(abs(toCanonical - 612 / width) < 1e-9)
        #expect(abs(toDisplay - width / 612) < 1e-9)

        let canonical = PageInkSpace.toCanonical(sample, fromDisplayWidth: width)
        #expect(InkTest.matches(canonical, sample, scaledBy: 612 / width))
        let display = PageInkSpace.fromCanonical(sample, toDisplayWidth: width)
        #expect(InkTest.matches(display, sample, scaledBy: width / 612))
    }

    @Test func portraitToLandscapeRescaleMatchesPathThroughCanonical() {
        let portrait = InkTest.portraitWidth
        let landscape = InkTest.landscapeWidth
        let direct = PageInkSpace.rescale(sample, fromWidth: portrait, toWidth: landscape)
        let viaCanonical = PageInkSpace.fromCanonical(
            PageInkSpace.toCanonical(sample, fromDisplayWidth: portrait),
            toDisplayWidth: landscape
        )
        #expect(InkTest.matches(direct, sample, scaledBy: landscape / portrait))
        #expect(InkTest.matches(direct, viaCanonical))
    }
}
