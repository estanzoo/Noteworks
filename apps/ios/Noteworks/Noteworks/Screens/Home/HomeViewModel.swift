//
//  HomeViewModel.swift
//  Noteworks
//
//  Layout helper for the home bubble field. The source of truth for
//  bubble names + notes lives in `NotesStore`; this file turns that
//  into laid-out `CourseBubble`s with:
//
//  - **Size proportional to note count**, clamped between a minimum
//    (readable) and a maximum (never dominates the screen).
//  - **Non-overlapping positions** — a deterministic packer places the
//    biggest bubble first and resolves collisions by spiraling outward
//    from each bubble's preferred slot.
//

import Foundation
import CoreGraphics

enum HomeBubbleLayout {

    // MARK: - Tuning

    /// Smallest a bubble ever shrinks to. Below this the title + note
    /// count stop being readable, so a bubble with 0 notes still renders
    /// at this size.
    private static let minBubbleSize: CGFloat = 110

    /// Largest a bubble can ever grow to in absolute points. We additionally
    /// cap to a fraction of the container width inside `bubbles(from:in:)`
    /// so on a phone-sized canvas the largest bubble never eats the whole
    /// screen.
    private static let maxBubbleSize: CGFloat = 210

    /// Fraction of the container's shorter edge that the biggest bubble
    /// is allowed to take up. Keeps small canvases sane.
    private static let maxBubbleFraction: CGFloat = 0.36

    /// Empty gap kept between bubble edges during packing.
    private static let packingPadding: CGFloat = 16

    /// Inset from the container edges so bubbles don't kiss the screen
    /// border or run under the title row / FAB.
    private static let edgeInset: CGFloat = 12

    // MARK: - Public

    /// Builds the on-screen bubble list. Pass the container size from a
    /// `GeometryReader` so the packer knows how much room it has.
    @MainActor
    static func bubbles(from store: NotesStore, in containerSize: CGSize) -> [CourseBubble] {
        var names = store.bubbleNames
        if store.hasUnnamedNotes,
           !names.contains(where: { $0.caseInsensitiveCompare("Unnamed") == .orderedSame }) {
            names.append("Unnamed")
        }

        struct Raw { let name: String; let noteCount: Int }
        let raws = names.map { Raw(name: $0, noteCount: store.noteCount(for: $0)) }

        guard !raws.isEmpty, containerSize.width > 0, containerSize.height > 0 else { return [] }

        // Cap the upper bound so the biggest bubble never dominates a
        // narrow container. On a wide iPad this falls back to `maxBubbleSize`.
        let dynamicMax = min(
            maxBubbleSize,
            min(containerSize.width, containerSize.height) * maxBubbleFraction
        )
        let effectiveMax = max(minBubbleSize + 10, dynamicMax)

        // Relative scaling: the bubble with the most notes hits the cap,
        // others scale proportionally. `sqrt` keeps mid-range bubbles from
        // feeling dwarfed by the leader (a bubble with 25% of max notes
        // ends up at 50% of the delta, not 25%).
        let maxNotes = max(1, raws.map(\.noteCount).max() ?? 1)
        let sized: [(name: String, noteCount: Int, size: CGFloat)] = raws.map { raw in
            let t = sqrt(Double(raw.noteCount) / Double(maxNotes))
            let size = minBubbleSize + CGFloat(t) * (effectiveMax - minBubbleSize)
            return (raw.name, raw.noteCount, size.rounded())
        }

        // Place the biggest bubbles first so they claim the center; smaller
        // ones fill in around them. Within equal sizes we sort by name so
        // the layout stays deterministic across launches.
        let placeOrder = sized.enumerated().sorted { lhs, rhs in
            if lhs.element.size != rhs.element.size { return lhs.element.size > rhs.element.size }
            return lhs.element.name < rhs.element.name
        }

        struct Placed { let center: CGPoint; let radius: CGFloat }
        var placed: [Placed] = []
        var positions: [String: CGPoint] = [:]

        for entry in placeOrder {
            let bubble = entry.element
            let radius = bubble.size / 2
            let center = findSpot(
                name: bubble.name,
                radius: radius,
                placed: placed,
                container: containerSize
            )
            placed.append(Placed(center: center, radius: radius))
            positions[bubble.name] = center
        }

        // Re-emit in the original order (so SwiftUI's ForEach stays stable
        // against the bubble list, not the placement order) with the
        // packed centers converted back to fractional offsets.
        return sized.map { s in
            let center = positions[s.name] ?? CGPoint(
                x: containerSize.width / 2,
                y: containerSize.height / 2
            )
            return CourseBubble(
                name: s.name,
                noteCount: s.noteCount,
                size: s.size,
                offsetX: (center.x - containerSize.width / 2) / containerSize.width,
                offsetY: (center.y - containerSize.height / 2) / containerSize.height
            )
        }
    }

