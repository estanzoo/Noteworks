//
//  HomeView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 30) {
            Text("Homepage")
                .font(.largeTitle)
            
            // Navigation to Note Editor
            NavigationLink(destination: NoteEditorView()) {
                Label("Create New Note", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            
            // Navigation to Course Space
            NavigationLink(destination: CourseSpaceView()) {
                Label("View Course Space", systemImage: "book.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            
            Text("This is a placeholder. Add notes list here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Home")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}

