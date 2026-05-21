//
//  HomeViewModel.swift
//  Noteworks
//
//  Layout helper for the home bubble field. The source of truth for
//  bubble names + notes lives in `NotesStore`; this file turns that
//  into laid-out `CourseBubble`s following the JSX mock at
//  `others/NoteWorks_UI 3/noteworks-library.jsx` (`placeBubbles`
//  L1460–L1510, `HomePage` L2179–L2278).
//
//  Recipe:
//  - **Order** by note count desc; Swift's `sorted` is stable, so ties
//    keep the user's bubble-list insertion order (which is the JSX
//    behaviour when explicit categories exist).
//  - **Size** proportional to note count between 170pt and 260pt, with
//    an empty-bubble base that depends on the total count so a screen
//    full of zero-note bubbles still feels balanced.
//  - **Position** from an art-directed slot table for 1–6 bubbles,
//    with a 12-slot fallback for 7+ that wraps via `index % slots`.
//  - **Uniform shrink-to-fit**: try the slot layout at scale 1.0; if
//    any pair collides, scale everyone down by 3.5% and retry until
//    they fit (or bottom out at 0.56). Replaces the old hash-spiral
//    packer that produced the "randomly scattered" look on iPad.
//

import Foundation
import CoreGraphics

enum HomeBubbleLayout {

    // MARK: - Tuning
    //
    // JSX uses linear scaling with `170 … 260` and a `112` floor. That
    // works for ~equal counts but collapses on iPad when one bubble
    // dominates the field — e.g. "Unnamed: 35 Notes" turns every other
    // bubble into the same near-minimum size (`Mathematics: 5 Notes`
    // ends up looking identical to `Physics: 1 Note`). We use `sqrt`
    // scaling instead so the size curve is steeper at the low end, and
    // raise the floor so even empty bubbles can render their label
    // ("Engineering" was truncating to "Engineeri…" at the old `88`
    // floor).
    //
    // Resulting feel: the leader still hits the max; mid-range bubbles
    // are clearly larger than empty ones; empty bubbles are visibly
    // smaller than any bubble with notes; nothing ever shrinks below a
    // size that can fit a 10-character course code.

    /// Smallest size a bubble with notes can ever request before the
    /// shrink-to-fit pass.
    private static let minSize: CGFloat = 160

    /// Largest size — the bubble with the most notes hits this.
    private static let maxSize: CGFloat = 280

    /// Absolute lower bound after the shrink pass. Tuned so the title
    /// label can render a typical course code ("Engineering",
    /// "Mathematics") without truncating to an ellipsis.
    private static let shrinkFloor: CGFloat = 115

    /// Note count at which a bubble hits `maxSize`. Decoupled from the
    /// observed maximum so a single outlier (e.g. 35 unnamed notes)
    /// can't compress every other bubble's curve into a near-flat
    /// region where 1 note and 2 notes render at the same size.
    private static let sizingReferenceCount: Int = 8

    /// JSX padding rule (L1461): tighter on narrow canvases, roomier
    /// on iPad-class widths.
    private static func packingPadding(for container: CGSize) -> CGFloat {
        min(container.width, container.height) < 520 ? 10 : 18
    }

    // MARK: - Slot tables (verbatim from JSX `slotSets` L1463–L1469)

    private struct Slot { let x: CGFloat; let y: CGFloat }

