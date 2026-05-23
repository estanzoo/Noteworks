//
//  AISummaryModels.swift
//  Noteworks
//
//  Side-panel summaries for Gap Detection and Smart Organization.
//  Mirrors UI 5 `gapSummaries`, `smartSummaries`, and `AISummaryHistoryPopup`.
//

import Foundation

enum AISummaryKind: String, Codable, Equatable {
    case gap
    case smart
}

struct AISummarySection: Codable, Equatable, Identifiable {
    var id: String { heading }
    let heading: String
    let bullets: [String]
}

struct AISummaryTemplate: Codable, Equatable, Identifiable {
    var id: String { "\(badge)-\(title)" }
    let badge: String
    let title: String
    let sections: [AISummarySection]
}

struct AISummaryEntry: Codable, Equatable, Identifiable {
    let id: String
    let kind: AISummaryKind
    let sourceNoteId: String
    let sourceTitle: String
    let createdAt: TimeInterval
    let createdAtLabel: String
    /// Gap Detection — peer notes included in the run.
    var peerNoteTitles: [String] = []
    var classMaterialNames: [String] = []
    /// Gap Detection — structured cards shown in the side panel.
    var templates: [AISummaryTemplate] = []
    /// Smart Organization — flat section list.
    var sections: [AISummarySection] = []

    var historyMeta: String {
        switch kind {
        case .gap:
            let peers = peerNoteTitles.count
            let materials = classMaterialNames.count
            return "\(peers) peer note\(peers == 1 ? "" : "s") · \(materials) material\(materials == 1 ? "" : "s")"
        case .smart:
            let groups = sections.count
            return "\(groups) change group\(groups == 1 ? "" : "s")"
        }
    }
}

enum AISummaryEntryFactory {
    static func gapEntry(
        sourceNoteId: String,
        sourceTitle: String,
        response: GapDetectionResponse,
        peerNoteTitles: [String],
        classMaterialNames: [String]
    ) -> AISummaryEntry {
        let peerLabel = peerNoteTitles.isEmpty
            ? "Community comparisons"
            : peerNoteTitles.prefix(2).joined(separator: " + ")
        let materialLabel = classMaterialNames.isEmpty
            ? "Your current class materials"
            : classMaterialNames.prefix(2).joined(separator: " + ")

        let overviewTemplate = AISummaryTemplate(
            badge: "Gap detection",
            title: response.title.uppercased(),
            sections: [
                AISummarySection(heading: "OVERVIEW", bullets: bulletLines([response.overview])),
                AISummarySection(
                    heading: "MISSING FROM YOUR NOTE",
                    bullets: bulletLines(response.missingTopics)
                ),
                AISummarySection(
                    heading: "NEEDS MORE DETAIL",
                    bullets: bulletLines(response.weakAreas)
                ),
            ]
        )

        let synthesisTemplate = AISummaryTemplate(
            badge: "Study bridge",
            title: "SOURCE BLEND",
            sections: [
                AISummarySection(
                    heading: "PEER SIGNALS",
                    bullets: bulletLines([
                        "Checked against \(max(peerNoteTitles.count, 1)) related peer note\(peerNoteTitles.count == 1 ? "" : "s")",
                        "Strongest reference: \(peerLabel)",
                    ] + (response.extraTopics.isEmpty ? [] : Array(response.extraTopics.prefix(2))))
                ),
                AISummarySection(
                    heading: "CLASS MATERIALS",
                    bullets: classMaterialNames.isEmpty
                        ? bulletLines([
                            materialLabel,
                            "Upload up to five files next time for richer summaries",
                        ])
                        : bulletLines(classMaterialNames.prefix(4).map { $0 })
                ),
                AISummarySection(
                    heading: "RECOMMENDED ADDITIONS",
                    bullets: bulletLines(
                        response.recommendedAdditions.isEmpty
                            ? ["Review contradictions and strengthen weak sections"]
                            : response.recommendedAdditions
                    )
                ),
            ]
        )

        if !response.contradictions.isEmpty {
            var templates = [overviewTemplate, synthesisTemplate]
            templates[0] = AISummaryTemplate(
                badge: overviewTemplate.badge,
                title: overviewTemplate.title,
                sections: overviewTemplate.sections + [
                    AISummarySection(
                        heading: "POSSIBLE CONFLICTS",
                        bullets: bulletLines(response.contradictions)
                    ),
                ]
            )
            return makeEntry(
                sourceNoteId: sourceNoteId,
                sourceTitle: sourceTitle,
                peerNoteTitles: peerNoteTitles,
                classMaterialNames: classMaterialNames,
                templates: templates,
                confidence: response.confidence
            )
        }

        return makeEntry(
            sourceNoteId: sourceNoteId,
            sourceTitle: sourceTitle,
            peerNoteTitles: peerNoteTitles,
            classMaterialNames: classMaterialNames,
            templates: [overviewTemplate, synthesisTemplate],
            confidence: response.confidence
        )
    }

