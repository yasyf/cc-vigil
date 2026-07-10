import Foundation

/// The Claude Code process a session's most recent nudge reported, and the epoch
/// at which we captured it. `capturedAtEpoch` is what the PID-reuse defense
/// compares a process's start time against: a process that started after we
/// captured the pid is a different process wearing the recycled number.
public struct TrackedPid: Equatable, Sendable {
    public let pid: Int32
    public let capturedAtEpoch: Int64

    public init(pid: Int32, capturedAtEpoch: Int64) {
        self.pid = pid
        self.capturedAtEpoch = capturedAtEpoch
    }
}

public struct SessionPidTracker: Equatable, Sendable {
    public private(set) var pidsBySessionID: [String: TrackedPid] = [:]

    public init() {}

    /// The pid rides on whatever nudge carried it, so `apply` keys on the pid's
    /// presence rather than on any particular hook event, latest-wins per
    /// session. A nudge without a pid carries no evidence about the process and
    /// leaves an existing entry untouched.
    public mutating func apply(_ nudge: NudgePayload, now: Date) {
        guard let sessionID = nudge.sessionId, let pid = nudge.claudePid else { return }
        pidsBySessionID[sessionID] = TrackedPid(pid: pid, capturedAtEpoch: Int64(now.timeIntervalSince1970))
    }

    /// Reclaims entries the map would otherwise hold for the life of the daemon,
    /// at the collect-decision cadence. An entry is dropped only when it is both
    /// no longer live — a vanished pid (dead) or one recycled by a later process
    /// (ghost), the exact complement of `liveSessionIDs` — and captured before
    /// `cutoffEpoch`, which the caller sets to the discovery window: past it the
    /// mtime window has already dropped the transcript, so the mapping can never
    /// pin anything again and simply reverts the session to unmapped cliff
    /// behavior. A live session is kept regardless of age, since its long-running
    /// process is exactly what the pin protects, and a recently-captured dead
    /// entry is kept so a just-ended session is not evicted ahead of its
    /// transcript. `processStart` floors to whole seconds like `liveSessionIDs`.
    public mutating func prune(capturedBefore cutoffEpoch: Int64, processStart: (Int32) -> Int64?) {
        pidsBySessionID = pidsBySessionID.filter { _, tracked in
            if tracked.capturedAtEpoch >= cutoffEpoch {
                return true
            }
            guard let started = processStart(tracked.pid) else { return false }
            return started <= tracked.capturedAtEpoch
        }
    }

    public func pids(forPaths paths: [String]) -> [String: TrackedPid] {
        var pids: [String: TrackedPid] = [:]
        for path in paths {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let tracked = pidsBySessionID[stem] {
                pids[path] = tracked
            }
        }
        return pids
    }

    /// The PID-reuse defense from `HoldRegistry.restored`: a session is live only
    /// when its pid still resolves and the process did not start after we captured
    /// the pid. A missing start means the process is gone (dead); a start strictly
    /// later than capture means the number was recycled by a different process
    /// (ghost). Equality at the capture instant is ambiguous, and a sleep
    /// inhibitor resolves ambiguity toward live — it must never sleep the Mac on
    /// it. `processStart` returns whole-second epochs so the comparison stays in
    /// `capturedAtEpoch`'s units, where a sub-second-later start within the same
    /// second reads as the same live process rather than a reuse ghost.
    public func liveSessionIDs(processStart: (Int32) -> Int64?) -> Set<String> {
        var live: Set<String> = []
        for (sessionID, tracked) in pidsBySessionID {
            guard let started = processStart(tracked.pid) else { continue }
            if started <= tracked.capturedAtEpoch {
                live.insert(sessionID)
            }
        }
        return live
    }
}
