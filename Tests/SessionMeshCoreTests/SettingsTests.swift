import Foundation
import Testing
@testable import SessionMeshCore

private let iterm2Command = "/Users/test/.config/iterm2/cc-status"
private let meshCommand = "/Users/test/.claude/session-mesh/bin/session-mesh hook-start"

private struct Fixture {
    let directory: URL
    let settingsURL: URL
    let backupDirectory: URL

    init(settingsJSON: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-mesh-tests-\(UUID().uuidString)", isDirectory: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        backupDirectory = directory.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let settingsJSON {
            try settingsJSON.write(to: settingsURL, atomically: true, encoding: .utf8)
        }
    }

    func cleanup() throws {
        try FileManager.default.removeItem(at: directory)
    }
}

private func makeSettingsJSON(hooks: [String: Any]? = nil) throws -> String {
    let root: [String: Any] = [
        "env": ["SAMPLE_MODEL": "sample-model"],
        "model": "sample-model",
        "hooks": hooks ?? [
            "SessionStart": [
                ["hooks": [["type": "command", "command": iterm2Command]]]
            ]
        ]
    ]
    let data = try JSONSerialization.data(
        withJSONObject: root,
        options: [.sortedKeys, .prettyPrinted]
    )
    return String(decoding: data, as: UTF8.self)
}

@Test func mergePreservesExistingHookEntries() throws {
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON())
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let merged = try store.mergedSettings(
        adding: [SettingsChange(hookEvent: "SessionStart", command: meshCommand)]
    )

    let hooks = try #require(merged["hooks"] as? [String: Any])
    let groups = try #require(hooks["SessionStart"] as? [[String: Any]])
    #expect(groups.count == 2)

    let existingGroup = try #require(groups.first)
    let existingHooks = try #require(existingGroup["hooks"] as? [[String: Any]])
    let existingCommand = try #require(existingHooks.first?["command"] as? String)
    #expect(existingCommand == iterm2Command)

    let addedHooks = try #require(groups.last?["hooks"] as? [[String: Any]])
    let addedCommand = try #require(addedHooks.first?["command"] as? String)
    #expect(addedCommand == meshCommand)
}

@Test func mergeAddsEntriesForMissingEvents() throws {
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON(hooks: [:]))
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let merged = try store.mergedSettings(
        adding: [SettingsChange(hookEvent: "Stop", command: meshCommand)]
    )

    let hooks = try #require(merged["hooks"] as? [String: Any])
    let groups = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(groups.count == 1)
}

@Test func mergeKeepsUnrelatedTopLevelKeys() throws {
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON())
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let merged = try store.mergedSettings(
        adding: [SettingsChange(hookEvent: "SessionStart", command: meshCommand)]
    )

    #expect(merged["model"] as? String == "sample-model")
    let env = try #require(merged["env"] as? [String: Any])
    #expect(env["SAMPLE_MODEL"] as? String == "sample-model")
}

@Test func mergeIsIdempotent() throws {
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON())
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let change = SettingsChange(hookEvent: "SessionStart", command: meshCommand)
    let once = try store.mergedSettings(adding: [change])
    let twice = try store.mergedSettings(adding: [change, change])

    let onceGroups = try #require((once["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]])
    let twiceGroups = try #require((twice["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]])
    #expect(onceGroups.count == 2)
    #expect(twiceGroups.count == 2)
}

@Test func mergeLeavesFileUnchanged() throws {
    let original = try makeSettingsJSON()
    let fixture = try Fixture(settingsJSON: original)
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    _ = try store.mergedSettings(
        adding: [SettingsChange(hookEvent: "SessionStart", command: meshCommand)]
    )

    let onDisk = try String(contentsOf: fixture.settingsURL, encoding: .utf8)
    #expect(onDisk == original)
}

@Test func mergeWorksWhenSettingsFileIsMissing() throws {
    let fixture = try Fixture()
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let merged = try store.mergedSettings(
        adding: [SettingsChange(hookEvent: "SessionStart", command: meshCommand)]
    )

    let hooks = try #require(merged["hooks"] as? [String: Any])
    #expect((hooks["SessionStart"] as? [[String: Any]])?.count == 1)
}

