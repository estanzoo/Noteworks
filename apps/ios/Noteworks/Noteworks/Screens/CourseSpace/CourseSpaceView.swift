//
//  CourseSpaceView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI
import PencilKit

struct CourseSpaceView: View {
    @StateObject private var viewModel = CourseSpaceViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(white: 0.94)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("My Notes")
                        .font(.system(size: 32, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .padding(.bottom, 24)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 20)],
                        spacing: 20
                    ) {
                        ForEach(viewModel.notes) { note in
                            NavigationLink(value: note.id) {
                                NoteCard(note: note)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120)
                }
            }

            Button {
                viewModel.createNote()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 94/255, green: 173/255, blue: 211/255),
                                     Color(red: 124/255, green: 196/255, blue: 228/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: Color(red: 94/255, green: 173/255, blue: 211/255).opacity(0.4), radius: 10, y: 4)
            }
            .padding(.trailing, 28)
            .padding(.bottom, 100)
        }
        .navigationDestination(for: String.self) { noteId in
            NoteEditorView(noteId: noteId)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Note Card

private struct NoteCard: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                Color.white
                if note.drawing.strokes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "pencil.tip.crop.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(white: 0.75))
                        Text("Tap to edit")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.6))
                    }
                } else {
                    Image(uiImage: note.drawing.image(from: note.drawing.bounds, scale: 1.0))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Title + date
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Text(note.formattedDate)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.top, 10)
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

#Preview {
    NavigationStack {
        CourseSpaceView()
    }
}
