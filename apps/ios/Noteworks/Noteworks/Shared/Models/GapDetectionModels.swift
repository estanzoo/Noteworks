//
//  GapDetectionModels.swift
//  Noteworks
//
//  Peer-note sources from community NOTE posts and optional class materials
//  uploaded during Gap Detection configuration.
//

import Foundation
import UIKit

/// A PDF note attached to a community NOTE post, surfaced as a Gap Detection peer source.
struct GapCommunityPeerSource: Identifiable, Equatable {
    let id: String
    let postId: String
    let attachment: PostAttachment
    let postTitle: String
    let authorName: String
    let authorSchool: String?
    let courseId: String?
    let createdAt: Date

    var displayTitle: String {
        let noteTitle = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !noteTitle.isEmpty { return noteTitle }
        let post = postTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !post.isEmpty { return post }
        return "Untitled Note"
    }

    var pdfFilename: String {
        let name = attachment.pdfFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return "\(displayTitle).pdf"
    }

    static func makeId(postId: String, noteId: String) -> String {
        "\(postId)-\(noteId)"
    }
}

/// A user-uploaded document or image attached as optional Gap Detection context.
struct GapClassMaterial: Identifiable, Equatable {
    let id: String
    let filename: String
    let data: Data
    let isPDF: Bool

    var kindLabel: String {
        isPDF ? "PDF document" : "Image"
    }

    func pdfDataForComparison(maxBytes: Int = 16 * 1024 * 1024) throws -> Data {
        let pdf = isPDF ? data : (Self.imageDataToPDF(data) ?? Data())
        guard !pdf.isEmpty else {
            throw APIError.badRequest("Could not convert \(filename) to PDF.")
        }
        guard pdf.count <= maxBytes else {
            throw APIError.badRequest("\(filename) is larger than 16 MB.")
        }
        return pdf
    }

    static func imageDataToPDF(_ imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let pageWidth: CGFloat = 612
        let aspect = max(image.size.height / max(image.size.width, 1), 1.4)
        let pageSize = CGSize(width: pageWidth, height: pageWidth * aspect)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            let iw = image.size.width
            let ih = image.size.height
            guard iw > 0, ih > 0 else { return }
            let scale = min(pageSize.width / iw, pageSize.height / ih)
            let width = iw * scale
            let height = ih * scale
            let origin = CGPoint(
                x: (pageSize.width - width) / 2,
                y: (pageSize.height - height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: CGSize(width: width, height: height)))
        }
    }
}
