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
final class SleepNotificationController: NSObject, UNUserNotificationCenterDelegate {
    private enum Authorization {
        case unknown
        case granted
        case denied
    }

    private let center = UNUserNotificationCenter.current()
    private let notifier = SleepNotifier(store: UserDefaultsAlertWatermarkStore())
    private var authorization = Authorization.unknown

    override init() {
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = [.banner]
        if notification.request.content.sound != nil {
            options.insert(.sound)
        }
        return options
    }

    func handle(_ event: StatusViewModel.Event, settings: NotificationSettings) {
        var pending: [SleepNotification] = []
        notifier.consume(event, settings: settings) { pending.append($0) }
        guard !pending.isEmpty else { return }
        // Delivery past this hand-off is best-effort async; a crash before the OS accepts the toast falls to the away summary, by design.
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
