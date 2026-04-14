//
//  NotificationDropdown.swift
//  Noteworks
//

import SwiftUI

// MARK: - Notification Model

struct HomeNotification: Identifiable {
    let id: Int
    let type: NotificationType
    let text: String
    let time: String
    var unread: Bool

    enum NotificationType: String {
        case share, comment, update, system

        var icon: String {
            switch self {
            case .share:   return "arrowshape.turn.up.forward"
            case .comment: return "bubble.right"
            case .update:  return "square.stack.3d.up"
            case .system:  return "info.circle"
            }
        }
    }
}

// MARK: - Sample Data

extension HomeNotification {
    static let samples: [HomeNotification] = [
        .init(id: 1, type: .share,   text: "Amy shared Cell Biology notes with you",    time: "2m ago",  unread: true),
        .init(id: 2, type: .comment, text: "Sam commented on your Organic Chem note",   time: "15m ago", unread: true),
        .init(id: 3, type: .update,  text: "Your Lab Report was enhanced by AI",        time: "1h ago",  unread: false),
        .init(id: 4, type: .share,   text: "Sam shared Grammer Rules with you",         time: "3h ago",  unread: false),
        .init(id: 5, type: .system,  text: "Welcome to NoteWorks Beta!",                time: "1d ago",  unread: false),
    ]
}

// MARK: - Notification Dropdown

struct NotificationDropdown: View {
    @Binding var notifications: [HomeNotification]
    let onClose: () -> Void

    private var unreadCount: Int {
        notifications.filter(\.unread).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 20)
            itemList
            Divider()
            footer
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.7))
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(HomeTheme.glassBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 24, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HomeTheme.textPrimary)
            Spacer()
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(HomeTheme.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(notifications) { notif in
                    NotificationRow(notification: notif) {
                        if let idx = notifications.firstIndex(where: { $0.id == notif.id }) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                notifications[idx].unread = false
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 340)
    }

    // MARK: - Footer

    private var footer: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                for i in notifications.indices {
                    notifications[i].unread = false
                }
            }
        } label: {
            Text(unreadCount > 0 ? "Mark all as read" : "All caught up!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(unreadCount > 0 ? HomeTheme.accent : HomeTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notification Row

private struct NotificationRow: View {
    let notification: HomeNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notification.type.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(HomeTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(HomeTheme.accent.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.text)
                        .font(.system(size: 14, weight: notification.unread ? .semibold : .regular))
                        .foregroundStyle(HomeTheme.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Text(notification.time)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HomeTheme.textMuted)
                }

                Spacer(minLength: 0)

                if notification.unread {
                    Circle()
                        .fill(HomeTheme.accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(notification.unread ? HomeTheme.accent.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
