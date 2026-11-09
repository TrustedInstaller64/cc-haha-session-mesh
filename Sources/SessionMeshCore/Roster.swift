import Foundation

enum Roster {
    static let activeWindow: TimeInterval = 2 * 60 * 60
    static let maxPeers = 8

    static func peers(
        from sessions: [Session],
        excluding currentSessionId: String,
        now: Date = Date()
    ) -> [RosterPeer] {
        sessions
            .filter { $0.id != currentSessionId }
            .filter { !$0.isChildSession && !$0.isDerivedSession }
            .filter { !isGeneratedChildWorktree($0) }
            .filter { now.timeIntervalSince($0.lastSeen) <= activeWindow }
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(maxPeers)
            .map { RosterPeer(id: $0.id, title: Redaction.sanitize($0.title), state: $0.state, lastSeen: $0.lastSeen) }
    }

    // state.json 不可用时 API 不返回 parent 信息；cc-haha 为子会话创建的 worktree 可据此排除
    static func isGeneratedChildWorktree(_ session: Session) -> Bool {
        guard let workDir = session.workDir else {
            return false
        }
        let components = URL(fileURLWithPath: workDir).pathComponents
        guard let index = components.firstIndex(of: "worktrees"),
              index > 0,
              components[index - 1] == ".claude",
              index + 1 < components.count else {
            return false
        }
        // 目录名必须精确匹配会话 id 前缀，避免误伤同名手工 worktree
        let name = components[index + 1]
        guard name.hasPrefix("desktop-main-") else {
            return false
        }
        return name == "desktop-main-\(session.id.prefix(8))"
    }
}
