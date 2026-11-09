import CryptoKit
import Darwin
import Foundation

enum SettingsStoreError: LocalizedError {
    case unreadable(URL)
    case invalidJSON(URL, String)
    case invalidRoot(URL)
    case invalidHooks(URL)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return "Cannot read settings file at \(url.path)"
        case .invalidJSON(let url, let detail):
            return "Settings file at \(url.path) is not valid JSON: \(detail)"
        case .invalidRoot(let url):
            return "Settings file at \(url.path) does not contain a JSON object"
        case .invalidHooks(let url):
            return "Settings file at \(url.path) has a non-object hooks value"
        case .writeFailed(let url):
            return "Cannot write settings file at \(url.path)"
        }
    }
}

struct SettingsChange {
    let hookEvent: String
    let matcher: String?
    let command: String

    init(hookEvent: String, matcher: String? = nil, command: String) {
        self.hookEvent = hookEvent
        self.matcher = matcher
        self.command = command
    }
}

final class SettingsStore {
    let settingsURL: URL
    let backupDirectory: URL
    let backupNamePrefix: String
    private let fileManager: FileManager

    init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json"),
        backupDirectory: URL = AppPaths.runtimeRoot.appendingPathComponent("backup", isDirectory: true),
        backupNamePrefix: String = "settings",
        fileManager: FileManager = .default
    ) {
        self.settingsURL = settingsURL
        self.backupDirectory = backupDirectory
        self.backupNamePrefix = backupNamePrefix
        self.fileManager = fileManager
    }

    // MARK: - Reading

    func readSettings() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return [:]
        }
        let data: Data
        do {
            data = try Data(contentsOf: settingsURL)
        } catch {
            throw SettingsStoreError.unreadable(settingsURL)
        }
        do {
            guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SettingsStoreError.invalidRoot(settingsURL)
            }
            return settings
        } catch let error as SettingsStoreError {
            throw error
        } catch {
            throw SettingsStoreError.invalidJSON(settingsURL, String(describing: error))
        }
    }

    // MARK: - Merging

    func mergedSettings(adding changes: [SettingsChange]) throws -> [String: Any] {
        var settings = try readSettings()
        guard !changes.isEmpty else { return settings }
        var hooks: [String: Any]
        if let existing = settings["hooks"] {
            guard let object = existing as? [String: Any] else {
                throw SettingsStoreError.invalidHooks(settingsURL)
            }
            hooks = object
        } else {
            hooks = [:]
        }
        for change in changes {
            var groups: [[String: Any]]
            if let existing = hooks[change.hookEvent] as? [[String: Any]] {
                groups = existing
            } else if let single = hooks[change.hookEvent] as? [String: Any] {
                groups = [single]
            } else if hooks[change.hookEvent] == nil {
                groups = []
            } else {
                // 标量等无法合并的值原样保留，不覆盖
                continue
            }
            if !groups.contains(where: { Self.group($0, hasCommand: change.command) }) {
                var group: [String: Any] = [
                    "hooks": [["type": "command", "command": change.command]]
                ]
                if let matcher = change.matcher {
                    group["matcher"] = matcher
                }
                groups.append(group)
            }
            hooks[change.hookEvent] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    private static func group(_ group: [String: Any], hasCommand command: String) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { $0["command"] as? String == command }
    }

    // MARK: - Uninstalling

    func settingsWithoutOwnedHooks(matchingBinaryPath binary: String) throws -> [String: Any] {
        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for group in groups {
                guard var inner = group["hooks"] as? [[String: Any]] else {
                    kept.append(group)
                    continue
                }
                inner.removeAll { Self.hook($0, belongsToBinary: binary) }
                if inner.isEmpty { continue }
                var cleaned = group
                cleaned["hooks"] = inner
                kept.append(cleaned)
            }
            if kept.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = kept
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return settings
    }

    func applyRemoval(matchingBinaryPath binary: String, mode: InstallMode) throws -> URL? {
        guard !mode.isReadOnly else { return nil }
        return try withLock {
            let backupURL = try makeBackup()
            try write(settingsWithoutOwnedHooks(matchingBinaryPath: binary))
            return backupURL
        }
    }

    func hookEventsContaining(binaryPath binary: String) throws -> [String] {
        let settings = try readSettings()
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }
        var events: [String] = []
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            if groups.contains(where: { Self.group($0, containsHookForBinary: binary) }) {
                events.append(event)
            }
        }
        return events.sorted()
    }

    private static func group(_ group: [String: Any], containsHookForBinary binary: String) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { Self.hook($0, belongsToBinary: binary) }
    }

    // 只认完整路径或 " hook-" 前缀，避免误删包含路径子串的其他命令
    private static func hook(_ hook: [String: Any], belongsToBinary binary: String) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command == binary || command.hasPrefix(binary + " hook-")
    }

    // MARK: - Applying

    func apply(changes: [SettingsChange], mode: InstallMode) throws -> URL? {
        guard !mode.isReadOnly else { return nil }
        return try withLock {
            let backupURL = try makeBackup()
            try write(mergedSettings(adding: changes))
            return backupURL
        }
    }

    // 两个 session-mesh 进程同时安装时，备份和写入必须整体互斥，避免备份与写入内容错位
    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let lockURL = backupDirectory.appendingPathComponent(".settings.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw SettingsStoreError.writeFailed(lockURL)
        }
        defer { close(descriptor) }
        var lockResult: Int32 = -1
        repeat {
            lockResult = flock(descriptor, LOCK_EX)
        } while lockResult != 0 && errno == EINTR
        guard lockResult == 0 else {
            throw SettingsStoreError.writeFailed(lockURL)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    // MARK: - Backup

    func makeBackup() throws -> URL {
        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // 目录已存在时 createDirectory 不会改权限，这里强制收紧
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backupDirectory.path)
        let stamp = Self.timestampFormatter.string(from: Date())
        // 同秒并发安装也不会撞名
        let destination = backupDirectory.appendingPathComponent(
            "\(backupNamePrefix)-\(stamp)-\(UUID().uuidString.prefix(8)).json"
        )
        if fileManager.fileExists(atPath: settingsURL.path) {
            try fileManager.copyItem(at: settingsURL, to: destination)
        } else {
            try Data("{}".utf8).write(to: destination, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let data = try Data(contentsOf: destination)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sidecar = URL(fileURLWithPath: destination.path + ".sha256")
        try (hex + "\n").write(to: sidecar, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sidecar.path)
        return destination
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Writing

    func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        let attributes = try? fileManager.attributesOfItem(atPath: settingsURL.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber) ?? NSNumber(value: 0o600)
        try AtomicFile.write(data, to: settingsURL, filePermissions: permissions)
    }
}
