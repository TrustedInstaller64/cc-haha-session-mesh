import Foundation
import Testing
@testable import SessionMeshCore

struct RosterTests {
    @Test func rosterFiltersExcludesSelfAndStaleSessions() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            makeSession(id: "self", lastSeen: now),
            makeSession(id: "child", lastSeen: now, parentSessionId: "self", rootSessionId: "self"),
            makeSession(id: "derived", lastSeen: now, rootSessionId: "self"),
            makeSession(id: "stale", lastSeen: now.addingTimeInterval(-3 * 60 * 60)),
            makeSession(id: "peer-a", lastSeen: now.addingTimeInterval(-60)),
            makeSession(id: "peer-b", lastSeen: now.addingTimeInterval(-30))
        ]

        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.map(\.id) == ["peer-b", "peer-a"])
        #expect(peers.first?.title == "title-peer-b")
        #expect(peers.first?.state == .running)
        #expect(peers.first?.lastSeen == now.addingTimeInterval(-30))
    }

    @Test func rosterCapsPeersAtEight() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = (0..<9).map { index in
            makeSession(id: "peer-\(index)", lastSeen: now.addingTimeInterval(-Double(index) * 60))
        }

        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.count == 8)
        #expect(peers.first?.id == "peer-0")
        #expect(peers.last?.id == "peer-7")
    }

    @Test func rosterKeepsSessionsInsideActiveWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let boundary = makeSession(
            id: "boundary",
            lastSeen: now.addingTimeInterval(-Roster.activeWindow)
        )
        let justOutside = makeSession(
            id: "outside",
            lastSeen: now.addingTimeInterval(-Roster.activeWindow - 1)
        )

        let peers = Roster.peers(from: [boundary, justOutside], excluding: "self", now: now)

        #expect(peers.map(\.id) == ["boundary"])
    }

    @Test func rosterSanitizesPeerTitles() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            makeSession(id: "long", lastSeen: now, title: String(repeating: "x", count: 70) + "\n")
        ]

        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.count == 1)
        #expect(peers[0].title == String(repeating: "x", count: 60))
    }

    @Test func rosterExcludesGeneratedChildWorktreesWithoutParentInfo() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let childId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let sessions = [
            makeSession(
                id: childId,
                lastSeen: now,
                workDir: "/tmp/proj/.claude/worktrees/desktop-main-aaaaaaaa"
            ),
            makeSession(id: "peer", lastSeen: now.addingTimeInterval(-60))
        ]

        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.map(\.id) == ["peer"])
    }

    @Test func rosterKeepsWorktreeWhenNameDoesNotMatchSession() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            makeSession(
                id: "11111111-1111-4111-8111-111111111111",
                lastSeen: now,
                workDir: "/tmp/proj/.claude/worktrees/desktop-main-22222222"
            )
        ]

        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.map(\.id) == ["11111111-1111-4111-8111-111111111111"])
    }

    @Test func rosterKeepsOrdinaryWorktreeSessions() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            makeSession(id: "linked", lastSeen: now, workDir: "/tmp/proj/linked")
        ]

        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.map(\.id) == ["linked"])
    }

    @Test func rosterPreservesPeerState() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            makeSession(id: "running", lastSeen: now, state: .running),
            makeSession(id: "stopped", lastSeen: now.addingTimeInterval(-60), state: .stopped)
        ]

        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.map(\.state) == [.running, .stopped])
    }

    // MARK: - Helpers

    private func makeSession(
        id: String,
        lastSeen: Date,
        title: String? = nil,
        state: SessionState = .running,
        workDir: String? = nil,
        parentSessionId: String? = nil,
        rootSessionId: String? = nil
    ) -> Session {
        Session(
            id: id,
            title: title ?? "title-\(id)",
            state: state,
            lastSeen: lastSeen,
            projectRoot: nil,
            workDir: workDir,
            parentSessionId: parentSessionId,
            rootSessionId: rootSessionId
        )
    }
}
