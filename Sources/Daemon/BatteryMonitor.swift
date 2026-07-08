import CCVigilShared
import Foundation
import IOKit.ps
import os

final class CallbackBox: Sendable {
    let invoke: @Sendable () -> Void

    init(_ invoke: @escaping @Sendable () -> Void) {
        self.invoke = invoke
    }
}

final class BatteryMonitor: @unchecked Sendable {
    private let onReading: @Sendable (BatteryReading) -> Void
    private var thread: Thread?

    init(onReading: @escaping @Sendable (BatteryReading) -> Void) {
        self.onReading = onReading
    }

    static func sample() -> BatteryReading? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let sources = list.compactMap {
            IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return BatterySourceParser.reading(fromSources: sources)
    }

    func start() {
        if let reading = Self.sample() {
            onReading(reading)
        }
        let thread = Thread { [onReading] in
            let box = CallbackBox {
                guard let reading = BatteryMonitor.sample() else { return }
                onReading(reading)
            }
            let context = Unmanaged.passRetained(box).toOpaque()
            guard let source = IOPSNotificationCreateRunLoopSource({ rawContext in
                guard let rawContext else { return }
                Unmanaged<CallbackBox>.fromOpaque(rawContext).takeUnretainedValue().invoke()
            }, context)?.takeRetainedValue() else {
                Logger.monitors.error("IOPSNotificationCreateRunLoopSource failed; battery events disabled")
                return
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopRun()
        }
        thread.name = "dev.yasyf.cc-vigil.battery"
        thread.start()
        self.thread = thread
    }
}
