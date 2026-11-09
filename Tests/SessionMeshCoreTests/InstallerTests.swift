import Foundation
import Testing
@testable import SessionMeshCore

private let iterm2Command = "/Users/test/.config/iterm2/cc-status"

private struct InstallFixture {
    let directory: URL
    let settingsURL: URL
    let backupDirectory: URL
    let binarySource: URL
    let binaryDestination: URL
    let skillSource: URL

    var skillDestination: URL {
        directory.appendingPathComponent(".claude/skills/session-mesh/SKILL.md")
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-mesh-installer-tests-\(UUID().uuidString)", isDirectory: true)
        settingsURL = directory.appendingPathComponent(".claude/settings.local.json")
        backupDirectory = directory.appendingPathComponent("backup", isDirectory: true)
        binarySource = directory.appendingPathComponent("source-bin", isDirectory: true)
        binaryDestination = directory.appendingPathComponent("bin/session-mesh")
        skillSource = directory.appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
    }

    func cleanup() throws {
        try FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    func writeSettings(hooks: [String: Any]? = nil, extraKeys: [String: Any] = [:]) throws -> String {
        var root: [String: Any] = [
            "model": "sample-model",
            "hooks": hooks ?? [
                "SessionStart": [["hooks": [["type": "command", "command": iterm2Command]]]],
                "Notification": [["hooks": [["type": "command", "command": iterm2Command]]]]
            ]
        ]
        for (key, value) in extraKeys {
            root[key] = value
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])
        let text = String(decoding: data, as: UTF8.self)
        try text.write(to: settingsURL, atomically: true, encoding: .utf8)
        return text
    }
}

private func makeInstaller(_ fixture: InstallFixture) -> Installer {
    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory,
        backupNamePrefix: "settings.local"
    )
    return Installer(
        settingsStore: store,
        scope: .project,
        projectRoot: fixture.directory,
        binarySource: fixture.binarySource,
        binaryDestination: fixture.binaryDestination,
        skillSource: fixture.skillSource
    )
}

private func readHooks(_ fixture: InstallFixture) throws -> [String: Any] {
    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let settings = try store.readSettings()
    return (settings["hooks"] as? [String: Any]) ?? [:]
}

@Test func installDryRunWritesNothing() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    let original = try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)
    try Data("# skill".utf8).write(to: fixture.skillSource)

    let plan = try makeInstaller(fixture).install(mode: .dryRun)

    #expect(plan.notes.contains { $0.hasPrefix("binary destination:") && $0.contains("missing") })
    #expect(!FileManager.default.fileExists(atPath: fixture.binaryDestination.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.skillDestination.path))
    let onDisk = try String(contentsOf: fixture.settingsURL, encoding: .utf8)
    #expect(onDisk == original)
}

@Test func installApplyCopiesBinarySkillAndMergesHooks() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)
    try Data("# skill".utf8).write(to: fixture.skillSource)

    let plan = try makeInstaller(fixture).install(mode: .apply)

    #expect(FileManager.default.fileExists(atPath: fixture.binaryDestination.path))
    let binaryAttributes = try FileManager.default
        .attributesOfItem(atPath: fixture.binaryDestination.path)
    #expect(binaryAttributes[.posixPermissions] as? Int == 0o700)
    #expect(FileManager.default.fileExists(atPath: fixture.skillDestination.path))

    let hooks = try readHooks(fixture)
    for event in ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "PreToolUse"] {
        #expect((hooks[event] as? [[String: Any]]) != nil)
    }
    #expect((hooks["SessionStart"] as? [[String: Any]])?.count == 2)
    #expect((hooks["Notification"] as? [[String: Any]])?.count == 1)
    let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
    #expect(preToolUse.contains { $0["matcher"] as? String == "CreateSession|CreateSessions" })

    let backup = try #require(plan.settingsBackupURL)
    #expect(FileManager.default.fileExists(atPath: backup.path))
    #expect(backup.lastPathComponent.hasPrefix("settings.local-"))
    #expect(plan.scope == .project)
    #expect(plan.projectRoot == fixture.directory)
    #expect(plan.settingsURL == fixture.settingsURL)
    #expect(plan.skillDestination == fixture.skillDestination)
}

@Test func installReplacesExistingBinaryAndSkill() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)
    try Data("# skill".utf8).write(to: fixture.skillSource)
    try FileManager.default.createDirectory(
        at: fixture.binaryDestination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("old-binary".utf8).write(to: fixture.binaryDestination)
    try FileManager.default.createDirectory(
        at: fixture.skillDestination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("old-skill".utf8).write(to: fixture.skillDestination)

    _ = try makeInstaller(fixture).install(mode: .apply)

    #expect(try String(contentsOf: fixture.binaryDestination, encoding: .utf8) == "fake-binary")
    #expect(try String(contentsOf: fixture.skillDestination, encoding: .utf8) == "# skill")
}

@Test func installRejectsInvalidHooksBeforeWritingFiles() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try Data(#"{"hooks":["invalid"]}"#.utf8).write(to: fixture.settingsURL)
    try Data("fake-binary".utf8).write(to: fixture.binarySource)
    try Data("# skill".utf8).write(to: fixture.skillSource)

    #expect(throws: SettingsStoreError.self) {
        _ = try makeInstaller(fixture).install(mode: .apply)
    }

    #expect(!FileManager.default.fileExists(atPath: fixture.binaryDestination.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.skillDestination.path))
}

@Test func installSkipsMissingSkillSource() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)

    let plan = try makeInstaller(fixture).install(mode: .apply)

    #expect(plan.skillSource == nil)
    #expect(!FileManager.default.fileExists(atPath: fixture.skillDestination.path))
}