@Test func backupWritesTimestampedFileWithShaSidecar() throws {
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON())
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let backupURL = try store.makeBackup()

    #expect(backupURL.deletingLastPathComponent() == fixture.backupDirectory)
    #expect(backupURL.lastPathComponent.hasPrefix("settings-"))
    #expect(backupURL.lastPathComponent.hasSuffix(".json"))

    let sidecar = URL(fileURLWithPath: backupURL.path + ".sha256")
    let digest = try String(contentsOf: sidecar, encoding: .utf8)
    #expect(digest.trimmingCharacters(in: .whitespacesAndNewlines).count == 64)

    let backupData = try Data(contentsOf: backupURL)
    let originalData = try Data(contentsOf: fixture.settingsURL)
    #expect(backupData == originalData)

    let fileAttributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
    #expect(fileAttributes[.posixPermissions] as? Int == 0o600)
    let directoryAttributes = try FileManager.default
        .attributesOfItem(atPath: fixture.backupDirectory.path)
    #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
}

@Test func backupUsesCustomNamePrefix() throws {
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON())
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory,
        backupNamePrefix: "settings.local"
    )
    let backupURL = try store.makeBackup()

    #expect(backupURL.lastPathComponent.hasPrefix("settings.local-"))
    #expect(backupURL.lastPathComponent.hasSuffix(".json"))
}

@Test func applyReadOnlyModesWriteNothing() throws {
    let original = try makeSettingsJSON()
    let fixture = try Fixture(settingsJSON: original)
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let change = SettingsChange(hookEvent: "SessionStart", command: meshCommand)

    for mode in [InstallMode.dryRun, InstallMode.check] {
        let backupURL = try store.apply(changes: [change], mode: mode)
        #expect(backupURL == nil)
    }

    let onDisk = try String(contentsOf: fixture.settingsURL, encoding: .utf8)
    #expect(onDisk == original)
}

@Test func applyModeBacksUpThenWritesMergedSettings() throws {
    let original = try makeSettingsJSON()
    let fixture = try Fixture(settingsJSON: original)
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let backupURL = try store.apply(
        changes: [SettingsChange(hookEvent: "SessionStart", command: meshCommand)],
        mode: .apply
    )
    let backup = try #require(backupURL)
    let backupContent = try String(contentsOf: backup, encoding: .utf8)
    #expect(backupContent == original)

    let reloaded = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let merged = try reloaded.readSettings()
    let groups = try #require(
        (merged["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]]
    )
    #expect(groups.count == 2)
}

@Test func applyCreatesSettingsFileWhenMissing() throws {
    let fixture = try Fixture()
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let backupURL = try store.apply(
        changes: [SettingsChange(hookEvent: "SessionStart", command: meshCommand)],
        mode: .apply
    )
    #expect(backupURL != nil)
    #expect(FileManager.default.fileExists(atPath: fixture.settingsURL.path))

    let reloaded = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let settings = try reloaded.readSettings()
    let groups = try #require(
        (settings["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]]
    )
    #expect(groups.count == 1)
}

@Test func removalRequiresTokenBoundary() throws {
    let binary = "/Users/test/.claude/session-mesh/bin/session-mesh"
    let hooks: [String: Any] = [
        "SessionStart": [
            ["hooks": [["type": "command", "command": "\(binary) hook-start"]]],
            ["hooks": [["type": "command", "command": "\(binary)-helper"]]],
            ["hooks": [["type": "command", "command": iterm2Command]]]
        ]
    ]
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON(hooks: hooks))
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let remaining = try store.settingsWithoutOwnedHooks(matchingBinaryPath: binary)
    let kept = try #require(
        (remaining["hooks"] as? [String: Any])?["SessionStart"] as? [[String: Any]]
    )
    #expect(kept.count == 2)
    let commands = kept.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
        .compactMap { $0["command"] as? String }
    #expect(commands.contains("\(binary)-helper"))
    #expect(commands.contains(iterm2Command))
    #expect(!commands.contains("\(binary) hook-start"))
}

