//
//  HomeViewModel.swift
//  Noteworks
//
//  Thin layout helper for the home bubble field. The actual source of truth
//  for bubbles + notes lives in `NotesStore`; this struct is purely about
//  turning bubble names into laid-out `CourseBubble`s with deterministic
//  positions and live note counts.
//

import Foundation
import CoreGraphics

enum HomeBubbleLayout {

    /// Hand-tuned layouts for the seeded "default" bubbles so the home field
    /// keeps its designed look. Anything outside this dictionary falls back
    /// to a deterministic hash-based slot.
    private static let presetSlots: [String: BubbleSlot] = [
        "biology":     BubbleSlot(size: 160, offsetX: -0.25, offsetY: -0.25),
        "art":         BubbleSlot(size: 140, offsetX:  0.10, offsetY: -0.28),
        "physics":     BubbleSlot(size: 130, offsetX:  0.38, offsetY: -0.20),
        "chemistry":   BubbleSlot(size: 150, offsetX:  0.05, offsetY:  0.08),
        "unnamed":     BubbleSlot(size: 170, offsetX: -0.38, offsetY:  0.12),
        "uncategorized": BubbleSlot(size: 170, offsetX: -0.38, offsetY:  0.12),
        "mathematics": BubbleSlot(size: 165, offsetX:  0.30, offsetY:  0.15),
    ]

    /// Builds the on-screen bubble list from the store's bubble names plus
    /// an auto-Unnamed bubble whenever any note has no subject (mirrors JSX
    /// L1426–L1435 where notes without `subject` roll into "Unnamed").
    @MainActor
    static func bubbles(from store: NotesStore) -> [CourseBubble] {
        var names = store.bubbleNames
        if store.hasUnnamedNotes,
           !names.contains(where: { $0.caseInsensitiveCompare("Unnamed") == .orderedSame }) {
            names.append("Unnamed")
        }

        return names.map { name in
            let slot = slotFor(name: name)
            return CourseBubble(
                name: name,
                noteCount: store.noteCount(for: name),
                size: slot.size,
                offsetX: slot.offsetX,
                offsetY: slot.offsetY
            )
        }
    }

    private static func slotFor(name: String) -> BubbleSlot {
        if let preset = presetSlots[name.lowercased()] {
            return preset
        }
        // Deterministic fall-back so a freshly-created bubble keeps the same
        // position across launches without needing to persist coordinates.
        let h = stableHash(name)
        let size = CGFloat(130 + Int(h % 50))             // 130 – 179
        let offsetX = CGFloat(Int(h / 50 % 700)) / 1000.0 - 0.35   // -0.35 – 0.35
        let offsetY = CGFloat(Int(h / 35000 % 550)) / 1000.0 - 0.275 // -0.275 – 0.275
        return BubbleSlot(size: size, offsetX: offsetX, offsetY: offsetY)
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

private struct BubbleSlot {
    let size: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
}
