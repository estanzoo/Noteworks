//
//  BubblePickerSheet.swift
//  Noteworks
//
//  Sheet shown when the user taps the subject pill in the canvas toolbar to
//  move a note between bubbles. Lists every bubble plus an "Unnamed" entry
//  (mirrors JSX `getNoteDisplayMeta` defaulting + LibraryFilter dropdown
//  behavior). Selecting a row immediately commits via the closure.
//

import SwiftUI

struct BubblePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NotesStore

    /// Currently selected subject (nil means "Unnamed").
    let currentSubject: String?
    /// Called with the new subject (nil for Unnamed) once the user picks.
    let onSelect: (String?) -> Void

    @State private var showCreate = false

    private var bubbleOptions: [String] {
        store.bubbleNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bubbles") {
                    Button {
                        commit(nil)
                    } label: {
                        row(label: "Unnamed", isSelected: currentSubject == nil)
                    }

                    ForEach(bubbleOptions, id: \.self) { name in
                        Button {
                            commit(name)
                        } label: {
                            row(label: name, isSelected: name.caseInsensitiveCompare(currentSubject ?? "") == .orderedSame)
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
                        onSubmit: { name in
                            if let error = store.addBubble(name: name) {
                                return .failure(message: error)
                            }
                            commit(NotesStore.normalizeBubbleName(name))
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

    private func commit(_ value: String?) {
        onSelect(value)
        dismiss()
    }
}
