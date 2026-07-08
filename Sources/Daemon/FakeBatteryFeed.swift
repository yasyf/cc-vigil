import CCVigilDaemonKit
import CCVigilShared
import Dispatch
import Foundation

/// Test-only stand-in for BatteryMonitor (see FakeBatteryFile): polls the
/// seam file every second so a headless run can flip the battery cutout.
final class FakeBatteryFeed: @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(url: URL, queue: DispatchQueue, onReading: @escaping @Sendable (BatteryReading) -> Void) {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler {
            guard let reading = Self.read(url: url) else { return }
            onReading(reading)
        }
    }

    static func read(url: URL) -> BatteryReading? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return FakeBatteryFile.reading(fromContents: contents)
    }

    func start() {
        timer.resume()
    }
}
