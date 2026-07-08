import os

enum BlockPushOutcome: Equatable, Sendable {
    case applied(Bool)
    case unsettled(applied: Bool, detail: String)
    case failed(String)
    case unavailable(String)
}

protocol BlockPushing: Sendable {
    func push(blocked: Bool) async -> BlockPushOutcome
}

struct LogOnlyBlockPusher: BlockPushing {
    func push(blocked: Bool) async -> BlockPushOutcome {
        print("cc-vigil dry-run: setSleepBlocked(\(blocked))")
        Logger.helperClient.info("dry-run: setSleepBlocked(\(blocked, privacy: .public))")
        return .applied(blocked)
    }
}
