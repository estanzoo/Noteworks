//
//  CanvasView.swift
//  Noteworks
//
//  Created by 王颢泰 on 2026-02-01.
//

import SwiftUI

struct CanvasView: View{
    var body: some View{
        GeometryReader{ geometry in
            Rectangle()
                .fill(Color.blue)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    CanvasView()
}
