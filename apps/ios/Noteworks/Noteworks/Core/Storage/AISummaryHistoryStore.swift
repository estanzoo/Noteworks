//
//  AISummaryHistoryStore.swift
//  Noteworks
//

import Foundation

final class AISummaryHistoryStore {
    static let shared = AISummaryHistoryStore()

    private let defaults: UserDefaults
    private let storageKey = "aiSummaryHistoryByNote"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entries(for noteId: String) -> [AISummaryEntry] {
        load()[noteId] ?? []
    }

    func append(_ entry: AISummaryEntry) {
        var map = load()
        var list = map[entry.sourceNoteId] ?? []
        list.append(entry)
        map[entry.sourceNoteId] = list
        save(map)
    }

    func allEntries(for noteId: String) -> [AISummaryEntry] {
        entries(for: noteId).sorted { $0.createdAt > $1.createdAt }
    }

    private func load() -> [String: [AISummaryEntry]] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [AISummaryEntry]].self, from: data)) ?? [:]
    }

    private func save(_ map: [String: [AISummaryEntry]]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
