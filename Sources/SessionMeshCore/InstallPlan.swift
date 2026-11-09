import Foundation

enum InstallMode {
    case apply
    case dryRun
    case check

    var isReadOnly: Bool {
        self != .apply
    }
}

enum InstallScope {
    case project
    case user
}

struct InstallPlan {
    let mode: InstallMode
    let scope: InstallScope
    let projectRoot: URL?
    let settingsURL: URL
    var settingsBackupURL: URL?
    let binarySource: URL
    let binaryDestination: URL
    let skillSource: URL?
    let skillDestination: URL
    let settingsChanges: [SettingsChange]
    var notes: [String]
}
