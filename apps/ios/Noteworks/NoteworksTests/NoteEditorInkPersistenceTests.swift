//
//  NoteEditorInkPersistenceTests.swift
//  NoteworksTests
//
//  NoteEditorViewModel ink save / load / rotation / export through a
//  NotesStore on a temp directory. Covers CR-01 (save/load scale),
//  CR-07 (setDisplayPageWidth branches) and CR-11 (live-page export).
//

import CoreGraphics
import Foundation
import PencilKit
import Testing
import UIKit
@testable import Noteworks

@MainActor
@Suite(.serialized)
struct NoteEditorInkPersistenceTests {

    /// A stroke in display coordinates on a portrait-width page.
    private let displayStroke = InkTest.drawing(from: CGPoint(x: 120, y: 160), to: CGPoint(x: 520, y: 700))
    /// A second, separate stroke in display coordinates.
    private let secondStroke = InkTest.drawing(from: CGPoint(x: 60, y: 900), to: CGPoint(x: 400, y: 980))
    /// A stroke in canonical (612pt) coordinates.
    private let canonicalStroke = InkTest.drawing(from: CGPoint(x: 80, y: 100), to: CGPoint(x: 400, y: 520))

    // MARK: - CR-01: save / load scale

    @Test(arguments: [InkTest.portraitWidth, InkTest.landscapeWidth])
    func debouncedSaveWritesCanonicalInk(width: CGFloat) async throws {
        let fixture = InkStoreFixture()
        let viewModel = fixture.makeViewModel(reportingWidth: width)

        viewModel.simulateStroke(to: displayStroke, store: fixture.store)
        try await InkTest.waitForDebouncedSave()

        let stored = try #require(fixture.storedDrawing())
        #expect(InkTest.matches(stored, displayStroke, scaledBy: PageInkSpace.canonicalWidth / width))
    }

    @Test func saveAtCanonicalWidthIsIdentity() async throws {
        let fixture = InkStoreFixture()
        let viewModel = fixture.makeViewModel(reportingWidth: PageInkSpace.canonicalWidth)

        viewModel.simulateStroke(to: displayStroke, store: fixture.store)
        try await InkTest.waitForDebouncedSave()

        let stored = try #require(fixture.storedDrawing())
        #expect(InkTest.matches(stored, displayStroke))
        #expect(viewModel.canonicalLiveDrawing == viewModel.displayDrawing)
    }

    @Test(arguments: [InkTest.portraitWidth, InkTest.landscapeWidth])
    func loadScalesCanonicalInkToReportedWidth(width: CGFloat) {
        let fixture = InkStoreFixture()
        fixture.seed(canonicalStroke)

        let viewModel = fixture.makeViewModel(reportingWidth: width)

        #expect(InkTest.matches(viewModel.displayDrawing, canonicalStroke, scaledBy: width / PageInkSpace.canonicalWidth))
        #expect(InkTest.matches(viewModel.canonicalLiveDrawing, canonicalStroke))
    }

