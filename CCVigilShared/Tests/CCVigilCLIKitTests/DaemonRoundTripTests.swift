import CCVigilCLIKit
import CCVigilDaemonKit
import CCVigilShared
import Darwin
import Foundation
import os
import Testing

/// Wire-protocol proof against the real daemon: spawns the xcodebuild-built
/// CCVigilDaemon in dry-run mode on a temp support dir and round-trips every
/// socket op, plus the built cc-vigil binary end to end. CI builds before
/// `swift test`, so the products always exist there; locally, run the
/// xcodebuild build first or these stay skipped.
private let productsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("build/Build/Products/Debug", isDirectory: true)
private let appBundle = productsDirectory.appendingPathComponent("CCVigil.app", isDirectory: true)
private let daemonBinary = appBundle.appendingPathComponent("Contents/Library/LaunchAgents/CCVigilDaemon")
private let cliBinary = appBundle.appendingPathComponent("Contents/Helpers/cc-vigil")

private var builtProductsExist: Bool {
    FileManager.default.fileExists(atPath: daemonBinary.path)
        && FileManager.default.fileExists(atPath: cliBinary.path)
}

private enum HarnessError: Error, CustomStringConvertible {
    case daemonNeverReady(stderr: String)
    case statusNeverMatched(last: StatusReport?)

    var description: String {
        switch self {
        case let .daemonNeverReady(stderr):
            "daemon never answered ping; stderr: \(stderr)"
        case let .statusNeverMatched(last):
            "status never matched the predicate; last: \(String(describing: last))"
        }
    }
}

private final class DaemonHarness {
    let supportDir: ShortTempDir
    let transcriptsRoot: ShortTempDir
    let process: Process
    private let stderrBuffer = OSAllocatedUnfairLock<Data>(initialState: Data())

    var socketPath: String {
        SupportPaths(directory: supportDir.url).socketPath
    }

    init() throws {
        supportDir = try ShortTempDir(prefix: "vigil-it")
        transcriptsRoot = try ShortTempDir(prefix: "vigil-tr")
        let socket = SupportPaths(directory: supportDir.url).socketPath
        precondition(socket.utf8.count < 104, "socket path too long: \(socket)")
        process = Process()
        process.executableURL = daemonBinary
        process.arguments = [
            "--dry-run",
            "--transcripts-root", transcriptsRoot.url.path,
            "--support-dir", supportDir.url.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        let buffer = stderrBuffer
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            buffer.withLock { $0.append(data) }
        }
        process.standardError = stderrPipe
        try process.run()
    }

    func waitUntilReady() throws {
        let client = SocketClient(path: socketPath, timeoutSeconds: 1)
        for _ in 0 ..< 100 {
            if let reply = try? client.roundTrip(.ping), reply == .ok {
                return
            }
            usleep(100_000)
        }
        let stderr = stderrBuffer.withLock { String(data: $0, encoding: .utf8) ?? "" }
        throw HarnessError.daemonNeverReady(stderr: stderr)
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
        supportDir.tearDown()
        transcriptsRoot.tearDown()
    }
}

private func status(_ client: SocketClient) throws -> StatusReport {
    let reply = try client.roundTrip(.status)
    guard case let .status(report) = reply else {
        throw HarnessError.statusNeverMatched(last: nil)
    }
    return report
}

private func pollStatus(
    _ client: SocketClient,
    until predicate: (StatusReport) -> Bool
) throws -> StatusReport {
    var last: StatusReport?
    for _ in 0 ..< 100 {
        let report = try status(client)
        last = report
        if predicate(report) {
            return report
        }
        usleep(100_000)
    }
    throw HarnessError.statusNeverMatched(last: last)
}

private struct RunResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private func run(_ executable: URL, _ arguments: [String], stdin: Data? = nil) throws -> RunResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    if let stdin {
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        try process.run()
        stdinPipe.fileHandleForWriting.write(stdin)
        try stdinPipe.fileHandleForWriting.close()
    } else {
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }
    let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return RunResult(
        status: process.terminationStatus,
        stdout: String(data: stdout, encoding: .utf8) ?? "",
        stderr: String(data: stderr, encoding: .utf8) ?? ""
    )
}

