import CCVigilCLIKit
import CCVigilShared
import Dispatch

/// Control operations ride the daemon's CLI socket; the app XPC channel is
/// read-only status.
struct DaemonCommands {
    let socketPath: String

    func roundTrip(_ request: WireRequest) async throws -> WireResponse {
        let client = SocketClient(path: socketPath)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try client.roundTrip(request) })
            }
        }
    }
}