    static func smartEntry(
        sourceNoteId: String,
        sourceTitle: String,
        sections: [AISummarySection]
    ) -> AISummaryEntry {
        AISummaryEntry(
            id: "smart-summary-\(sourceNoteId)-\(Int(Date().timeIntervalSince1970 * 1000))",
            kind: .smart,
            sourceNoteId: sourceNoteId,
            sourceTitle: sourceTitle,
            createdAt: Date().timeIntervalSince1970,
            createdAtLabel: "TODAY",
            sections: sections
        )
    }

    static func fallbackSmartSections(pageCount: Int, title: String) -> [AISummarySection] {
        let sectionCount = max(2, min(5, Int(round(Double(pageCount) * 0.8))))
        return [
            AISummarySection(
                heading: "STRUCTURE",
                bullets: bulletLines([
                    "Re-sequenced \(sectionCount) sections in \(title)",
                    "Merged overlapping passages into clearer blocks",
                    "Renamed headings to match section content",
                ])
            ),
            AISummarySection(
                heading: "READABILITY",
                bullets: bulletLines([
                    "Tightened long paragraphs without losing meaning",
                    "Standardized bullet formatting across the note",
                    "Removed duplicate lines and dangling notes",
                ])
            ),
            AISummarySection(
                heading: "NEXT STEPS",
                bullets: bulletLines([
                    "Skim the new section order to confirm the flow",
                    "Restore any merged passage you'd rather keep separate",
                    "Tag the reorganized note for review later",
                ])
            ),
        ]
    }

    private static func makeEntry(
        sourceNoteId: String,
        sourceTitle: String,
        peerNoteTitles: [String],
        classMaterialNames: [String],
        templates: [AISummaryTemplate],
        confidence: GapDetectionConfidence
    ) -> AISummaryEntry {
        var finalTemplates = templates
        if var first = finalTemplates.first {
            first = AISummaryTemplate(
                badge: first.badge,
                title: first.title,
                sections: first.sections + [
                    AISummarySection(
                        heading: "CONFIDENCE",
                        bullets: bulletLines(["Model confidence: \(confidence.rawValue.capitalized)"])
                    ),
                ]
            )
            finalTemplates[0] = first
        }

        return AISummaryEntry(
            id: "gap-summary-\(sourceNoteId)-\(Int(Date().timeIntervalSince1970 * 1000))",
            kind: .gap,
            sourceNoteId: sourceNoteId,
            sourceTitle: sourceTitle,
            createdAt: Date().timeIntervalSince1970,
            createdAtLabel: "TODAY",
            peerNoteTitles: peerNoteTitles,
            classMaterialNames: classMaterialNames,
            templates: finalTemplates
        )
    }

    private static func bulletLines(_ items: [String]) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                line.hasPrefix("-") || line.hasPrefix("•") ? line : "- \(line)"
            }
    }
}
