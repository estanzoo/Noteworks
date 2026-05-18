//
//  NotificationDropdown.swift
//  Noteworks
//

import SwiftUI

// MARK: - Notification Model

struct HomeNotification: Identifiable, Equatable, Codable {
    let id: String
    let type: NotificationType
    let text: String
    /// Absolute creation time. The row label ("2m ago" / "Oct 14") is
    /// derived from this on render so the timestamp keeps drifting as
    /// the dropdown stays open across days.
    let createdAt: Date
    var unread: Bool

    enum NotificationType: String, Equatable, Codable {
        case share, comment, update, system, post, like, mention

        var icon: String {
            switch self {
            case .share:   return "arrowshape.turn.up.forward"
            case .comment: return "bubble.right"
            case .update:  return "square.stack.3d.up"
            case .system:  return "info.circle"
            case .post:    return "person.2.fill"
            case .like:    return "heart.fill"
            case .mention: return "at"
            }
        }
    }

    init(id: String = UUID().uuidString,
         type: NotificationType,
         text: String,
         createdAt: Date = Date(),
         unread: Bool = true) {
        self.id = id
        self.type = type
        self.text = text
        self.createdAt = createdAt
        self.unread = unread
    }
}

// MARK: - Welcome notification

extension HomeNotification {
    /// Stable id so the welcome row survives persistence and inbox trimming.
    static let welcomeNotificationId = "system-welcome-beta"

    static func welcomeNotification(unread: Bool = true) -> HomeNotification {
        .init(
            id: welcomeNotificationId,
            type: .system,
            text: "Welcome to NoteWorks Beta!",
            createdAt: Date(),
            unread: unread
        )
    }
}

// MARK: - Notification Dropdown

struct NotificationDropdown: View {
    @ObservedObject var store: NotificationsStore
    let onClose: () -> Void

    private var unreadCount: Int { store.unreadCount }

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
                if store.items.isEmpty {
                    Text("You're all set — new community posts and replies will show up here.")
                        .font(.system(size: 13))
                        .foregroundStyle(HomeTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                } else {
                    ForEach(store.items) { notif in
                        NotificationRow(notification: notif) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.markRead(notif.id)
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
                store.markAllRead()
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

// MARK: - Relative time

/// Mirrors the "2m ago / 15m ago / 1h ago / 3h ago / 1d ago" labels in
/// the JSX mock — short and stable enough to align with the design.
private func notificationRelativeTime(_ date: Date) -> String {
    let delta = max(0, Int(Date().timeIntervalSince(date)))
    if delta < 45 { return "just now" }
    let minutes = delta / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    if days < 7 { return "\(days)d ago" }
    let weeks = days / 7
    if weeks < 5 { return "\(weeks)w ago" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
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

                    Text(notificationRelativeTime(notification.createdAt))
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
