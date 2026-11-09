import Foundation

final class Installer {
    private let settingsStore: SettingsStore
    private let fileManager: FileManager
    private let binarySource: URL
    private let binaryDestination: URL
    private let skillSource: URL
    private let scope: InstallScope
    private let projectRoot: URL

    static var defaultBinarySource: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    }

    static var defaultSkillSource: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("skills/session-mesh/SKILL.md")
    }

    static var defaultSkillDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/session-mesh", isDirectory: true)
    }

    init(
        settingsStore: SettingsStore? = nil,
        scope: InstallScope = .project,
        projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        binarySource: URL = Installer.defaultBinarySource,
        binaryDestination: URL = AppPaths.binDirectory.appendingPathComponent("session-mesh"),
        skillSource: URL = Installer.defaultSkillSource,
        fileManager: FileManager = .default
    ) {
        self.scope = scope
        self.projectRoot = projectRoot
        self.settingsStore = settingsStore ?? Self.makeSettingsStore(scope: scope, projectRoot: projectRoot)
        self.fileManager = fileManager
        self.binarySource = binarySource
        self.binaryDestination = binaryDestination
        self.skillSource = skillSource
    }

    private static func makeSettingsStore(scope: InstallScope, projectRoot: URL) -> SettingsStore {
        let backupDirectory = AppPaths.runtimeRoot.appendingPathComponent("backup", isDirectory: true)
        switch scope {
        case .project:
            return SettingsStore(
                settingsURL: projectRoot.appendingPathComponent(".claude/settings.local.json"),
                backupDirectory: backupDirectory,
                backupNamePrefix: "settings.local"
            )
        case .user:
            return SettingsStore(
                settingsURL: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/settings.json"),
                backupDirectory: backupDirectory,
                backupNamePrefix: "settings"
            )
        }
    }

    private var skillDestination: URL {
        switch scope {
        case .project:
            return projectRoot.appendingPathComponent(".claude/skills/session-mesh/SKILL.md")
        case .user:
            return Installer.defaultSkillDirectory.appendingPathComponent("SKILL.md")
        }
    }

    // MARK: - Installing

    func install(mode: InstallMode) throws -> InstallPlan {
        let changes = meshSettingsChanges()
        var plan = InstallPlan(
            mode: mode,
            scope: scope,
            projectRoot: scope == .project ? projectRoot : nil,
            settingsURL: settingsStore.settingsURL,
            settingsBackupURL: nil,
            binarySource: binarySource,
            binaryDestination: binaryDestination,
            skillSource: fileManager.fileExists(atPath: skillSource.path) ? skillSource : nil,
            skillDestination: skillDestination,
            settingsChanges: changes,
            notes: []
        )
        guard !mode.isReadOnly else {
            plan.notes = inspectInstallState()
            return plan
        }
        // 先校验 settings 与合并结果，避免复制完二进制/skill 后才发现配置损坏
        _ = try settingsStore.mergedSettings(adding: changes)
        try installBinary()
        try installSkill()
        if !fileManager.fileExists(atPath: skillSource.path) {
            plan.notes.append("skill source missing: skill not installed")
        }
        let backupURL = try settingsStore.apply(changes: changes, mode: mode)
        plan.settingsBackupURL = backupURL
        plan.notes.append("settings backup: \(backupURL?.path ?? "none")")
        return plan
    }

    func check() throws -> InstallPlan {
        try install(mode: .check)
    }

    // MARK: - Uninstalling

    func uninstall(mode: InstallMode) throws -> InstallPlan {
        var plan = InstallPlan(
            mode: mode,
            scope: scope,
            projectRoot: scope == .project ? projectRoot : nil,
            settingsURL: settingsStore.settingsURL,
            settingsBackupURL: nil,
            binarySource: binarySource,
            binaryDestination: binaryDestination,
            skillSource: nil,
            skillDestination: skillDestination,
            settingsChanges: [],
            notes: []
        )
        guard !mode.isReadOnly else {
            plan.notes = inspectUninstallState()
            return plan
        }
        let backupURL = try settingsStore.applyRemoval(
            matchingBinaryPath: ownershipMarker,
            mode: mode
        )
        // 二进制是所有 scope 共用的，卸载一个项目不能删掉其他项目的 hook 目标
        try removeSkillIfOwned()
        plan.settingsBackupURL = backupURL
        plan.notes.append("settings backup: \(backupURL?.path ?? "none")")
        plan.notes.append("binary kept: shared path; remove manually if unused")
        return plan
    }

    // MARK: - Helpers

    private var ownershipMarker: String {
        binaryDestination.path
    }

    private func meshSettingsChanges() -> [SettingsChange] {
        let binary = binaryDestination.path
        return [
            SettingsChange(hookEvent: "SessionStart", command: "\(binary) hook-start"),
            SettingsChange(hookEvent: "UserPromptSubmit", command: "\(binary) hook-prompt"),
            SettingsChange(hookEvent: "Stop", command: "\(binary) hook-stop"),
            SettingsChange(hookEvent: "SessionEnd", command: "\(binary) hook-end"),
            SettingsChange(
                hookEvent: "PreToolUse",
                matcher: "CreateSession|CreateSessions",
                command: "\(binary) hook-guard"
            )
        ]
    }

    private func inspectInstallState() -> [String] {
        var notes: [String] = []
        notes.append(
            "binary destination: \(binaryDestination.path) "
                + "(\(fileManager.fileExists(atPath: binaryDestination.path) ? "present" : "missing"))"
        )
        notes.append(
            "skill destination: \(skillDestination.path) "
                + "(\(fileManager.fileExists(atPath: skillDestination.path) ? "present" : "missing"))"
        )
        notes.append(
            "skill source: \(skillSource.path) "
                + "(\(fileManager.fileExists(atPath: skillSource.path) ? "present" : "missing"))"
        )
        let events = (try? settingsStore.hookEventsContaining(binaryPath: ownershipMarker)) ?? []
        notes.append("mesh hook events: \(events.isEmpty ? "none" : events.joined(separator: ", "))")
        return notes
    }

    private func inspectUninstallState() -> [String] {
        var notes: [String] = []
        notes.append(
            "binary: kept (shared path; \(fileManager.fileExists(atPath: binaryDestination.path) ? "present" : "absent"))"
        )
        notes.append(
            "skill: \(fileManager.fileExists(atPath: skillDestination.path) ? "would remove" : "absent")"
        )
        let events = (try? settingsStore.hookEventsContaining(binaryPath: ownershipMarker)) ?? []
        notes.append("mesh hook events: \(events.isEmpty ? "none" : events.joined(separator: ", "))")
        return notes
    }

    private func installBinary() throws {
        try fileManager.createDirectory(
            at: binaryDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // 已安装的二进制再 install 时源即目标，跳过复制避免自删
        if binarySource.standardizedFileURL.path == binaryDestination.standardizedFileURL.path {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binaryDestination.path)
            return
        }
        let temporary = binaryDestination.deletingLastPathComponent()
            .appendingPathComponent(".session-mesh.tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: binarySource, to: temporary)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporary.path)
        try replaceOrMove(temporary, to: binaryDestination)
    }

    private func installSkill() throws {
        guard fileManager.fileExists(atPath: skillSource.path) else { return }
        let directory = skillDestination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = directory.appendingPathComponent(".SKILL.md.tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: skillSource, to: temporary)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try replaceOrMove(temporary, to: skillDestination)
    }

    // 并发 install 时目标可能在检查后才出现，失败后重试一次替换
    private func replaceOrMove(_ temporary: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            return
        }
        do {
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            guard fileManager.fileExists(atPath: destination.path) else {
                throw error
            }
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        }
    }

    private func removeSkillIfOwned() throws {
        guard fileManager.fileExists(atPath: skillDestination.path) else { return }
        let directory = skillDestination.deletingLastPathComponent()
        try fileManager.removeItem(at: skillDestination)
        let remaining = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        if remaining.isEmpty {
            try? fileManager.removeItem(at: directory)
        }
    }
}
