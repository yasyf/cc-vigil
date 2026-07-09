import CCVigilShared
import IOKit.pwr_mgt

final class IOPMIdleAssertion: IdleAssertionControlling {
    private var assertionID: IOPMAssertionID?

    // Re-creates the assertion on every call so the timeout re-arms with a fresh
    // deadline: the daemon re-pushes every 60 s, keeping the 15 min dead-man from
    // ever firing on a healthy system. The new assertion is live before the old is
    // released, so the hold never gaps; a failed create keeps the prior assertion.
    func create(_ descriptor: IdleAssertionDescriptor) -> Bool {
        var created = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithDescription(
            descriptor.type.ioKitAssertionType,
            descriptor.name as CFString,
            descriptor.details as CFString,
            descriptor.reason as CFString,
            nil,
            descriptor.timeout,
            descriptor.timeoutAction.ioKitTimeoutAction,
            &created
        )
        guard status == kIOReturnSuccess else {
            return false
        }
        if let previous = assertionID {
            IOPMAssertionRelease(previous)
        }
        assertionID = created
        return true
    }

    func release() {
        guard let assertionID else {
            return
        }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }
}

private extension IdleAssertionType {
    var ioKitAssertionType: CFString {
        switch self {
        case .preventUserIdleSystemSleep:
            kIOPMAssertPreventUserIdleSystemSleep as CFString
        }
    }
}

private extension IdleAssertionTimeoutAction {
    var ioKitTimeoutAction: CFString {
        switch self {
        case .release:
            kIOPMAssertionTimeoutActionRelease as CFString
        }
    }
}
