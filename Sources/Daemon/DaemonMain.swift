import CCTranscript
import CCVigilShared
import Foundation

@main
enum DaemonMain {
    static func main() async throws {
        // TODO: placeholder probe — the real transcript oracle replaces this.
        if CommandLine.arguments.count > 1 {
            let activity = try sessionActivity(path: CommandLine.arguments[1])
            let epoch = activity.last_event_epoch().map(String.init) ?? "nil"
            print(
                "CCTranscript probe: is_waiting=\(activity.is_waiting()) "
                    + "mid_tool=\(activity.mid_tool()) last_event_epoch=\(epoch)"
            )
        }
        print("CCVigilDaemon skeleton: verdict \(Verdict.allowSleep.rawValue); idling")
        while true {
            try await Task.sleep(for: .seconds(300))
        }
    }
}
