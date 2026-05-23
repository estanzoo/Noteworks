//
//  BubblePickerSheet.swift
//  Noteworks
//
//  Sheet shown when the user taps the subject pill in the canvas toolbar to
//  move a note between bubbles. Lists every bubble; legacy orphan notes
//  appear under Untitled Bubble.
//

import SwiftUI

struct BubblePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NotesStore

    /// Currently selected subject (nil / legacy names map to Untitled Bubble).
    let currentSubject: String?
    /// Called with the chosen bubble name once the user picks.
    let onSelect: (String) -> Void

    @State private var showCreate = false

    private var resolvedCurrentSubject: String {
        NotesStore.resolvedBubbleSubject(currentSubject)
    }

    private var bubbleOptions: [String] {
        store.bubbleNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bubbles") {
                    ForEach(bubbleOptions, id: \.self) { name in
                        Button {
                            commit(name)
                        } label: {
                            row(
                                label: name,
                                isSelected: name.caseInsensitiveCompare(resolvedCurrentSubject) == .orderedSame
                            )
                        }
                    }

                    Button {
                        showCreate = true
                    } label: {
                        Label("Create new bubble", systemImage: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255))
                    }
                }
            }
            .navigationTitle("Move note to bubble")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if showCreate {
                    BubbleEditorDialog(
                        isPresented: $showCreate,
                        mode: .create,
                        defaultDisplayMode: .code,
                        onSubmit: { _, courseDraft, displayMode in
                            guard let courseDraft, let displayMode else {
                                return .failure(message: "Enter a course name.")
                            }
                            if let error = store.addCourseBubble(draft: courseDraft, displayMode: displayMode) {
                                return .failure(message: error)
                            }
                            let normalized = courseDraft.normalized()
                            if let label = normalized.bubbleLabel(for: displayMode) {
                                commit(NotesStore.normalizeBubbleName(label))
                            }
                            return .success
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder
    private func row(label: String, isSelected: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255))
            }
        }
    }

    private func commit(_ value: String) {
        onSelect(value)
        dismiss()
    }
}
