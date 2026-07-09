import Foundation

public enum HookInstallerError: Error, Equatable {
    case unparseable
    case rootNotObject
    case malformedHooks(String)
}

public enum HookInstallState: String, Equatable, Sendable {
    case installed
    case notInstalled
    case modifiedExternally
}

public enum HookInstaller {
    public static let hookEvents = ["UserPromptSubmit", "PreToolUse", "Stop", "SubagentStop", "Notification"]
    public static let tagKey = "_cc_vigil"

    public static func command(cliPath: String) -> String {
        "\(cliPath) nudge"
    }

    public static func install(into settings: Data?, cliPath: String) throws -> Data {
        var root = try parseRoot(settings)
        var hooks = try root["hooks"].map { try objectValue($0, context: "hooks") } ?? [:]
        let expected = handlerEntry(cliPath: cliPath)
        for (event, value) in hooks {
            let groups = try groupList(value, event: event)
            let rewritten = hookEvents.contains(event)
                ? try repair(groups, expected: expected, event: event)
                : try strip(groups, event: event)
            if rewritten.isEmpty, !groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = rewritten
            }
        }
        for event in hookEvents where hooks[event] == nil {
            hooks[event] = [["hooks": [expected]]]
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    public static func remove(from settings: Data) throws -> Data {
        var root = try parseRoot(settings)
        guard let hooksValue = root["hooks"] else { return try serialize(root) }
        var hooks = try objectValue(hooksValue, context: "hooks")
        let hadEvents = !hooks.isEmpty
        for (event, value) in hooks {
            let groups = try groupList(value, event: event)
            let stripped = try strip(groups, event: event)
            if stripped.isEmpty, !groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = stripped
            }
        }
        if hooks.isEmpty, hadEvents {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return try serialize(root)
    }

    public static func state(of settings: Data?, cliPath: String) throws -> HookInstallState {
        guard let settings else { return .notInstalled }
        let root = try parseRoot(settings)
        guard let hooksValue = root["hooks"] else { return .notInstalled }
        let hooks = try objectValue(hooksValue, context: "hooks")
        var taggedByEvent: [String: [[String: Any]]] = [:]
        for (event, value) in hooks {
            let tagged = try groupList(value, event: event)
                .flatMap { try handlerList($0, event: event) }
                .filter(isTagged)
            if !tagged.isEmpty {
                taggedByEvent[event] = tagged
            }
        }
        guard !taggedByEvent.isEmpty else { return .notInstalled }
        guard taggedByEvent.count == hookEvents.count else { return .modifiedExternally }
        let expected = handlerEntry(cliPath: cliPath)
        let exact = hookEvents.allSatisfy { event in
            guard let tagged = taggedByEvent[event], tagged.count == 1 else { return false }
            return NSDictionary(dictionary: tagged[0]).isEqual(to: expected)
        }
        return exact ? .installed : .modifiedExternally
    }

    private static func handlerEntry(cliPath: String) -> [String: Any] {
        ["type": "command", "command": command(cliPath: cliPath), tagKey: true]
    }

    private static func isTagged(_ handler: [String: Any]) -> Bool {
        handler[tagKey] as? Bool == true
    }

    private static func repair(
        _ groups: [[String: Any]],
        expected: [String: Any],
        event: String
    ) throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        var repairedOne = false
        for group in groups {
            let handlers: [[String: Any]] = try handlerList(group, event: event).compactMap { handler in
                guard isTagged(handler) else { return handler }
                guard !repairedOne else { return nil }
                repairedOne = true
                return expected
            }
            guard !handlers.isEmpty else { continue }
            var group = group
            group["hooks"] = handlers
            result.append(group)
        }
        if !repairedOne {
            result.append(["hooks": [expected]])
        }
        return result
    }

    private static func strip(_ groups: [[String: Any]], event: String) throws -> [[String: Any]] {
        try groups.compactMap { group in
            let handlers = try handlerList(group, event: event).filter { !isTagged($0) }
            guard !handlers.isEmpty else { return nil }
            var group = group
            group["hooks"] = handlers
            return group
        }
    }

    private static func parseRoot(_ settings: Data?) throws -> [String: Any] {
        guard let settings else { return [:] }
        guard let parsed = try? JSONSerialization.jsonObject(with: settings, options: [.fragmentsAllowed]) else {
            throw HookInstallerError.unparseable
        }
        guard let root = parsed as? [String: Any] else {
            throw HookInstallerError.rootNotObject
        }
        return root
    }

    private static func objectValue(_ value: Any, context: String) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw HookInstallerError.malformedHooks(context)
        }
        return object
    }

    private static func groupList(_ value: Any, event: String) throws -> [[String: Any]] {
        guard let list = value as? [Any] else {
            throw HookInstallerError.malformedHooks("hooks.\(event)")
        }
        return try list.map { try objectValue($0, context: "hooks.\(event)[]") }
    }

    private static func handlerList(_ group: [String: Any], event: String) throws -> [[String: Any]] {
        guard let value = group["hooks"], let list = value as? [Any] else {
            throw HookInstallerError.malformedHooks("hooks.\(event)[].hooks")
        }
        return try list.map { try objectValue($0, context: "hooks.\(event)[].hooks[]") }
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }
}
