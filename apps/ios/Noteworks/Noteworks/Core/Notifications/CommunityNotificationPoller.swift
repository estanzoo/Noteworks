//
//  CommunityNotificationPoller.swift
//  Noteworks
//
//  Periodically refreshes the public community feed while the user is
//  signed in and the app is active, so new posts from other users land
//  in the bell inbox even when they stay on Home (no APNs required).
//

import Foundation

@MainActor
enum CommunityNotificationPoller {
    /// Seconds between feed checks while the app is in the foreground.
    static let intervalSeconds: UInt64 = 30

    /// Poll loop — cancelled when the hosting `.task` ends (tab hidden,
    /// sign-out, or app backgrounded).
    static func run(
        notifications: NotificationsStore,
        isActive: @escaping () -> Bool,
        accessToken: @escaping () -> String?,
        currentUserId: @escaping () -> String?,
        service: CommunityServiceProtocol = CommunityService.shared
    ) async {
        while !Task.isCancelled {
            guard isActive(),
                  let token = accessToken(),
                  let userId = currentUserId() else {
                break
            }

            await pollOnce(
                notifications: notifications,
                token: token,
                userId: userId,
                service: service
            )

            do {
                try await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
            } catch {
                break
            }
        }
    }

    private static func pollOnce(
        notifications: NotificationsStore,
        token: String,
        userId: String,
        service: CommunityServiceProtocol
    ) async {
        do {
            let page = try await service.fetchFeed(
                filter: .publicFeed(),
                cursor: nil,
                limit: 20,
                currentUserId: userId,
                accessToken: token
            )
            notifications.recordNewCommunityPosts(
                page.posts,
                currentUserId: userId
            )
        } catch {
            // Transient network/auth errors — skip this tick; the next
            // poll will retry.
        }
    }
}
