import Foundation

enum AppPaths {
    static var runtimeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/session-mesh", isDirectory: true)
    }

    static var binDirectory: URL {
        runtimeRoot.appendingPathComponent("bin", isDirectory: true)
    }

    static var inboxDirectory: URL {
        runtimeRoot.appendingPathComponent("inbox", isDirectory: true)
    }

    static var logDirectory: URL {
        runtimeRoot.appendingPathComponent("logs", isDirectory: true)
    }

    static var stateDirectory: URL {
        runtimeRoot.appendingPathComponent("state", isDirectory: true)
    }
}