@Test func ownedHookDetectionRequiresTokenBoundary() throws {
    let binary = "/Users/test/.claude/session-mesh/bin/session-mesh"
    let hooks: [String: Any] = [
        "Stop": [["hooks": [["type": "command", "command": "\(binary)-helper"]]]]
    ]
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON(hooks: hooks))
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let events = try store.hookEventsContaining(binaryPath: binary)
    #expect(events == [])
}

@Test func mergeAddsPreToolUseMatcherGroup() throws {
    let binary = "/Users/test/.claude/session-mesh/bin/session-mesh"
    let hooks: [String: Any] = [
        "PreToolUse": [["hooks": [["type": "command", "command": iterm2Command]]]]
    ]
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON(hooks: hooks))
    defer { try? fixture.cleanup() }
    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )

    let merged = try store.mergedSettings(
        adding: [
            SettingsChange(
                hookEvent: "PreToolUse",
                matcher: "CreateSession|CreateSessions",
                command: "\(binary) hook-guard"
            )
        ]
    )

    let mergedHooks = try #require(merged["hooks"] as? [String: Any])
    let groups = try #require(mergedHooks["PreToolUse"] as? [[String: Any]])
    #expect(groups.count == 2)
    let added = try #require(groups.last)
    #expect(added["matcher"] as? String == "CreateSession|CreateSessions")
    let addedCommand = try #require(
        (added["hooks"] as? [[String: Any]])?.first?["command"] as? String
    )
    #expect(addedCommand == "\(binary) hook-guard")
}

@Test func applySerializesConcurrentSettingsWrites() throws {
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON())
    defer { try? fixture.cleanup() }
    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let change = SettingsChange(hookEvent: "Stop", command: meshCommand)

    let queue = DispatchQueue(label: "session-mesh-settings", attributes: .concurrent)
    let group = DispatchGroup()
    for _ in 0..<8 {
        group.enter()
        queue.async {
            _ = try? store.apply(changes: [change], mode: .apply)
            group.leave()
        }
    }
    group.wait()

    let lockURL = fixture.backupDirectory.appendingPathComponent(".settings.lock")
    #expect(FileManager.default.fileExists(atPath: lockURL.path))
    let lockAttributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
    #expect((lockAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    let data = try Data(contentsOf: fixture.settingsURL)
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stopGroups.count == 1)
    let backups = try FileManager.default.contentsOfDirectory(atPath: fixture.backupDirectory.path)
        .filter { $0.hasSuffix(".json") }
    #expect(backups.count == 8)
}

@Test func mergeRejectsNonObjectHooksValue() throws {
    let fixture = try Fixture(settingsJSON: #"{"hooks":["invalid"]}"#)
    defer { try? fixture.cleanup() }
    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )

    #expect(throws: SettingsStoreError.self) {
        _ = try store.mergedSettings(
            adding: [SettingsChange(hookEvent: "Stop", command: meshCommand)]
        )
    }
}

@Test func mergePreservesUnmergeableHookValues() throws {
    let hooks: [String: Any] = [
        "Stop": "not-an-array",
        "SessionEnd": ["hooks": [["type": "command", "command": iterm2Command]]]
    ]
    let fixture = try Fixture(settingsJSON: try makeSettingsJSON(hooks: hooks))
    defer { try? fixture.cleanup() }

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let merged = try store.mergedSettings(
        adding: [
            SettingsChange(hookEvent: "Stop", command: meshCommand),
            SettingsChange(hookEvent: "SessionEnd", command: meshCommand)
        ]
    )
    let mergedHooks = try #require(merged["hooks"] as? [String: Any])
    #expect(mergedHooks["Stop"] as? String == "not-an-array")
    let sessionEnd = try #require(mergedHooks["SessionEnd"] as? [[String: Any]])
    #expect(sessionEnd.count == 2)
    let firstCommand = try #require(
        (sessionEnd.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
    )
    #expect(firstCommand == iterm2Command)
}
