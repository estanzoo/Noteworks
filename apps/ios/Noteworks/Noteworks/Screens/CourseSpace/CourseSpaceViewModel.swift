//
//  CourseSpaceViewModel.swift
//  Noteworks
//
//  After the bubbles ↔ notes wiring lands, the library no longer owns its
//  own list of notes. The shared `NotesStore` is the source of truth; this
//  view model now exists only to host transient UI state for the screen
//  (active tab + active subject filter). Everything else is read directly
//  from the store via `@EnvironmentObject` in `CourseSpaceView`.
//

import Foundation

@MainActor
final class CourseSpaceViewModel: ObservableObject {
    // Reserved for future view-only state (e.g. multi-select / pinned notes).
    // The list of notes themselves is owned by `NotesStore`.
}