    @Test func savedInPortraitReloadsScaledInLandscape() async throws {
        let fixture = InkStoreFixture()
        let portrait = fixture.makeViewModel(reportingWidth: InkTest.portraitWidth)
        portrait.simulateStroke(to: displayStroke, store: fixture.store)
        try await InkTest.waitForDebouncedSave()
        fixture.flushWrites()

        let landscape = fixture.makeViewModel(reportingWidth: InkTest.landscapeWidth)

        #expect(InkTest.matches(
            landscape.displayDrawing, displayStroke,
            scaledBy: InkTest.landscapeWidth / InkTest.portraitWidth
        ))
    }

    // MARK: - CR-07: setDisplayPageWidth branches

    @Test func widthReportedBeforeAttachScalesTheLoad() {
        let fixture = InkStoreFixture()
        fixture.seed(canonicalStroke)

        let viewModel = NoteEditorViewModel()
        viewModel.setDisplayPageWidth(InkTest.portraitWidth)   // before attach: remembered only
        #expect(viewModel.displayDrawing.strokes.isEmpty)
        viewModel.attach(store: fixture.store, noteId: fixture.noteId)

        #expect(InkTest.matches(
            viewModel.displayDrawing, canonicalStroke,
            scaledBy: InkTest.portraitWidth / PageInkSpace.canonicalWidth
        ))
    }

    @Test func loadWithoutReportedWidthStaysCanonicalUntilWidthArrives() {
        let fixture = InkStoreFixture()
        fixture.seed(canonicalStroke)

        let viewModel = fixture.makeViewModel(reportingWidth: nil)
        #expect(InkTest.matches(viewModel.displayDrawing, canonicalStroke))

        viewModel.setDisplayPageWidth(InkTest.portraitWidth)
        #expect(InkTest.matches(
            viewModel.displayDrawing, canonicalStroke,
            scaledBy: InkTest.portraitWidth / PageInkSpace.canonicalWidth
        ))
        #expect(InkTest.matches(viewModel.canonicalLiveDrawing, canonicalStroke))
    }

    @Test(arguments: [CGFloat(0), -10, InkTest.portraitWidth + 0.4, InkTest.portraitWidth - 0.4])
    func zeroNegativeOrSubHalfPointWidthLeavesDrawingUnchanged(width: CGFloat) async throws {
        let fixture = InkStoreFixture()
        let viewModel = fixture.makeViewModel(reportingWidth: InkTest.portraitWidth)
        viewModel.simulateStroke(to: displayStroke, store: fixture.store)
        let pushGeneration = viewModel.drawingPushGeneration
        let canonicalBefore = viewModel.canonicalLiveDrawing

        viewModel.setDisplayPageWidth(width)

        #expect(viewModel.displayDrawing == displayStroke)
        #expect(viewModel.drawingPushGeneration == pushGeneration)
        #expect(InkTest.matches(viewModel.canonicalLiveDrawing, canonicalBefore))
        // The pending debounced save is not cancelled or re-flagged.
        try await InkTest.waitForDebouncedSave()
        let stored = try #require(fixture.storedDrawing())
        #expect(InkTest.matches(stored, canonicalBefore))
    }

    @Test func rotationWithPendingSavePersistsLastStrokeAtCanonicalScale() async throws {
        let fixture = InkStoreFixture()
        let viewModel = fixture.makeViewModel(reportingWidth: InkTest.portraitWidth)

        // Stroke lands; its debounced save is still pending when we rotate.
        viewModel.simulateStroke(to: displayStroke, store: fixture.store)
        viewModel.setDisplayPageWidth(InkTest.landscapeWidth)

        let toCanonical = PageInkSpace.canonicalWidth / InkTest.portraitWidth
        let stored = try #require(fixture.storedDrawing())
        #expect(InkTest.matches(stored, displayStroke, scaledBy: toCanonical))

        let toLandscape = InkTest.landscapeWidth / InkTest.portraitWidth
        #expect(InkTest.matches(viewModel.displayDrawing, displayStroke, scaledBy: toLandscape))
        #expect(InkTest.matches(viewModel.canonicalLiveDrawing, displayStroke, scaledBy: toCanonical))

        // The cancelled debounce must not later overwrite the flushed save.
        try await InkTest.waitForDebouncedSave()
        let storedLater = try #require(fixture.storedDrawing())
        #expect(InkTest.matches(storedLater, displayStroke, scaledBy: toCanonical))
    }

    @Test func rotationSkipsPersistingItsOwnAssignmentOnce() async throws {
        let fixture = InkStoreFixture()
        let viewModel = fixture.makeViewModel(reportingWidth: InkTest.portraitWidth)
        viewModel.simulateStroke(to: displayStroke, store: fixture.store)
        viewModel.setDisplayPageWidth(InkTest.landscapeWidth)
        let flushed = try #require(fixture.storedDrawing())

        // The first change after rotation is the rotation's own assignment
        // echoing back: it must not be persisted.
        viewModel.displayDrawing = InkTest.appending(secondStroke, to: viewModel.displayDrawing)
        viewModel.handleDrawingChange()
        try await InkTest.waitForDebouncedSave()
        let afterSkip = try #require(fixture.storedDrawing())
        #expect(afterSkip.strokes.count == flushed.strokes.count)
        #expect(InkTest.matches(afterSkip, flushed))

        // The next change is persisted normally, in canonical space.
        viewModel.handleDrawingChange()
        try await InkTest.waitForDebouncedSave()
        let afterSave = try #require(fixture.storedDrawing())
        #expect(afterSave.strokes.count == 2)
        #expect(InkTest.matches(afterSave, viewModel.canonicalLiveDrawing))
    }

    @Test func rotationRescalesUndoAndRedoInsteadOfClearing() async throws {
        let fixture = InkStoreFixture()
        let portrait = InkTest.portraitWidth
        let landscape = InkTest.landscapeWidth
        let factor = landscape / portrait
        let viewModel = fixture.makeViewModel(reportingWidth: portrait)

        let oneStroke = displayStroke
        let twoStrokes = InkTest.appending(secondStroke, to: displayStroke)
        viewModel.simulateStroke(to: oneStroke, store: fixture.store)
        viewModel.simulateStroke(to: twoStrokes, store: fixture.store)
        #expect(viewModel.canUndoPageEdit)

        viewModel.setDisplayPageWidth(landscape)

        // History survives rotation.
        #expect(viewModel.canUndoPageEdit)

        // Undo restores the one-stroke snapshot, rescaled to landscape.
        #expect(viewModel.undoPageEdit(store: fixture.store, canvas: nil))
        #expect(viewModel.displayDrawing.strokes.count == 1)
        #expect(InkTest.matches(viewModel.displayDrawing, oneStroke, scaledBy: factor))
        #expect(InkTest.matches(
            viewModel.canonicalLiveDrawing, oneStroke,
            scaledBy: PageInkSpace.canonicalWidth / portrait
        ))
        #expect(viewModel.canRedoPageEdit)

        // Rotate back with the redo entry pending: redo comes back in portrait.
        viewModel.setDisplayPageWidth(portrait)
        #expect(viewModel.canRedoPageEdit)
        #expect(viewModel.redoPageEdit(store: fixture.store, canvas: nil))
        #expect(viewModel.displayDrawing.strokes.count == 2)
        #expect(InkTest.matches(viewModel.displayDrawing, twoStrokes))
    }

    // MARK: - CR-11: canonical live drawing vs. saved / exported pages

    @Test(arguments: [InkTest.portraitWidth, InkTest.landscapeWidth])
    func canonicalLiveDrawingEqualsWhatFlushWrites(width: CGFloat) throws {
        let fixture = InkStoreFixture()
        let viewModel = fixture.makeViewModel(reportingWidth: width)
        viewModel.simulateStroke(to: displayStroke, store: fixture.store)
        let live = viewModel.canonicalLiveDrawing

        // Leaving the note flushes the pending save synchronously.
        viewModel.switchActiveNote(nil)

        let stored = try #require(fixture.storedDrawing())
        #expect(InkTest.matches(stored, live, tolerance: 0.0001))
    }

    @Test func exportedLivePageMatchesStoredPageScale() throws {
        let fixture = InkStoreFixture()
        fixture.seed(canonicalStroke, page: 1)
        let width = InkTest.landscapeWidth
        let viewModel = fixture.makeViewModel(reportingWidth: width)

        // Page 2 is live; draw the same ink in display space there.
        viewModel.addPage()
        viewModel.handleDrawingChange()   // consume the page-load echo
        #expect(viewModel.currentPage == 2)
        let liveDisplay = PageInkSpace.fromCanonical(canonicalStroke, toDisplayWidth: width)
        viewModel.simulateStroke(to: liveDisplay, store: fixture.store)

        let storedPage1 = try #require(fixture.storedDrawing(page: 1))
        #expect(InkTest.matches(viewModel.canonicalLiveDrawing, storedPage1))

        // PDF export: the live page renders like the stored page.
        let note = try #require(fixture.store.note(id: fixture.noteId))
        #expect(note.pageSettings.count == 2)
        let pdf = viewModel.exportPDFLocally(store: fixture.store)
        let document = try #require(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
        #expect(document.numberOfPages == 2)
        let page1 = try #require(PDFPixels.render(document, page: 1))
        let page2 = try #require(PDFPixels.render(document, page: 2))
        #expect(page1.inkPixelCount > 50, "stored page should contain ink")
        #expect(PDFPixels.differingFraction(page1, page2) < 0.002)

        // Thumbnails: the live page renders like the stored page.
        let size = CGSize(width: 153, height: 198)
        let thumb1 = try #require(PDFStorageService.shared.renderPageImage(
            note: note, store: fixture.store, pageNumber: 1,
            livePage: 2, liveDrawing: viewModel.canonicalLiveDrawing, targetSize: size
        ))
        let thumb2 = try #require(PDFStorageService.shared.renderPageImage(
            note: note, store: fixture.store, pageNumber: 2,
            livePage: 2, liveDrawing: viewModel.canonicalLiveDrawing, targetSize: size
        ))
        let pixels1 = try #require(PDFPixels.render(thumb1, size: size))
        let pixels2 = try #require(PDFPixels.render(thumb2, size: size))
        #expect(pixels1.inkPixelCount > 10)
        #expect(PDFPixels.differingFraction(pixels1, pixels2) < 0.005)
    }
}

