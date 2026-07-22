import CCVigilCLIKit
import CCVigilShared
import CCVigilTransport

/// Control operations ride the daemon's CLI socket; the app XPC channel is
/// read-only status.
struct DaemonCommands {
    private let client: CLIDaemonClient

    init(socketPath: String) {
        client = CLIDaemonClient(path: socketPath)
    }

    func roundTrip(_ request: WireRequest) async throws -> WireResponse {
        try await client.roundTrip(request)
    }
}
