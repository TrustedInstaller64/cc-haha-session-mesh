import Foundation

enum SessionState: String, Codable {
    case running
    case idle
    case stopped
    case completed
    case unknown
}

struct Session {
    var id: String
    var title: String
    var state: SessionState
    var lastSeen: Date
    var projectRoot: String?
    var workDir: String?
    var parentSessionId: String?
    var rootSessionId: String?

    var isChildSession: Bool { parentSessionId != nil }

    var isDerivedSession: Bool { rootSessionId != nil && rootSessionId != id }
}

struct RosterPeer {
    let id: String
    let title: String
    let state: SessionState
    let lastSeen: Date
}