    private static let slotSets: [Int: [Slot]] = [
        1: [Slot(x: 0.50, y: 0.50)],
        // The JSX 2-bubble template is a desktop-card diagonal
        // (`[(0.40, 0.30), (0.60, 0.47)]`) that on a wide iPad canvas
        // reads as "one bubble in the upper-left, one in the lower-
        // right" rather than a centred pair. We use a symmetric
        // horizontal pair at the vertical middle so a freshly-
        // onboarded user sees their two course bubbles balanced at the
        // centre of the field.
        2: [Slot(x: 0.38, y: 0.50), Slot(x: 0.62, y: 0.50)],
        3: [Slot(x: 0.34, y: 0.30), Slot(x: 0.56, y: 0.30), Slot(x: 0.45, y: 0.52)],
        4: [
            Slot(x: 0.31, y: 0.29), Slot(x: 0.52, y: 0.29),
            Slot(x: 0.42, y: 0.51), Slot(x: 0.69, y: 0.43),
        ],
        5: [
            Slot(x: 0.28, y: 0.28), Slot(x: 0.49, y: 0.28), Slot(x: 0.68, y: 0.23),
            Slot(x: 0.39, y: 0.50), Slot(x: 0.58, y: 0.50),
        ],
        6: [
            Slot(x: 0.28, y: 0.28), Slot(x: 0.49, y: 0.28), Slot(x: 0.68, y: 0.23),
            Slot(x: 0.39, y: 0.50), Slot(x: 0.58, y: 0.50), Slot(x: 0.75, y: 0.42),
        ],
    ]

    /// JSX `defaultSlots` (L1470–L1478): the 6-slot template plus six
    /// outer positions for 7+ bubbles. Index wraps via `i % count` so
    /// bubbles 13+ reuse the same slots.
    private static let defaultSlots: [Slot] = (slotSets[6] ?? []) + [
        Slot(x: 0.22, y: 0.47),
        Slot(x: 0.47, y: 0.14),
        Slot(x: 0.70, y: 0.67),
        Slot(x: 0.20, y: 0.18),
        Slot(x: 0.88, y: 0.34),
        Slot(x: 0.36, y: 0.69),
    ]

    // MARK: - Public

