import CCVigilShared
import Foundation

@main
enum HelperMain {
    static func main() async throws {
        print("CCVigilHelper skeleton: verdict \(Verdict.allowSleep.rawValue); idling")
        while true {
            try await Task.sleep(for: .seconds(300))
        }
    }
}
