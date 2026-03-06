//
//  PencilCanvasView.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//

import SwiftUI
import PencilKit

/// PencilCanvasView is a SwiftUI wrapper around UIKit's PKCanvasView.
/// 
/// Why do we need this wrapper?
/// - SwiftUI doesn't have native PencilKit support (yet)
/// - PKCanvasView is a UIKit component (UIView)
/// - UIViewRepresentable bridges UIKit → SwiftUI
/// 
/// Think of it like this:
///   SwiftUI (modern) ← UIViewRepresentable (bridge) → UIKit (PKCanvasView)
struct PencilCanvasView: UIViewRepresentable {
    
    // MARK: - Properties
    
    /// This stores the actual drawing data (all your strokes)
    /// We'll use @State in the parent view to persist this later
    @Binding var drawing: PKDrawing
    
    /// Optional: Control whether finger drawing is allowed
    /// .anyInput = finger + pencil both work
    /// .pencilOnly = only Apple Pencil works (finger scrolls/selects)
    var drawingPolicy: PKCanvasViewDrawingPolicy = .anyInput
    
    // MARK: - UIViewRepresentable Required Methods
    
    /// This function is called ONCE when SwiftUI first creates the view.
    /// It's like the "initializer" for the UIKit view.
    /// 
    /// What happens here:
    /// 1. Create a PKCanvasView (the actual drawing canvas)
    /// 2. Configure it (set drawing policy, background color, etc.)
    /// 3. Set up the tool picker (the floating toolbar)
    /// 4. Return the configured view
    func makeUIView(context: Context) -> PKCanvasView {
        // Step 1: Create the canvas view
        let canvasView = PKCanvasView()
        
        // Step 2: Configure the canvas
        canvasView.drawingPolicy = drawingPolicy  // Allow finger/pencil drawing
        canvasView.backgroundColor = .white       // White background (like paper)
        canvasView.isOpaque = true                // Better performance
        
        // Step 3: Set the initial drawing (if we have one)
        canvasView.drawing = drawing
        
        // Step 4: Set the delegate (for handling drawing changes)
        // Must be set before tool picker setup
        canvasView.delegate = context.coordinator
        
        // Step 5: Set up the tool picker (the floating toolbar)
        // The tool picker is a system component that gives you:
        // - Pen, Pencil, Marker tools
        // - Eraser
        // - Ruler
        // - Color picker
        // - Stroke width slider
        // 
        // Note: Window might be nil initially, so we'll set it up in updateUIView
        setupToolPicker(for: canvasView, coordinator: context.coordinator)
        
        return canvasView
    }
    
    /// This function is called whenever SwiftUI needs to UPDATE the view.
    /// For example, if the @Binding drawing changes from outside.
    /// 
    /// IMPORTANT: We need to be careful here to avoid conflicts while the user is drawing.
    /// We only update if the drawing changed AND the user is not currently drawing.
    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        // Update drawing policy if it changed
        if canvasView.drawingPolicy != drawingPolicy {
            canvasView.drawingPolicy = drawingPolicy
        }
        
        // Set up tool picker if window is now available and picker not set up yet
        if canvasView.window != nil && context.coordinator.toolPicker == nil {
            setupToolPicker(for: canvasView, coordinator: context.coordinator)
        }
        
        // Only update the drawing if:
        // 1. The drawing actually changed
        // 2. The user is NOT currently drawing (to avoid stroke order conflicts)
        // This prevents the "stroke order flipped" warning
        // Note: We only update from external changes, not during active drawing
        if canvasView.drawing != drawing && !context.coordinator.isDrawing {
            canvasView.drawing = drawing
        }
    }
    
    /// Helper function to set up the tool picker
    /// This is called from both makeUIView and updateUIView to ensure it's set up properly
    private func setupToolPicker(for canvasView: PKCanvasView, coordinator: Coordinator) {
        // Guard: Only set up tool picker if window is available
        guard canvasView.window != nil else {
            // Window not available yet - will be set up in updateUIView when window becomes available
            return
        }
        
        // Create individual tool picker instance (recommended since iOS 14.0)
        // PKToolPicker.shared(for:) was deprecated - create new instances instead
        // This prevents gesture conflicts and follows Apple's current best practices
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        
        // Store tool picker reference in coordinator to avoid recreation
        coordinator.toolPicker = toolPicker
        
        // Make canvas first responder so tool picker shows
        // Use async to ensure view hierarchy is ready
        DispatchQueue.main.async {
            canvasView.becomeFirstResponder()
        }
    }
    
    /// This function creates a "Coordinator" - a helper object that handles
    /// delegate callbacks from PKCanvasView.
    /// 
    /// Why do we need a Coordinator?
    /// - PKCanvasView sends events via delegate methods
    /// - Delegate methods need to be in a class (not a struct)
    /// - UIViewRepresentable is a struct, so we need a separate class
    /// - The Coordinator bridges between UIKit callbacks and SwiftUI state
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator Class
    
    /// Coordinator is a helper class that implements PKCanvasViewDelegate.
    /// It receives callbacks from PKCanvasView and updates our SwiftUI state.
    /// 
    /// Think of it as a "translator" between UIKit events and SwiftUI state.
    class Coordinator: NSObject, PKCanvasViewDelegate {
        
        /// Reference back to the parent PencilCanvasView
        /// This lets us update the @Binding drawing property
        var parent: PencilCanvasView
        
        /// Store a reference to the tool picker to avoid recreation issues
        var toolPicker: PKToolPicker?
        
        /// Track if user is currently drawing to prevent update conflicts
        var isDrawing: Bool = false
        
        /// Initialize with a reference to the parent
        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }
        
        /// This delegate method is called whenever the user draws something.
        /// It fires continuously as the user draws (not just at the end).
        /// 
        /// What we do:
        /// 1. Get the updated drawing from the canvas
        /// 2. Update our @Binding drawing property
        /// 3. SwiftUI will automatically re-render if needed
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Update the parent's @Binding drawing
            // This keeps SwiftUI state in sync with the canvas
            // We use DispatchQueue to avoid updating during drawing operations
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Only update if actually different to avoid unnecessary updates
                if self.parent.drawing != canvasView.drawing {
                    self.parent.drawing = canvasView.drawing
                }
            }
            
            // TODO: Later, we'll add auto-save here
            // For example: save to local file or send to server
        }
        
        /// This delegate method is called when the user starts drawing.
        /// Useful for adjusting UI layout when the toolbar appears.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Mark that user is currently drawing
            isDrawing = true
            // Called when user starts drawing
            // Could use this to hide other UI elements, show undo/redo buttons, etc.
        }
        
        /// This delegate method is called when the user stops drawing.
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // Mark that user finished drawing
            isDrawing = false
            // Called when user stops drawing
            // Could use this to show UI elements again, trigger auto-save, etc.
        }
    }
}

// MARK: - Preview

#Preview {
    // Create a preview with an empty drawing
    PencilCanvasView(drawing: .constant(PKDrawing()))
}