@Suite(.enabled(if: builtProductsExist, "xcodebuild products missing; run the Debug build first"))
struct DaemonRoundTripTests {
    @Test func wireOpsRoundTripAgainstTheRealDaemon() throws {
        let harness = try DaemonHarness()
        defer { harness.stop() }
        try harness.waitUntilReady()
        let client = SocketClient(path: harness.socketPath)

        let initial = try status(client)
        #expect(initial.shouldBlock == false)
        #expect(initial.blockApplied == false)
        #expect(initial.helper == .dryRun)
        #expect(initial.holds.isEmpty)
        #expect(initial.pausedUntil == nil)

        #expect(try client.roundTrip(
            .hold(key: "itest", reason: "integration", ttlSeconds: 120, pid: nil)
        ) == .ok)
        let held = try pollStatus(client) { $0.shouldBlock && $0.blockApplied }
        #expect(held.holds.map(\.key) == ["itest"])
        #expect(held.holds.first?.reason == "integration")
        #expect(held.holds.first?.ttlSeconds == 120)

        #expect(try client.roundTrip(
            .nudge(NudgePayload(sessionId: "itest-session", hookEvent: "UserPromptSubmit"))
        ) == .ok)

        #expect(try client.roundTrip(.pause(seconds: 300)) == .ok)
        let paused = try pollStatus(client) { !$0.shouldBlock }
        #expect(paused.pausedUntil != nil)
        #expect(try client.roundTrip(.pause(seconds: 0)) == .ok)
        let resumed = try pollStatus(client) { $0.shouldBlock }
        #expect(resumed.pausedUntil == nil)

        #expect(try client.roundTrip(.release(key: "itest")) == .ok)
        let released = try pollStatus(client) { !$0.shouldBlock }
        #expect(released.holds.isEmpty)
        guard case let .error(message) = try client.roundTrip(.release(key: "itest")) else {
            Issue.record("second release should be an error")
            return
        }
        #expect(message.contains("itest"))

        // The uninstall clear latches the daemon fail-open; a passive status poll
        // does not lift that latch, so the block stays cleared.
        #expect(try client.roundTrip(.clear) == .ok)
        let cleared = try status(client)
        #expect(cleared.shouldBlock == false)
        #expect(cleared.blockApplied == false)

        // A subsequent control op is traffic that proves this was not an
        // uninstall: it un-latches the teardown, so the hold re-blocks.
        #expect(try client.roundTrip(
            .hold(key: "post-clear", reason: "re-block", ttlSeconds: 120, pid: nil)
        ) == .ok)
        let reblocked = try pollStatus(client) { $0.blockApplied && $0.holds.contains { $0.key == "post-clear" } }
        #expect(reblocked.shouldBlock)
        #expect(reblocked.blockApplied)
    }

    @Test func cliBinaryDrivesTheDaemon() throws {
        let harness = try DaemonHarness()
        defer { harness.stop() }
        try harness.waitUntilReady()
        let client = SocketClient(path: harness.socketPath)
        let socketArguments = ["--socket", harness.socketPath]

        let jsonRun = try run(cliBinary, ["status", "--json"] + socketArguments)
        #expect(jsonRun.status == 0)
        let report = try WireCodec.decodePayload(
            StatusReport.self,
            from: Data(jsonRun.stdout.utf8)
        )
        #expect(report.helper == .dryRun)

        let humanRun = try run(cliBinary, ["status"] + socketArguments)
        #expect(humanRun.status == 0)
        #expect(humanRun.stdout.contains("helper: dry-run"))
        #expect(humanRun.stdout.contains("blocking: no"))

        let holdRun = try run(
            cliBinary,
            ["hold", "--for", "2m", "--reason", "cli test", "--key", "cli-itest"] + socketArguments
        )
        #expect(holdRun.status == 0)
        #expect(holdRun.stdout.contains("holding cli-itest for 2m"))
        _ = try pollStatus(client) { report in report.holds.contains { $0.key == "cli-itest" } }

        let releaseRun = try run(cliBinary, ["release", "cli-itest"] + socketArguments)
        #expect(releaseRun.status == 0)
        #expect(releaseRun.stdout.contains("released cli-itest"))
        _ = try pollStatus(client) { $0.holds.isEmpty }

        let nudgeInput = Data(#"{"session_id":"it","hook_event_name":"Stop"}"#.utf8)
        let nudgeRun = try run(cliBinary, ["nudge"] + socketArguments, stdin: nudgeInput)
        #expect(nudgeRun.status == 0)
        #expect(nudgeRun.stdout.isEmpty)
        #expect(nudgeRun.stderr.isEmpty)

        let logRun = try run(cliBinary, ["log", "--support-dir", harness.supportDir.url.path])
        #expect(logRun.status == 0)
        #expect(logRun.stdout.contains("daemon-started"))

        let versionRun = try run(cliBinary, ["version"])
        #expect(versionRun.status == 0)
        #expect(versionRun.stdout.hasPrefix("cc-vigil "))
        #expect(versionRun.stdout.contains("."))
    }

    @Test func survivesFireAndForgetNudgePeers() throws {
        let harness = try DaemonHarness()
        defer { harness.stop() }
        try harness.waitUntilReady()
        let client = SocketClient(path: harness.socketPath)

        // The nudge hook fires and forgets: it writes the frame and closes before
        // the daemon replies. The daemon's reply to the gone peer must return
        // EPIPE, not raise SIGPIPE and terminate the process (exit 141).
        for index in 0 ..< 8 {
            try client.send(.nudge(NudgePayload(sessionId: "sigpipe-\(index)", hookEvent: "PreToolUse")))
        }

        // A fresh round-trip proves the daemon is still alive.
        #expect(try client.roundTrip(.ping) == .ok)
    }

    @Test func registersARelocatedTranscriptsRootCarriedByANudge() throws {
        let harness = try DaemonHarness()
        defer { harness.stop() }
        try harness.waitUntilReady()
        let client = SocketClient(path: harness.socketPath)
        let stateURL = SupportPaths(directory: harness.supportDir.url).stateURL

        let relocated = try ShortTempDir(prefix: "vigil-cfg")
        defer { relocated.tearDown() }
        let missing = relocated.url.appendingPathComponent("nope", isDirectory: true).path

        // A nonexistent dir is never registered; an existing one is, once.
        #expect(try client.roundTrip(.nudge(NudgePayload(transcriptsRoot: missing))) == .ok)
        #expect(try roots(from: stateURL) == [])
        #expect(try client.roundTrip(.nudge(NudgePayload(transcriptsRoot: relocated.url.path))) == .ok)
        #expect(try roots(from: stateURL) == [relocated.url.path])
        #expect(try client.roundTrip(.nudge(NudgePayload(transcriptsRoot: relocated.url.path))) == .ok)
        #expect(try roots(from: stateURL) == [relocated.url.path])
    }

    private func roots(from stateURL: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return [] }
        return try WireCodec.decodePayload(PersistedState.self, from: Data(contentsOf: stateURL)).registeredRoots
    }

    @Test func nudgeFailsOpenWithoutADaemon() throws {
        let dir = try ShortTempDir(prefix: "vigil-nod")
        defer { dir.tearDown() }
        let missingSocket = dir.socketPath("nope.sock")

        let nudgeRun = try run(
            cliBinary,
            ["nudge", "--socket", missingSocket],
            stdin: Data("not even json".utf8)
        )

        #expect(nudgeRun.status == 0)
        #expect(nudgeRun.stdout.isEmpty)
        #expect(nudgeRun.stderr.hasPrefix("cc-vigil: nudge failed:"))
        #expect(nudgeRun.stderr.count(where: { $0 == "\n" }) == 1)
    }

    @Test func installHooksEmbedsTheRealBinaryPathNeverTheSymlink() throws {
        let dir = try ShortTempDir(prefix: "vigil-hks")
        defer { dir.tearDown() }
        let link = dir.url.appendingPathComponent("cc-vigil-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cliBinary)
        let settings = dir.path("settings.json")

        let installRun = try run(link, ["install-hooks", "--settings", settings])
        #expect(installRun.status == 0)

        let realPath = cliBinary.resolvingSymlinksInPath().path
        let written = try String(contentsOfFile: settings, encoding: .utf8)
        #expect(written.contains(HookInstaller.command(cliPath: realPath)))
        #expect(!written.contains("cc-vigil-link"))
        #expect(installRun.stdout.contains(realPath))

        let uninstallRun = try run(link, ["uninstall-hooks", "--settings", settings])
        #expect(uninstallRun.status == 0)
        let after = try String(contentsOfFile: settings, encoding: .utf8)
        #expect(!after.contains("_cc_vigil"))
    }
}
