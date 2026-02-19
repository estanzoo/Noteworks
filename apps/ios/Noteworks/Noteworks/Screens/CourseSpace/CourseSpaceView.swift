//
//  CourseSpaceView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

struct CourseSpaceView: View {
    var body: some View {
        VStack {
            Text("CourseNote Page")
                .font(.largeTitle)
        }
        .navigationTitle("Course Space")
    }
}

#Preview {
    NavigationStack {
        CourseSpaceView()
    }
}

