import Foundation
import IOKit
import os

final class LidMonitor: @unchecked Sendable {
    private let service: io_service_t
    private let notifyPort: IONotificationPortRef
    private var notification: io_object_t = 0
    private let box: CallbackBox

    /// Returns nil on machines without a lid (no AppleClamshellState property).
    init?(queue: DispatchQueue, onChange: @escaping @Sendable (Bool) -> Void) {
        let matched = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard matched != 0, Self.clamshellState(of: matched) != nil else {
            if matched != 0 {
                IOObjectRelease(matched)
            }
            Logger.monitors.info("no AppleClamshellState; lid monitoring disabled")
            return nil
        }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            IOObjectRelease(matched)
            Logger.monitors.error("IONotificationPortCreate failed; lid monitoring disabled")
            return nil
        }
        service = matched
        notifyPort = port
        box = CallbackBox {
            guard let closed = Self.clamshellState(of: matched) else { return }
            onChange(closed)
        }
        IONotificationPortSetDispatchQueue(port, queue)
        let registered = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { rawContext, _, _, _ in
                guard let rawContext else { return }
                Unmanaged<CallbackBox>.fromOpaque(rawContext).takeUnretainedValue().invoke()
            },
            Unmanaged.passUnretained(box).toOpaque(),
            &notification
        )
        guard registered == kIOReturnSuccess else {
            Logger.monitors.error("IOServiceAddInterestNotification failed; lid monitoring disabled")
            IONotificationPortDestroy(port)
            IOObjectRelease(service)
            return nil
        }
    }

    func current() -> Bool {
        Self.clamshellState(of: service) ?? false
    }

    private static func clamshellState(of service: io_service_t) -> Bool? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        return value as? Bool
    }
}
