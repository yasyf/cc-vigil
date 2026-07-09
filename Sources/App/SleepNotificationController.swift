import CCVigilAppKit
import CCVigilShared
import Foundation
import os
import UserNotifications

/// Thin edge between the daemon's status stream and UNUserNotificationCenter:
/// `SleepNotifier` decides what to post, this posts it. Authorization is
/// requested lazily on the first edge worth delivering; a denial is logged once
/// and every later edge is dropped silently.
@MainActor
final class SleepNotificationController {
    private enum Authorization {
        case unknown
        case granted
        case denied
    }

    private let center = UNUserNotificationCenter.current()
    private var notifier = SleepNotifier()
    private var authorization = Authorization.unknown

    func handle(_ event: StatusViewModel.Event, settings: NotificationSettings) {
        let pending = notifier.detect(event, settings: settings, now: Date())
        guard !pending.isEmpty else { return }
        Task { await deliver(pending) }
    }

    private func deliver(_ notifications: [SleepNotification]) async {
        guard await authorized() else { return }
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
            } catch {
                Logger.app.error("notification post failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func authorized() async -> Bool {
        switch authorization {
        case .granted:
            return true
        case .denied:
            return false
        case .unknown:
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                Logger.app.error("notification authorization failed: \(String(describing: error), privacy: .public)")
                authorization = .denied
                return false
            }
            authorization = granted ? .granted : .denied
            if !granted {
                Logger.app.notice("notifications denied; sleep edge alerts suppressed")
            }
            return granted
        }
    }
}