// MARK: - Pixel helpers

/// RGBA8 rasters for comparing rendered pages.
struct PDFPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// Pixels that are clearly dark (ink, not page fill).
    var inkPixelCount: Int {
        stride(from: 0, to: bytes.count, by: 4).reduce(0) { count, i in
            let luminance = (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
            return luminance < 100 ? count + 1 : count
        }
    }

    static func render(_ document: CGPDFDocument, page number: Int) -> PDFPixels? {
        guard let page = document.page(at: number) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        return draw(size: box.size) { context in
            context.drawPDFPage(page)
        }
    }

    static func render(_ image: UIImage, size: CGSize) -> PDFPixels? {
        guard let cgImage = image.cgImage else { return nil }
        return draw(size: size) { context in
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
    }

    private static func draw(size: CGSize, _ body: (CGContext) -> Void) -> PDFPixels? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            body(context)
            return true
        }
        return drawn ? PDFPixels(width: width, height: height, bytes: bytes) : nil
    }

    /// Fraction of pixels whose channels differ by more than 32.
    static func differingFraction(_ a: PDFPixels, _ b: PDFPixels) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        var differing = 0
        for i in stride(from: 0, to: a.bytes.count, by: 4) {
            for c in 0..<3 where abs(Int(a.bytes[i + c]) - Int(b.bytes[i + c])) > 32 {
                differing += 1
                break
            }
        }
        return Double(differing) / Double(a.width * a.height)
    }
}
