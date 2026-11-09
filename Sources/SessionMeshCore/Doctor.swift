import Foundation

enum Doctor {
    struct Environment {
        let fileManager: FileManager
        let homeDirectory: URL
        let runtimeRoot: URL

        init(
            fileManager: FileManager = .default,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
            runtimeRoot: URL = AppPaths.runtimeRoot
        ) {
            self.fileManager = fileManager
            self.homeDirectory = homeDirectory
            self.runtimeRoot = runtimeRoot
        }

        var settingsURL: URL {
            homeDirectory.appendingPathComponent(".claude/settings.json")
        }

        var binaryURL: URL {
            runtimeRoot.appendingPathComponent("bin/session-mesh")
        }
    }

    struct Check {
        enum Status {
            case pass
            case warning
            case failure

            var label: String {
                switch self {
                case .pass:
                    return "PASS"
                case .warning:
                    return "WARN"
                case .failure:
                    return "FAIL"
                }
            }
        }

        let name: String
        let status: Status
        let detail: String
    }

    static func run(writeOutput: (String) -> Void = { print($0) }) -> Int32 {
        let checks = runChecks()
        for check in checks {
            writeOutput("[\(check.status.label)] \(check.name): \(check.detail)")
        }
        let failures = checks.filter { $0.status == .failure }.count
        let warnings = checks.filter { $0.status == .warning }.count
        let passed = checks.count - failures - warnings
        writeOutput("Doctor: \(passed) passed, \(warnings) warning(s), \(failures) failure(s)")
        return failures == 0 ? 0 : 1
    }

    static func runChecks(environment: Environment = Environment()) -> [Check] {
        [
            checkSwiftToolchain(),
            checkRuntimeDirectory(environment: environment),
            checkInstalledBinary(environment: environment),
            checkSettingsFile(environment: environment),
            checkSettingsPermissions(environment: environment),
            checkLocalAPI()
        ]
    }

    // MARK: - Checks

    private static func checkSwiftToolchain() -> Check {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun") else {
            return Check(name: "Swift toolchain", status: .failure, detail: "xcrun not found")
        }
        guard let result = Shell.run(executable: "/usr/bin/xcrun", arguments: ["--find", "swift"]),
              result.status == 0 else {
            return Check(name: "Swift toolchain", status: .failure, detail: "xcrun cannot locate swift")
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return Check(name: "Swift toolchain", status: .failure, detail: "swift path is empty")
        }
        return Check(name: "Swift toolchain", status: .pass, detail: path)
    }

    static func checkRuntimeDirectory(environment: Environment) -> Check {
        let fileManager = environment.fileManager
        let root = environment.runtimeRoot
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                return Check(name: "Runtime directory", status: .failure, detail: "\(root.path) is not a directory")
            }
            guard let attributes = try? fileManager.attributesOfItem(atPath: root.path),
                  let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue else {
                return Check(name: "Runtime directory", status: .warning, detail: "cannot read permissions")
            }
            if mode & 0o077 != 0 {
                return Check(
                    name: "Runtime directory",
                    status: .warning,
                    detail: "\(root.path) permissions \(String(mode, radix: 8)); expected 0700"
                )
            }
            return Check(name: "Runtime directory", status: .pass, detail: "\(root.path) (0700)")
        }

        let parent = root.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path) else {
            return Check(name: "Runtime directory", status: .failure, detail: "\(parent.path) is missing")
        }
        guard fileManager.isWritableFile(atPath: parent.path) else {
            return Check(name: "Runtime directory", status: .failure, detail: "\(parent.path) is not writable")
        }
        return Check(name: "Runtime directory", status: .pass, detail: "not created yet; parent is writable")
    }

    static func checkInstalledBinary(environment: Environment) -> Check {
        let fileManager = environment.fileManager
        let binary = environment.binaryURL
        guard fileManager.fileExists(atPath: binary.path) else {
            return Check(name: "Installed binary", status: .warning, detail: "not installed")
        }
        guard fileManager.isExecutableFile(atPath: binary.path) else {
            return Check(name: "Installed binary", status: .warning, detail: "\(binary.path) is not executable")
        }
        return Check(name: "Installed binary", status: .pass, detail: binary.path)
    }

    static func checkSettingsFile(environment: Environment) -> Check {
        let fileManager = environment.fileManager
        let settingsURL = environment.settingsURL
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return Check(name: "Settings file", status: .warning, detail: "\(settingsURL.path) not found")
        }
        do {
            let store = SettingsStore(settingsURL: settingsURL, fileManager: fileManager)
            let settings = try store.readSettings()
            if let hooks = settings["hooks"], hooks as? [String: Any] == nil {
                return Check(name: "Settings file", status: .failure, detail: "\"hooks\" is not an object")
            }
            return Check(name: "Settings file", status: .pass, detail: "valid JSON")
        } catch {
            return Check(name: "Settings file", status: .failure, detail: error.localizedDescription)
        }
    }

    static func checkSettingsPermissions(environment: Environment) -> Check {
        let fileManager = environment.fileManager
        let settingsURL = environment.settingsURL
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return Check(name: "Settings permissions", status: .warning, detail: "settings file not found")
        }
        guard fileManager.isReadableFile(atPath: settingsURL.path) else {
            return Check(name: "Settings permissions", status: .failure, detail: "not readable")
        }
        guard fileManager.isWritableFile(atPath: settingsURL.path) else {
            return Check(name: "Settings permissions", status: .failure, detail: "not writable")
        }
        return Check(name: "Settings permissions", status: .pass, detail: "readable and writable")
    }

    private static func checkLocalAPI() -> Check {
        let port: Int
        do {
            port = try LocalAPI.readPort()
        } catch {
            return Check(name: "Local API", status: .warning, detail: error.localizedDescription)
        }
        do {
            let sessions = try LocalAPI.fetchSessions()
            return Check(name: "Local API", status: .pass, detail: "\(sessions.count) session(s) on port \(port)")
        } catch {
            return Check(name: "Local API", status: .warning, detail: "port \(port): \(error.localizedDescription)")
        }
    }
}
