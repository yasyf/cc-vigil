import CCVigilShared
import Foundation
import Testing

private let cliPath = "/Applications/CCVigil.app/Contents/Helpers/cc-vigil"
private let nudge = "\(cliPath) nudge"

private func parsed(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private func vigilGroup(command: String = nudge) -> [String: Any] {
    ["hooks": [["type": "command", "command": command, "_cc_vigil": true]]]
}

private func settings(_ json: String) -> Data {
    Data(json.utf8)
}

@Test func installerCommandAppendsNudgeVerb() {
    #expect(HookInstaller.command(cliPath: "/usr/local/bin/cc-vigil") == "/usr/local/bin/cc-vigil nudge")
}

@Test func installIntoMissingFileCreatesAllFourEvents() throws {
    let result = try HookInstaller.install(into: nil, cliPath: cliPath)
    let expected: NSDictionary = [
        "hooks": [
            "UserPromptSubmit": [vigilGroup()],
            "Stop": [vigilGroup()],
            "SubagentStop": [vigilGroup()],
            "Notification": [vigilGroup()],
        ],
    ]
    #expect(try parsed(result) == expected)
    #expect(try HookInstaller.state(of: result, cliPath: cliPath) == .installed)
}

@Test func installPreservesUnrelatedSettingsAndUserHooks() throws {
    let original = settings(#"""
    {
      "model": "opus",
      "permissions": {"allow": ["Bash(ls:*)"]},
      "hooks": {
        "Stop": [{"hooks": [{"type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff"}]}],
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "my-guard"}]}]
      }
    }
    """#)
    let result = try HookInstaller.install(into: original, cliPath: cliPath)
    let expected: NSDictionary = [
        "model": "opus",
        "permissions": ["allow": ["Bash(ls:*)"]],
        "hooks": [
            "Stop": [
                ["hooks": [["type": "command", "command": "afplay /System/Library/Sounds/Glass.aiff"]]],
                vigilGroup(),
            ],
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-guard"]]]],
            "UserPromptSubmit": [vigilGroup()],
            "SubagentStop": [vigilGroup()],
            "Notification": [vigilGroup()],
        ],
    ]
    #expect(try parsed(result) == expected)
    #expect(try HookInstaller.state(of: result, cliPath: cliPath) == .installed)
}

@Test func installRepairsTamperedHandlerInPlace() throws {
    let original = settings(#"""
    {
      "hooks": {
        "Stop": [
          {"hooks": [
            {"type": "command", "command": "user-first"},
            {"type": "command", "command": "stale-path nudge", "_cc_vigil": true},
            {"type": "command", "command": "user-last"}
          ]}
        ]
      }
    }
    """#)
    let result = try HookInstaller.install(into: original, cliPath: cliPath)
    let root = try parsed(result)
    let stopGroups = try #require((root["hooks"] as? NSDictionary)?["Stop"] as? [NSDictionary])
    #expect(stopGroups.count == 1)
    let handlers = try #require(stopGroups[0]["hooks"] as? [NSDictionary])
    #expect(handlers == [
        ["type": "command", "command": "user-first"],
        ["type": "command", "command": nudge, "_cc_vigil": true],
        ["type": "command", "command": "user-last"],
    ])
    #expect(try HookInstaller.state(of: result, cliPath: cliPath) == .installed)
}

@Test func installDropsDuplicateTaggedHandlers() throws {
    let original = settings(#"""
    {
      "hooks": {
        "Stop": [
          {"hooks": [{"type": "command", "command": "a nudge", "_cc_vigil": true}]},
          {"hooks": [{"type": "command", "command": "b nudge", "_cc_vigil": true}]}
        ]
      }
    }
    """#)
    let result = try HookInstaller.install(into: original, cliPath: cliPath)
    let root = try parsed(result)
    let stopGroups = try #require((root["hooks"] as? NSDictionary)?["Stop"] as? [NSDictionary])
    #expect(stopGroups == [vigilGroup() as NSDictionary])
}

@Test func installRemovesStrayTaggedHandlersFromOtherEvents() throws {
    let original = settings(#"""
    {
      "hooks": {
        "PreToolUse": [
          {"matcher": "Bash", "hooks": [
            {"type": "command", "command": "my-guard"},
            {"type": "command", "command": "old nudge", "_cc_vigil": true}
          ]},
          {"hooks": [{"type": "command", "command": "old nudge", "_cc_vigil": true}]}
        ]
      }
    }
    """#)
    let result = try HookInstaller.install(into: original, cliPath: cliPath)
    let root = try parsed(result)
    let preToolUse = try #require((root["hooks"] as? NSDictionary)?["PreToolUse"] as? [NSDictionary])
    #expect(preToolUse == [
        ["matcher": "Bash", "hooks": [["type": "command", "command": "my-guard"]]],
    ])
    #expect(try HookInstaller.state(of: result, cliPath: cliPath) == .installed)
}

@Test func installIsIdempotent() throws {
    let once = try HookInstaller.install(into: nil, cliPath: cliPath)
    let twice = try HookInstaller.install(into: once, cliPath: cliPath)
    #expect(once == twice)
}

@Test(arguments: [
    ("not json {", HookInstallerError.unparseable),
    ("[1, 2]", HookInstallerError.rootNotObject),
    (#""just a string""#, HookInstallerError.rootNotObject),
    (#"{"hooks": 5}"#, HookInstallerError.malformedHooks("hooks")),
    (#"{"hooks": {"Stop": 5}}"#, HookInstallerError.malformedHooks("hooks.Stop")),
    (#"{"hooks": {"Stop": [{"matcher": "x"}]}}"#, HookInstallerError.malformedHooks("hooks.Stop[].hooks")),
])
func installRefusesMalformedSettings(json: String, expected: HookInstallerError) {
    #expect(throws: expected) {
        try HookInstaller.install(into: settings(json), cliPath: cliPath)
    }
}

@Test func removeFromFreshInstallDropsHooksKeyEntirely() throws {
    let installed = try HookInstaller.install(into: nil, cliPath: cliPath)
    let removed = try HookInstaller.remove(from: installed)
    #expect(try parsed(removed) == [:])
    #expect(try HookInstaller.state(of: removed, cliPath: cliPath) == .notInstalled)
}

@Test func removePreservesUserHooksAndSiblings() throws {
    let original = settings(#"""
    {
      "model": "opus",
      "hooks": {
        "Stop": [{"hooks": [
          {"type": "command", "command": "user-handler"},
          {"type": "command", "command": "old nudge", "_cc_vigil": true}
        ]}],
        "Notification": [{"hooks": [{"type": "command", "command": "old nudge", "_cc_vigil": true}]}],
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "my-guard"}]}]
      }
    }
    """#)
    let removed = try HookInstaller.remove(from: original)
    let expected: NSDictionary = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "user-handler"]]]],
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-guard"]]]],
        ],
    ]
    #expect(try parsed(removed) == expected)
    #expect(try HookInstaller.state(of: removed, cliPath: cliPath) == .notInstalled)
}

@Test func removeKeepsPreexistingEmptyContainers() throws {
    let original = settings(#"{"hooks": {"Stop": []}}"#)
    let removed = try HookInstaller.remove(from: original)
    #expect(try parsed(removed) == ["hooks": ["Stop": []]])
}

@Test func removeWithoutHooksKeyLeavesSettingsAlone() throws {
    let original = settings(#"{"model": "opus"}"#)
    let removed = try HookInstaller.remove(from: original)
    #expect(try parsed(removed) == ["model": "opus"])
}

@Test func stateOfMissingFileIsNotInstalled() throws {
    #expect(try HookInstaller.state(of: nil, cliPath: cliPath) == .notInstalled)
}

@Test func stateWithoutTaggedHandlersIsNotInstalled() throws {
    let data = settings(#"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "user"}]}]}}"#)
    #expect(try HookInstaller.state(of: data, cliPath: cliPath) == .notInstalled)
}

@Test func stateDetectsTamperedCommand() throws {
    let installed = try HookInstaller.install(into: nil, cliPath: cliPath)
    let installedJSON = try #require(String(bytes: installed, encoding: .utf8))
    let tampered = settings(installedJSON.replacingOccurrences(of: nudge, with: "evil nudge"))
    #expect(try HookInstaller.state(of: tampered, cliPath: cliPath) == .modifiedExternally)
}

@Test func stateDetectsMissingEvent() throws {
    let data = settings(#"""
    {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\#(nudge)", "_cc_vigil": true}]}]}}
    """#)
    #expect(try HookInstaller.state(of: data, cliPath: cliPath) == .modifiedExternally)
}

@Test func stateDetectsDuplicateTaggedHandlers() throws {
    let installed = try HookInstaller.install(into: nil, cliPath: cliPath)
    var root = try #require(JSONSerialization.jsonObject(with: installed) as? [String: Any])
    var hooks = try #require(root["hooks"] as? [String: Any])
    var stop = try #require(hooks["Stop"] as? [[String: Any]])
    stop.append(stop[0])
    hooks["Stop"] = stop
    root["hooks"] = hooks
    let duplicated = try JSONSerialization.data(withJSONObject: root)
    #expect(try HookInstaller.state(of: duplicated, cliPath: cliPath) == .modifiedExternally)
}

@Test func stateDetectsStrayTaggedHandler() throws {
    let installed = try HookInstaller.install(into: nil, cliPath: cliPath)
    var root = try #require(JSONSerialization.jsonObject(with: installed) as? [String: Any])
    var hooks = try #require(root["hooks"] as? [String: Any])
    hooks["PreToolUse"] = [vigilGroup()]
    root["hooks"] = hooks
    let strayed = try JSONSerialization.data(withJSONObject: root)
    #expect(try HookInstaller.state(of: strayed, cliPath: cliPath) == .modifiedExternally)
}

@Test func stateRefusesGarbage() {
    #expect(throws: HookInstallerError.unparseable) {
        try HookInstaller.state(of: settings("not json {"), cliPath: cliPath)
    }
}