    /// Builds the on-screen bubble list. Pass the container size from a
    /// `GeometryReader`; the slot table is fraction-based so the same
    /// layout reflows naturally across iPad sizes / split view / rotation.
    @MainActor
    static func bubbles(from store: NotesStore, in containerSize: CGSize) -> [CourseBubble] {
        var names = store.bubbleNames

        struct Raw { let name: String; let count: Int }
        let raws = names.map { Raw(name: $0, count: store.noteCount(for: $0)) }

        guard !raws.isEmpty,
              containerSize.width > 0, containerSize.height > 0
        else { return [] }

        // JSX L2191–L2194: sort by count desc. Swift's `sorted` is
        // stable, so ties retain `bubbleNames` insertion order — which
        // matches the JSX `hasExplicitCategories ? 0 : localeCompare`
        // branch for the explicit-categories case the iOS app always
        // hits (NotesStore.bubbleNames is the source of truth).
        let sortedRaws = raws.sorted { $0.count > $1.count }

        // Sizing — `sqrt` curve over `minSize…maxSize`, normalised to a
        // capped reference count instead of the raw `maxCount`.
        //
        // Why the cap: with a real maxCount like 35 ("Unnamed: 35
        // Notes"), `sqrt(1/35)` and `sqrt(2/35)` differ by ~7% of the
        // size range, so a 1-note bubble and a 2-note bubble look
        // identical. Capping at `sizingReferenceCount = 8` stretches
        // the visible curve over the realistic 1–8 note range, making
        // each additional note clearly noticeable. Any bubble at or
        // above the cap hits `maxSize`, so the "lots of notes" cue is
        // preserved without per-count fidelity at the top end.
        let actualMaxCount = max(1, sortedRaws.map(\.count).max() ?? 1)
        let referenceMax = max(1, min(actualMaxCount, sizingReferenceCount))
        let emptyBase: CGFloat = {
            switch sortedRaws.count {
            case ...1: return 200
            case ...4: return 180
            case ...6: return 160
            default:   return 140
            }
        }()

        let sized: [Sized] = sortedRaws.map { raw in
            let size: CGFloat
            if raw.count > 0 {
                let normalised = min(1.0, Double(raw.count) / Double(referenceMax))
                let ratio = sqrt(normalised)
                size = (minSize + CGFloat(ratio) * (maxSize - minSize)).rounded()
            } else {
                size = emptyBase
            }
            return Sized(name: raw.name, count: raw.count, size: size)
        }

        let slotPlaced = placeBubbles(sized, in: containerSize)

        // The JSX slot table biases the cluster toward the top of the
        // field (`y` fractions sit between 0.23 and 0.52). On iPad the
        // remaining lower half feels wasted, so shift the whole cluster
        // down until the empty space above ≈ the empty space below.
        // Bounds-checked so no bubble ever crosses the inset.
        let centered = verticallyCenter(slotPlaced, in: containerSize)

        // Manual override: if the user has dragged a bubble in edit
        // mode, honour the saved fractional offset *exactly* — no
        // collision adjustment, no padding push. This mirrors the iOS
        // Home Screen drag-and-drop feel: the icon stays at the spot
        // you let go of, never animates from "where you dropped" to
        // "where the layout would prefer".
        //
        // The non-overlap relaxation below still runs, but manually
        // placed bubbles are treated as immovable obstacles so the
        // *slot-placed* bubbles are the ones that yield. From the
        // user's perspective: whatever I drag stays put.
        var positionByName: [String: Placed] = [:]
        var pinned: Set<String> = []
        for p in centered { positionByName[p.name] = p }

        for p in centered {
            guard let bubble = store.bubble(named: p.name),
                  let mx = bubble.manualOffsetX,
                  let my = bubble.manualOffsetY
            else { continue }
            let r = p.size / 2
            // Clamp only to the container bounds (no padding) so the
            // bubble lands exactly where the finger left it; the drag
            // gesture already clamps to `r`-from-edge so this is just a
            // safety net for stored offsets from older container sizes.
            let minX = r, maxX = max(r, containerSize.width - r)
            let minY = r, maxY = max(r, containerSize.height - r)
            let x = min(maxX, max(minX, containerSize.width / 2 + CGFloat(mx) * containerSize.width))
            let y = min(maxY, max(minY, containerSize.height / 2 + CGFloat(my) * containerSize.height))
            positionByName[p.name] = Placed(
                name: p.name, count: p.count, size: p.size, x: x, y: y
            )
            pinned.insert(p.name)
        }

        // Relaxation pass: only the un-pinned (slot-placed) bubbles
        // move out of the way; manually placed bubbles are fixed
        // obstacles. Without `pinned`, this pass would slide a
        // just-dropped bubble off the finger's landing spot when its
        // requested position happens to overlap a slot bubble — that
        // post-drop drift was the "animation to a new position" the
        // user was seeing.
        positionByName = enforceNonOverlap(positionByName, in: containerSize, pinned: pinned)

        // Re-emit in `centered` order so the entrance stagger stays
        // tied to the sorted-by-count order from earlier.
        let finalPlaced: [Placed] = centered.map { positionByName[$0.name] ?? $0 }

        // Emit in sorted-by-count order so the entrance stagger in
        // `HomeView` runs biggest-bubble-first (mirrors JSX L2266 where
        // `placed.map((bubble, index))` uses the sorted index for delay).
        // SwiftUI keeps identity stable via `CourseBubble.id` (case-folded
        // name), so reorder is a cross-fade, not a wipe.
        return finalPlaced.map { p in
            CourseBubble(
                name: p.name,
                noteCount: p.count,
                size: p.size,
                offsetX: (p.x - containerSize.width / 2) / containerSize.width,
                offsetY: (p.y - containerSize.height / 2) / containerSize.height
            )
        }
    }

    // MARK: - Collision avoidance

    /// One bubble treated as an obstacle for the collision resolver.
    struct Obstacle {
        let center: CGPoint
        let radius: CGFloat
    }

