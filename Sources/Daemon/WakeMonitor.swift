import Foundation
import IOKit
import IOKit.pwr_mgt
import os

// IOMessage.h macros the Clang importer drops: iokit_common_msg(0x270|0x280|0x300).
private let canSystemSleepMessage: UInt32 = 0xE000_0270
private let systemWillSleepMessage: UInt32 = 0xE000_0280
private let systemHasPoweredOnMessage: UInt32 = 0xE000_0300

private final class WakeContext {
    var rootPort: io_connect_t = 0
    let onWake: @Sendable () -> Void

    init(onWake: @escaping @Sendable () -> Void) {
        self.onWake = onWake
    }
}

final class WakeMonitor: @unchecked Sendable {
    private let context: WakeContext
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init(onWake: @escaping @Sendable () -> Void) {
        context = WakeContext(onWake: onWake)
    }

    func start(queue: DispatchQueue) {
        let rawContext = Unmanaged.passUnretained(context).toOpaque()
        var port: IONotificationPortRef?
        let rootPort = IORegisterForSystemPower(
            rawContext,
            &port,
            { rawContext, _, messageType, messageArgument in
                guard let rawContext else { return }
                let context = Unmanaged<WakeContext>.fromOpaque(rawContext).takeUnretainedValue()
                switch messageType {
                case systemWillSleepMessage, canSystemSleepMessage:
                    // Never veto: an unacknowledged sleep message stalls the
                    // system for 30s. Idle sleep is governed by the assertion.
                    IOAllowPowerChange(context.rootPort, Int(bitPattern: messageArgument))
                case systemHasPoweredOnMessage:
                    context.onWake()
                default:
                    break
                }
            },
            &notifier
        )
        guard rootPort != 0, let port else {
            Logger.monitors.error("IORegisterForSystemPower failed; wake re-assert disabled")
            return
        }
        context.rootPort = rootPort
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, queue)
        Logger.monitors.info("registered for system power notifications")
    }
}
