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
    var subject: String?
    var tag: String?
    var sharedBy: String?
    var pageCount: Int

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            return "TODAY"
        } else if calendar.isDateInYesterday(createdAt) {
            return "YESTERDAY"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MMM.dd  HH:mm"
            return f.string(from: createdAt).uppercased()
        }
    }
}

@MainActor
class CourseSpaceViewModel: ObservableObject {
    @Published var notes: [NoteItem] = []

    init() {
        notes = sampleNotes
    }

    @discardableResult
    func createNote() -> String {
        let note = NoteItem(
            id: UUID().uuidString,
            title: "Note \(notes.count + 1)",
            drawing: PKDrawing(),
            createdAt: Date(),
            subject: nil,
            tag: nil,
            sharedBy: nil,
            pageCount: 1
        )
        notes.insert(note, at: 0)
        return note.id
    }

    private var sampleNotes: [NoteItem] {
        [
            NoteItem(id: UUID().uuidString, title: "Lab Report",
                     drawing: PKDrawing(), createdAt: makeDate(month: 10, day: 24, hour: 18, minute: 6),
                     subject: "Chemistry", tag: "Course", sharedBy: nil, pageCount: 9),
            NoteItem(id: UUID().uuidString, title: "Cell Biology",
                     drawing: PKDrawing(), createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                     subject: "Biology", tag: nil, sharedBy: "Amy", pageCount: 16),
            NoteItem(id: UUID().uuidString, title: "Organic Chem",
                     drawing: PKDrawing(), createdAt: Date(),
                     subject: "Chemistry", tag: "Public", sharedBy: "Sam", pageCount: 34),
            NoteItem(id: UUID().uuidString, title: "Grammer Rules",
                     drawing: PKDrawing(), createdAt: makeDate(month: 10, day: 20, hour: 22, minute: 6),
                     subject: nil, tag: "Course", sharedBy: "Sam", pageCount: 11),
            NoteItem(id: UUID().uuidString, title: "Perspective Drawing",
                     drawing: PKDrawing(), createdAt: makeDate(month: 10, day: 18, hour: 9, minute: 30),
                     subject: "Art", tag: nil, sharedBy: nil, pageCount: 6),
            NoteItem(id: UUID().uuidString, title: "Physics Lab 3",
                     drawing: PKDrawing(), createdAt: makeDate(month: 10, day: 15, hour: 14, minute: 20),
                     subject: "Physics", tag: nil, sharedBy: nil, pageCount: 4),
            NoteItem(id: UUID().uuidString, title: "Calc II Notes",
                     drawing: PKDrawing(), createdAt: makeDate(month: 10, day: 12, hour: 10, minute: 0),
                     subject: "Mathematics", tag: "Course", sharedBy: nil, pageCount: 12),
            NoteItem(id: UUID().uuidString, title: "Calc III Review",
                     drawing: PKDrawing(), createdAt: makeDate(month: 10, day: 10, hour: 16, minute: 30),
                     subject: "Mathematics", tag: nil, sharedBy: nil, pageCount: 8),
        ]
    }

    private func makeDate(month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = Calendar.current.component(.year, from: Date())
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}
