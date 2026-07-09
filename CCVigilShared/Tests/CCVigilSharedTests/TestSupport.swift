import CCVigilShared
import Foundation

struct FixedClock: WallClock {
    let now: Date

    init(epoch: Int64) {
        now = Date(timeIntervalSince1970: TimeInterval(epoch))
    }
}

extension IdleAssertionDescriptor {
    static let test = IdleAssertionDescriptor.ccVigil(localizationBundlePath: "/Applications/CCVigil.app")
}
