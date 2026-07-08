import CCVigilShared
import Foundation

@main
enum HelperMain {
    static func main() async throws {
        let policy = SleepBlockPolicy()
        print("CCVigilHelper skeleton: needsClear=\(policy.needsClear); idling")
        while true {
            try await Task.sleep(for: .seconds(300))
        }
    }
}
