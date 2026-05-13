//
//  TextOverlayEditorSheet.swift
//  Noteworks
//
//  Modal sheet used by both "insert text" (from the text tool) and "edit
//  text" (tap-to-edit on an existing text overlay). Returns the edited
//  string + font-size + color via the `onSave` callback so the parent can
//  decide whether to `addOverlay(...)` or `updateOverlay(...)`.
//

import SwiftUI

struct TextOverlayEditorSheet: View {
    /// `nil` when inserting a fresh overlay; a copy of the existing one
    /// when editing.
    let existing: NotePageOverlay?

    var onSave: (_ text: String, _ fontSize: CGFloat, _ colorHex: String) -> Void
    var onCancel: () -> Void

    @State private var text: String
    @State private var fontSize: CGFloat
    @State private var color: Color
    @FocusState private var fieldFocused: Bool

    init(
        existing: NotePageOverlay?,
        onSave: @escaping (String, CGFloat, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: existing?.text ?? "")
        _fontSize = State(initialValue: existing?.fontSize ?? 18)
        if let hex = existing?.colorHex, let c = Color(noteHex: hex) {
            _color = State(initialValue: c)
        } else {
            _color = State(initialValue: NoteEditorTheme.textPrimary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Type your note…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($fieldFocused)
                        .submitLabel(.done)
                }

                Section("Style") {
                    HStack {
                        Text("Size")
                        Slider(value: $fontSize, in: 12...48, step: 1)
                            .tint(NoteEditorTheme.accent)
                        Text("\(Int(fontSize))")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .frame(width: 28, alignment: .trailing)
                    }

                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                }

                Section("Preview") {
                    Text(text.isEmpty ? "Your text here" : text)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle(existing == nil ? "Insert text" : "Edit text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text, fontSize, color.toHexString())
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { fieldFocused = true }
        }
    }
}

private extension Color {
    init?(noteHex hex: String) {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
