import CCVigilShared
import IOKit.pwr_mgt

final class IOPMIdleAssertion: IdleAssertionControlling {
    static let assertionName = "cc-vigil: agents active"

    private var assertionID: IOPMAssertionID?

    func create() -> Bool {
        if assertionID != nil {
            return true
        }
        var created = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName as CFString,
            &created
        )
        guard status == kIOReturnSuccess else {
            return false
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
