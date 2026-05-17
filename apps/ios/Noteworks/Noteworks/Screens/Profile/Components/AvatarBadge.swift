//
//  AvatarBadge.swift
//  Noteworks
//
//  Mirrors the AvatarBadge component from others/noteworks-library(2).jsx L352–L393.
//

import SwiftUI

struct AvatarBadge: View {
    let profile: Profile
    var size: CGFloat = 32
    var fontSize: CGFloat = 12

    var body: some View {
        Group {
            // Priority:
            //   1. Local `photoData` — set the instant the user picks a
            //      new image so the UI updates without waiting for
            //      `upload-avatar`.
            //   2. Server `avatarUrl` — canonical URL once the upload
            //      finishes. Also the source on every other client.
            //   3. Coloured initials fallback (pre-photo users).
            if let data = profile.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.68), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            } else if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsBadge
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.68), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            } else {
                initialsBadge
            }
        }
    }

    private var initialsBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            ProfileTheme.accent.opacity(0.18),
                            Color.white.opacity(0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)

            Text(profileInitials(from: profile.name))
                .font(.system(size: fontSize, weight: .bold))
                .tracking(0.04 * fontSize)
                .foregroundStyle(ProfileTheme.accent)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}
