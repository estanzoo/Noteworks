//
//  NoteTabBar.swift
//  Noteworks
//
//  Horizontal strip of "open note" tabs that sits at the very top of the
//  editor chrome. Port of the JSX `NoteSessionTab` + `NoteTabBar`
//  (others/NoteWorks_UI/noteworks-library.jsx L3321 / L3431):
//
//    - Each chip = one open note (title + meta line, optional X to close).
//    - Active chip is brighter and slightly wider.
//    - Trailing "+" button opens a fresh draft tab.
//    - Hidden by the parent when only one note is open.
//

import SwiftUI

struct NoteTabBar: View {
    /// Pre-resolved open notes. The parent reads from `store.openNoteIds`
    /// and maps each id to its `Note` so the bar can show the live title
    /// without poking into the store itself.
    let notes: [Note]
    let activeId: String?
    var onSelect: (String) -> Void
    var onClose: (String) -> Void
    var onCreateNew: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(notes) { note in
                        NoteSessionTab(
                            note: note,
                            isActive: note.id == activeId,
                            totalTabs: notes.count,
                            onSelect: { onSelect(note.id) },
                            onClose: { onClose(note.id) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                onCreateNew()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NoteEditorTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.94))
                    )
                    .overlay(
                        Circle().strokeBorder(NoteEditorTheme.accent.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open new note tab")
        }
    }
}

// MARK: - NoteSessionTab

private struct NoteSessionTab: View {
    let note: Note
    let isActive: Bool
    let totalTabs: Int
    let onSelect: () -> Void
    let onClose: () -> Void

    private var compact: Bool { totalTabs >= 3 }
    private var hideMeta: Bool { totalTabs >= 4 }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: compact ? 8 : 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "Untitled Note" : note.title)
                        .font(.system(size: compact ? (isActive ? 12.5 : 12)
                                                 : (isActive ? 13.5 : 13),
                                      weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isActive
                                         ? Color(red: 0x35/255, green: 0x55/255, blue: 0x6F/255)
                                         : Color(red: 69/255, green: 90/255, blue: 108/255).opacity(0.88))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !hideMeta {
                        Text(metaLabel.uppercased())
                            .font(.system(size: compact ? 9 : 10, weight: .bold))
                            .tracking(0.06 * 10)
                            .foregroundStyle(isActive
                                             ? Color(red: 78/255, green: 102/255, blue: 124/255).opacity(0.66)
                                             : Color(red: 90/255, green: 110/255, blue: 130/255).opacity(0.52))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 60, alignment: .leading)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isActive
                                         ? Color(red: 82/255, green: 102/255, blue: 124/255).opacity(0.85)
                                         : Color(red: 98/255, green: 116/255, blue: 133/255).opacity(0.7))
                        .frame(width: compact ? 18 : 20, height: compact ? 18 : 20)
                        .background(
                            Circle().fill(isActive
                                         ? Color.white.opacity(0.85)
                                         : Color.white.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(note.title)")
            }
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 7 : 9)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive
                          ? Color.white.opacity(0.82)
                          : Color.white.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isActive
                                  ? Color.white.opacity(0.92)
                                  : NoteEditorTheme.chromeBorder.opacity(0.7),
                                  lineWidth: 1)
            )
            .shadow(color: .black.opacity(isActive ? 0.06 : 0.02), radius: isActive ? 6 : 2, y: isActive ? 3 : 1)
            .frame(maxWidth: totalTabs <= 2 ? 260 : 200)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }

    private var metaLabel: String {
        if note.tag == "Draft" { return "Draft" }
        if let subject = note.subject, !subject.isEmpty { return subject }
        return "\(note.pageSettings.count) page\(note.pageSettings.count == 1 ? "" : "s")"
    }
}
