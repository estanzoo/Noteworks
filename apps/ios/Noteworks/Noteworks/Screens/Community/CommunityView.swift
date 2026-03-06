//
//  CommunityView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

struct CommunityView: View {
    var body: some View {
        VStack(spacing: 30) {
            Text("Community Page")
                .font(.largeTitle)
            
            // Navigation to Course Space
            NavigationLink(destination: CourseSpaceView()) {
                Label("Browse Course Spaces", systemImage: "person.3.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            
            Text("This is a placeholder. Add spaces list here.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        CommunityView()
    }
}

