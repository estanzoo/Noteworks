//
//  AccountView.swift
//  Noteworks
//
//  Created on 2026-02-03.
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Profile header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 94/255, green: 173/255, blue: 211/255),
                                             Color(red: 124/255, green: 196/255, blue: 228/255)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Text(initials)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text(appState.currentUser?.email ?? "Not signed in")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.primary)

                    Text("Member since 2026")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.top, 32)
                .padding(.bottom, 32)

                // MARK: - Settings sections
                VStack(spacing: 12) {
                    SettingsSection(title: "General") {
                        SettingsRow(icon: "person.fill", label: "Edit Profile")
                        SettingsRow(icon: "bell.fill", label: "Notifications")
                        SettingsRow(icon: "paintbrush.fill", label: "Appearance")
                    }

                    SettingsSection(title: "Data") {
                        SettingsRow(icon: "icloud.fill", label: "Cloud Sync")
                        SettingsRow(icon: "arrow.down.circle.fill", label: "Export Notes")
                        SettingsRow(icon: "trash.fill", label: "Clear Cache", tint: .orange)
                    }

                    SettingsSection(title: "About") {
                        SettingsRow(icon: "info.circle.fill", label: "Version 1.0 (Beta)", showChevron: false)
                        SettingsRow(icon: "questionmark.circle.fill", label: "Help & Feedback")
                        SettingsRow(icon: "doc.text.fill", label: "Terms of Service")
                    }
                }
                .padding(.horizontal, 20)

                // MARK: - Sign out
                Button {
                    appState.signOut()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        .background(Color(white: 0.94).ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var initials: String {
        guard let email = appState.currentUser?.email else { return "?" }
        let prefix = email.components(separatedBy: "@").first ?? ""
        let parts = prefix.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(prefix.prefix(2)).uppercased()
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .kerning(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {
    let icon: String
    let label: String
    var tint: Color = Color(red: 94/255, green: 173/255, blue: 211/255)
    var showChevron: Bool = true

    var body: some View {
        Button { } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.78))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environmentObject(AppState())
    }
}