@Test func installCheckReportsStateWithoutWrites() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)

    let installer = makeInstaller(fixture)
    let before = try installer.check()
    #expect(before.notes.contains { $0 == "mesh hook events: none" })

    _ = try installer.install(mode: .apply)
    let after = try installer.check()
    #expect(after.notes.contains { $0.hasPrefix("binary destination:") && $0.contains("present") })
    #expect(
        after.notes.contains {
            $0 == "mesh hook events: PreToolUse, SessionEnd, SessionStart, Stop, UserPromptSubmit"
        }
    )
}

@Test func uninstallRemovesOnlyMeshOwnedItems() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)
    try Data("# skill".utf8).write(to: fixture.skillSource)

    let installer = makeInstaller(fixture)
    _ = try installer.install(mode: .apply)
    _ = try installer.uninstall(mode: .apply)

    // 二进制被多个 scope 共用，uninstall 保留，避免打断其他项目
    #expect(FileManager.default.fileExists(atPath: fixture.binaryDestination.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.skillDestination.path))
    #expect(
        !FileManager.default.fileExists(
            atPath: fixture.skillDestination.deletingLastPathComponent().path
        )
    )

    let hooks = try readHooks(fixture)
    #expect((hooks["SessionStart"] as? [[String: Any]])?.count == 1)
    #expect(hooks["Notification"] as? [[String: Any]] != nil)
    #expect(hooks["Stop"] == nil)
    #expect(hooks["UserPromptSubmit"] == nil)
    #expect(hooks["SessionEnd"] == nil)
    #expect(hooks["PreToolUse"] == nil)
}

@Test func uninstallDryRunWritesNothing() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)

    let installer = makeInstaller(fixture)
    _ = try installer.install(mode: .apply)
    let settingsAfterInstall = try String(contentsOf: fixture.settingsURL, encoding: .utf8)

    let plan = try installer.uninstall(mode: .dryRun)
    #expect(plan.notes.contains { $0.hasPrefix("binary: kept") })

    #expect(FileManager.default.fileExists(atPath: fixture.binaryDestination.path))
    let onDisk = try String(contentsOf: fixture.settingsURL, encoding: .utf8)
    #expect(onDisk == settingsAfterInstall)
}

@Test func installSelfInstallSkipsCopy() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings()
    try Data("fake-binary".utf8).write(to: fixture.binarySource)

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let installer = Installer(
        settingsStore: store,
        scope: .project,
        projectRoot: fixture.directory,
        binarySource: fixture.binarySource,
        binaryDestination: fixture.binarySource,
        skillSource: fixture.skillSource
    )
    _ = try installer.install(mode: .apply)

    #expect(FileManager.default.fileExists(atPath: fixture.binarySource.path))
    let content = try String(contentsOf: fixture.binarySource, encoding: .utf8)
    #expect(content == "fake-binary")
}

@Test func installProjectScopeDryRunTargetsLocalPaths() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }

    let installer = Installer(
        scope: .project,
        projectRoot: fixture.directory,
        binarySource: fixture.binarySource,
        binaryDestination: fixture.binaryDestination,
        skillSource: fixture.skillSource
    )
    let plan = try installer.install(mode: .dryRun)

    #expect(plan.settingsURL == fixture.settingsURL)
    #expect(plan.skillDestination == fixture.skillDestination)
    #expect(plan.projectRoot == fixture.directory)
    #expect(!FileManager.default.fileExists(atPath: fixture.settingsURL.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.skillDestination.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.binaryDestination.path))
}

@Test func installUserScopeReportsGlobalPaths() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let globalSettings = home.appendingPathComponent(".claude/settings.json")
    let before = try? Data(contentsOf: globalSettings)

    let installer = Installer(scope: .user)
    let plan = try installer.install(mode: .dryRun)

    #expect(plan.settingsURL == globalSettings)
    #expect(
        plan.skillDestination.path.hasSuffix(".claude/skills/session-mesh/SKILL.md")
    )
    #expect(plan.projectRoot == nil)
    let after = try? Data(contentsOf: globalSettings)
    #expect(before == after)
}

@Test func projectInstallPreservesPermissionsAndHooks() throws {
    let fixture = try InstallFixture()
    defer { try? fixture.cleanup() }
    try fixture.writeSettings(
        extraKeys: ["permissions": ["defaultMode": "auto", "allow": ["Bash(*)": true]]]
    )
    try Data("fake-binary".utf8).write(to: fixture.binarySource)
    let permissionsBefore = try FileManager.default
        .attributesOfItem(atPath: fixture.settingsURL.path)[.posixPermissions] as? Int

    _ = try makeInstaller(fixture).install(mode: .apply)

    let store = SettingsStore(
        settingsURL: fixture.settingsURL,
        backupDirectory: fixture.backupDirectory
    )
    let settings = try store.readSettings()
    let permissions = try #require(settings["permissions"] as? [String: Any])
    #expect(permissions["defaultMode"] as? String == "auto")
    let hooks = try #require(settings["hooks"] as? [String: Any])
    #expect((hooks["SessionStart"] as? [[String: Any]])?.count == 2)
    #expect((hooks["Notification"] as? [[String: Any]])?.count == 1)
    #expect((hooks["PreToolUse"] as? [[String: Any]])?.count == 1)
    let permissionsAfter = try FileManager.default
        .attributesOfItem(atPath: fixture.settingsURL.path)[.posixPermissions] as? Int
    #expect(permissionsAfter == permissionsBefore)
}
