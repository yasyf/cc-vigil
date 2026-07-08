import CCVigilShared
import Foundation

// TODO: Depend on CCTranscript once its package ships — the transcript oracle
// that computes real verdicts reads Claude Code sessions through it.

@main
enum DaemonMain {
    static func main() async throws {
        print("CCVigilDaemon skeleton: verdict \(Verdict.allowSleep.rawValue); idling")
        while true {
            try await Task.sleep(for: .seconds(300))
        }
    }
}
