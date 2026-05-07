//
//  InlineLinkAction.swift
//  Noteworks
//
//  Mirrors InlineLinkAction from others/noteworks-library(2).jsx L512–L539.
//

import SwiftUI

struct InlineLinkAction: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ProfileTheme.accent)
                .underline()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
    }
}