    // MARK: - Packing

    /// Finds a non-overlapping center for a bubble of `radius`. Starts
    /// from a hash-derived preferred position so re-renders don't shuffle
    /// the field; if that spot collides, spirals outward through evenly
    /// spaced angles until a free slot is found.
    private static func findSpot(
        name: String,
        radius: CGFloat,
        placed: [(center: CGPoint, radius: CGFloat)],
        container: CGSize
    ) -> CGPoint {
        let seed = stableHash(name)
        let minX = edgeInset + radius
        let maxX = container.width - edgeInset - radius
        let minY = edgeInset + radius
        let maxY = container.height - edgeInset - radius

        // Degenerate container — return center as a safe fallback.
        guard maxX > minX, maxY > minY else {
            return CGPoint(x: container.width / 2, y: container.height / 2)
        }

        let preferred = preferredPosition(seed: seed, radius: radius, container: container)

        if !overlaps(preferred, radius: radius, placed: placed) {
            return preferred
        }

        // Spiral search anchored at the container center. Step size is a
        // little less than the smallest bubble diameter so we don't miss
        // gaps; angle count keeps the spiral dense enough to find a slot
        // even on a crowded canvas.
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        let maxReach = hypot(maxX - minX, maxY - minY)
        let radialStep: CGFloat = max(8, minBubbleSize * 0.35)
        let anglesPerRing = 18

        // Bias the starting angle by the seed so different bubbles try
        // different sweeps before settling.
        let angleOffset = Double(seed % 1000) / 1000.0 * 2 * .pi

        var currentReach: CGFloat = max(radius * 0.8, radialStep)
        while currentReach <= maxReach {
            for i in 0..<anglesPerRing {
                let theta = angleOffset + (Double(i) / Double(anglesPerRing)) * 2 * .pi
                var candidate = CGPoint(
                    x: center.x + cos(theta) * currentReach,
                    y: center.y + sin(theta) * currentReach
                )
                candidate.x = min(max(candidate.x, minX), maxX)
                candidate.y = min(max(candidate.y, minY), maxY)
                if !overlaps(candidate, radius: radius, placed: placed) {
                    return candidate
                }
            }
            currentReach += radialStep
        }

        // Fully crowded canvas — fall back to the clamped preferred spot.
        // Some overlap is preferable to placing the bubble off-screen.
        return CGPoint(
            x: min(max(preferred.x, minX), maxX),
            y: min(max(preferred.y, minY), maxY)
        )
    }

    /// Preferred center derived from the bubble's name, biased toward a
    /// constellation pattern around the container's center. The result
    /// is already clamped to the legal region.
    private static func preferredPosition(seed: UInt64, radius: CGFloat, container: CGSize) -> CGPoint {
        let minX = edgeInset + radius
        let maxX = container.width - edgeInset - radius
        let minY = edgeInset + radius
        let maxY = container.height - edgeInset - radius

        let usableWidth = max(0, maxX - minX)
        let usableHeight = max(0, maxY - minY)

        // Bias toward the middle 80% of the canvas — the biggest bubble
        // (placed first) almost always grabs a near-center spot, smaller
        // ones radiate outward via the spiral search.
        let fx = (Double(seed % 800) / 1000.0) + 0.10   // 0.10 – 0.90
        let fy = (Double((seed / 800) % 800) / 1000.0) + 0.10
        return CGPoint(
            x: minX + CGFloat(fx) * usableWidth,
            y: minY + CGFloat(fy) * usableHeight
        )
    }

    private static func overlaps(
        _ center: CGPoint,
        radius: CGFloat,
        placed: [(center: CGPoint, radius: CGFloat)]
    ) -> Bool {
        for p in placed {
            let dx = p.center.x - center.x
            let dy = p.center.y - center.y
            let dist = sqrt(dx * dx + dy * dy)
            // `packingPadding` guarantees a visible gap between any two
            // bubbles even when they're packed tight.
            let minDist = radius + p.radius + packingPadding
            if dist < minDist { return true }
        }
        return false
    }

    /// djb2 — stable across processes (Swift's `hash(into:)` is not).
    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for byte in s.utf8 {
            h = (h &* 33) &+ UInt64(byte)
        }
        return h
    }
}
