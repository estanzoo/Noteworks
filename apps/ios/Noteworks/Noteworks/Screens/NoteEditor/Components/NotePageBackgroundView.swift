//
//  NotePageBackgroundView.swift
//  Noteworks
//
//  Draws the per-page background pattern behind the PencilKit canvas.
//  Templates: blank, dots, ruled (legacy key `single-column`), grid,
//  and Cornell. Rotation is applied on the parent page card.
//

import SwiftUI
import UIKit

struct NotePageBackgroundView: View {
    let background: NotePageBackground
    var imageData: Data? = nil

    var body: some View {
        ZStack {
            if let imageData,
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            Canvas { context, size in
                NotePageBackgroundDrawing.draw(background, size: size, context: &context)
            }
        }
        .clipped()
    }
}
