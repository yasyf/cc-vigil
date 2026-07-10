import Foundation

final class LowPowerMonitor: @unchecked Sendable {
    private let center: NotificationCenter
    private let observer: any NSObjectProtocol

    init(queue: DispatchQueue, onChange: @escaping @Sendable (Bool) -> Void) {
        center = .default
        let notificationQueue = OperationQueue()
        notificationQueue.underlyingQueue = queue
        observer = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: notificationQueue
        ) { _ in
            onChange(ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
    }

    deinit {
        center.removeObserver(observer)
    }

    func current() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
