//
//  ContentView.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//

import SwiftUI
import PencilKit

struct ContentView: View {
    /// This @State property stores the drawing data.
    /// @State means SwiftUI will automatically update the UI when this changes.
    /// 
    /// Why @State here?
    /// - We need to persist the drawing across view updates
    /// - PencilCanvasView needs a @Binding to this
    /// - When the user draws, the drawing updates, and SwiftUI re-renders
    @State private var drawing = PKDrawing()
    
    var body: some View {
        ZStack {
            // The drawing canvas (background layer)
            PencilCanvasView(
                drawing: $drawing,  // $drawing creates a binding (two-way connection)
                drawingPolicy: .pencilOnly  // Only Apple Pencil draws, finger scrolls
            )
            .ignoresSafeArea()  // Make canvas fill entire screen
            
            // Small UI overlay to test simulator (foreground layer)
            VStack {
                HStack {
                    // Status indicator - green circle means simulator is working!
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                    
                    Text("Simulator Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Stroke count indicator
                    Text("\(drawing.strokes.count) strokes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground).opacity(0.8))
                .cornerRadius(8)
                .padding(.top, 20)
                .padding(.horizontal, 16)
                
                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
}
