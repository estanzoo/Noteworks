//
//  NavBar.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

/// Custom Navigation Bar Component
/// Use this reusable navbar across all screens for consistent styling
struct NavBar: View {
    let title: String
    var leadingButton: (() -> AnyView)? = nil
    var trailingButton: (() -> AnyView)? = nil
    
    var body: some View {
        HStack {
            // Leading button (back button, menu, etc.)
            if let leading = leadingButton {
                leading()
            } else {
                Spacer()
            }
            
            // Title
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
            
            // Trailing button (settings, add, etc.)
            if let trailing = trailingButton {
                trailing()
            } else {
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#Preview {
    NavBar(title: "Example Title")
}

