//
//  NoteEditorView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

struct NoteEditorView: View {
    var body: some View {
        VStack {
            Text("Notetaking Page")
                .font(.largeTitle)
        }
        .navigationTitle("Note Editor")
    }
}

#Preview {
    NavigationStack {
        NoteEditorView()
    }
}