    /// Live drag-time resolver used by `HomeBubbleCell`. Given where
    /// the user's finger wants the bubble to be, returns the closest
    /// non-overlapping centre considering every other rendered bubble.
    /// The result is also clamped to the container's padded bounds so
    /// the bubble can never disappear off-screen.
    @MainActor
    static func resolveDragPosition(
        requestedCenter: CGPoint,
        radius: CGFloat,
        siblings: [CourseBubble],
        in container: CGSize
    ) -> CGPoint {
        let pad = packingPadding(for: container)
        let obstacles: [Obstacle] = siblings.map { sib in
            Obstacle(
                center: CGPoint(
                    x: container.width / 2 + sib.offsetX * container.width,
                    y: container.height / 2 + sib.offsetY * container.height
                ),
                radius: sib.size / 2
            )
        }
        return resolveCollision(
            requested: requestedCenter,
            radius: radius,
            obstacles: obstacles,
            padding: pad,
            bounds: container
        )
    }

    /// Whole-field relaxation pass. For every bubble, push it out of
    /// every other bubble using `resolveCollision`, looping until no
    /// bubble moves (or 6 iterations elapse, whichever first). Used as
    /// the final layout step so the rendered field can never overlap,
    /// even in pathological inputs where the shrink-to-fit pass had to
    /// fall back to its bottom scale.
    private static func enforceNonOverlap(
        _ placed: [String: Placed],
        in container: CGSize,
        pinned: Set<String> = []
    ) -> [String: Placed] {
        guard placed.count > 1 else { return placed }
        var result = placed
        let pad = packingPadding(for: container)
        // Stable iteration order so identical inputs converge to the
        // same output on every render.
        let names = result.keys.sorted { $0.lowercased() < $1.lowercased() }
        let maxIterations = 6
        for _ in 0..<maxIterations {
            var moved = false
            for name in names {
                // Manually-placed bubbles stay exactly where the user
                // dropped them; only auto-placed bubbles yield.
                if pinned.contains(name) { continue }
                guard let p = result[name] else { continue }
                let obstacles = result.values
                    .filter { $0.name != name }
                    .map { Obstacle(center: CGPoint(x: $0.x, y: $0.y), radius: $0.size / 2) }
                let resolved = resolveCollision(
                    requested: CGPoint(x: p.x, y: p.y),
                    radius: p.size / 2,
                    obstacles: obstacles,
                    padding: pad,
                    bounds: container
                )
                if abs(resolved.x - p.x) > 0.5 || abs(resolved.y - p.y) > 0.5 {
                    result[name] = Placed(
                        name: p.name, count: p.count, size: p.size,
                        x: resolved.x, y: resolved.y
                    )
                    moved = true
                }
            }
            if !moved { break }
        }
        return result
    }

    /// Iteratively pushes `requested` out of every obstacle until no
    /// overlaps remain (or we hit `maxIterations`, in which case the
    /// best-effort position is returned). Two overlapping obstacles
    /// resolve in a few passes because each push can re-introduce
    /// overlap with a neighbour; clamping is applied each iteration.
    private static func resolveCollision(
        requested: CGPoint,
        radius: CGFloat,
        obstacles: [Obstacle],
        padding: CGFloat,
        bounds container: CGSize
    ) -> CGPoint {
        let minX = padding + radius
        let maxX = max(minX, container.width - padding - radius)
        let minY = padding + radius
        let maxY = max(minY, container.height - padding - radius)

        var pos = CGPoint(
            x: min(maxX, max(minX, requested.x)),
            y: min(maxY, max(minY, requested.y))
        )
        guard !obstacles.isEmpty else { return pos }

        let maxIterations = 10
        for _ in 0..<maxIterations {
            var moved = false
            for obs in obstacles {
                let dx = pos.x - obs.center.x
                let dy = pos.y - obs.center.y
                let dist = sqrt(dx * dx + dy * dy)
                let minDist = radius + obs.radius + padding
                if dist + 0.5 < minDist {
                    if dist < 0.001 {
                        // Centres coincide — push out along an
                        // arbitrary axis (toward the container centre)
                        // so we have a defined direction.
                        let toCenterX = container.width / 2 - obs.center.x
                        let toCenterY = container.height / 2 - obs.center.y
                        let mag = max(0.001, sqrt(toCenterX * toCenterX + toCenterY * toCenterY))
                        pos.x = obs.center.x + (toCenterX / mag) * minDist
                        pos.y = obs.center.y + (toCenterY / mag) * minDist
                    } else {
                        let scale = minDist / dist
                        pos.x = obs.center.x + dx * scale
                        pos.y = obs.center.y + dy * scale
                    }
                    pos.x = min(maxX, max(minX, pos.x))
                    pos.y = min(maxY, max(minY, pos.y))
                    moved = true
                }
            }
            if !moved { break }
        }
        return pos
    }

