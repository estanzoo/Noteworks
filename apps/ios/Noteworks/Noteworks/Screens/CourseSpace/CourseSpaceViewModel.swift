//
//  CourseSpaceViewModel.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import Foundation
import PencilKit

struct NoteItem: Identifiable {
    let id: String
    var title: String
    var drawing: PKDrawing
    var createdAt: Date

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: createdAt)
    }
}

@MainActor
class CourseSpaceViewModel: ObservableObject {
    @Published var notes: [NoteItem] = []

    init() {
        notes = [
            NoteItem(
                id: UUID().uuidString,
                title: "Untitled Note",
                drawing: PKDrawing(),
                createdAt: Date()
            )
        ]
    }

    func createNote() {
        let note = NoteItem(
            id: UUID().uuidString,
            title: "Note \(notes.count + 1)",
            drawing: PKDrawing(),
            createdAt: Date()
        )
        notes.insert(note, at: 0)
    }
}