    /// Shifts every bubble vertically so the empty space above the
    /// cluster matches the empty space below. Count-independent: works
    /// the same for 1, 5, or 10 bubbles. Clamped so the shift never
    /// pushes a bubble past the container's vertical inset.
    private static func verticallyCenter(_ placed: [Placed], in container: CGSize) -> [Placed] {
        guard !placed.isEmpty else { return placed }
        let pad = packingPadding(for: container)
        let topY = placed.map { $0.y - $0.size / 2 }.min() ?? 0
        let botY = placed.map { $0.y + $0.size / 2 }.max() ?? container.height
        let desired = ((container.height - botY) - topY) / 2
        let maxDown = max(0, container.height - pad - botY)
        let maxUp = max(0, topY - pad)
        let shift = max(-maxUp, min(maxDown, desired))
        guard abs(shift) > 0.5 else { return placed }
        return placed.map {
            Placed(name: $0.name, count: $0.count, size: $0.size, x: $0.x, y: $0.y + shift)
        }
    }

    // MARK: - Packing (JSX `placeBubbles` L1460–L1510)

    private struct Sized {
        let name: String
        let count: Int
        let size: CGFloat
    }

    private struct Placed {
        let name: String
        let count: Int
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    private static func placeBubbles(_ sized: [Sized], in container: CGSize) -> [Placed] {
        let padding = packingPadding(for: container)
        let slots = slotSets[min(sized.count, 6)] ?? defaultSlots

        // JSX `buildPlaced` (L1481–L1491): scale every bubble uniformly,
        // map index → slot, clamp to the inside of the container so the
        // bubble + its padding never crosses the edge.
        func buildPlaced(scale: CGFloat) -> [Placed] {
            sized.enumerated().map { i, bubble in
                let slot = slots[i % slots.count]
                let scaled = max(shrinkFloor, (bubble.size * scale).rounded())
                let r = scaled / 2
                let x = min(container.width - r - padding, max(r + padding, slot.x * container.width))
                let y = min(container.height - r - padding, max(r + padding, slot.y * container.height))
                return Placed(name: bubble.name, count: bubble.count, size: scaled, x: x, y: y)
            }
        }

        // JSX `fits` (L1493–L1503): pairwise distance must exceed the
        // sum of radii plus the layout padding.
        func fits(_ placed: [Placed]) -> Bool {
            guard placed.count > 1 else { return true }
            for i in 0..<placed.count {
                for j in (i + 1)..<placed.count {
                    let dx = placed[i].x - placed[j].x
                    let dy = placed[i].y - placed[j].y
                    let minDist = placed[i].size / 2 + placed[j].size / 2 + padding
                    if dx * dx + dy * dy < minDist * minDist { return false }
                }
            }
            return true
        }

        // JSX L1505–L1509: try 100% → 58% in 3.5% steps. First scale
        // that fits wins. Stride down through floats by hand because
        // `stride(through:)` on `Double`/`CGFloat` can overshoot the
        // bound by an epsilon and skip the 0.58 attempt.
        var scale: CGFloat = 1.0
        while scale >= 0.58 {
            let candidate = buildPlaced(scale: scale)
            if fits(candidate) { return candidate }
            scale -= 0.035
        }

        // JSX L1510 fallback: pathological canvas — return the 56%
        // layout even though some bubbles may overlap. Better than
        // pushing bubbles off-screen.
        return buildPlaced(scale: 0.56)
    }
}
