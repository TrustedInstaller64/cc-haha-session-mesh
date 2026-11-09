import Foundation
import Testing
@testable import SessionMeshCore

struct LocalAPITests {
    @Test func localAPICollectsPagesUntilTotal() throws {
        let pages = [
            SessionPage(sessions: makeSessions(prefix: "p0", count: 20), total: 41),
            SessionPage(sessions: makeSessions(prefix: "p1", count: 20), total: 41),
            SessionPage(sessions: makeSessions(prefix: "p2", count: 1), total: 41)
        ]
        var offsets: [Int] = []

        let sessions = try LocalAPI.collectPages { offset in
            offsets.append(offset)
            return pages[offset / 20]
        }

        #expect(sessions.count == 41)
        #expect(offsets == [0, 20, 40])
    }

    @Test func localAPIStopsOnEmptyPage() throws {
        var calls = 0

        let sessions = try LocalAPI.collectPages { _ in
            calls += 1
            return SessionPage(sessions: [], total: 100)
        }

        #expect(sessions.isEmpty)
        #expect(calls == 1)
    }

    @Test func localAPIStopsWhenTotalReached() throws {
        var calls = 0

        let sessions = try LocalAPI.collectPages { _ in
            calls += 1
            return SessionPage(sessions: makeSessions(prefix: "p", count: 10), total: 10)
        }

        #expect(sessions.count == 10)
        #expect(calls == 1)
    }

    @Test func localAPIStopsWhenPageAddsNoNewSessions() throws {
        let firstPage = makeSessions(prefix: "p", count: 20)
        var calls = 0

        let sessions = try LocalAPI.collectPages { offset in
            calls += 1
            if offset == 0 {
                return SessionPage(sessions: firstPage, total: 500)
            }
            return SessionPage(sessions: firstPage, total: 500)
        }

        #expect(sessions.count == 20)
        #expect(calls == 2)
    }

    @Test func localAPIAdvancesOffsetPastDuplicateEntries() throws {
        let firstPage = makeSessions(prefix: "p", count: 20)
        let secondPage = Array(firstPage[10...]) + makeSessions(prefix: "q", count: 10)
        var offsets: [Int] = []

        let sessions = try LocalAPI.collectPages { offset in
            offsets.append(offset)
            if offset == 0 {
                return SessionPage(sessions: firstPage, total: 30)
            }
            return SessionPage(sessions: secondPage, total: 30)
        }

        #expect(sessions.count == 30)
        #expect(offsets == [0, 20])
    }

    @Test func localAPIDeduplicatesDuplicateSessionIds() throws {
        let duplicated = makeSessions(prefix: "dup", count: 2)
        let page = SessionPage(sessions: duplicated + duplicated, total: 2)

        let sessions = try LocalAPI.collectPages { _ in page }

        #expect(sessions.count == 2)
    }

    @Test func localAPIPortParsesServerStateJSON() throws {
        let data = Data(#"{"lastPort": 64520}"#.utf8)

        #expect(try LocalAPI.port(from: data) == 64520)
        #expect(throws: LocalAPIError.invalidPort) {
            try LocalAPI.port(from: Data("not json".utf8))
        }
    }

    @Test func localAPIDecodesSessionPageWithFractionalDates() throws {
        let json = """
        {
          "sessions": [
            {
              "id": "00000000-0000-4000-8000-000000000001",
              "title": "sample session title",
              "createdAt": "2024-01-01T00:00:00.852Z",
              "modifiedAt": "2024-01-01T01:00:00.094Z",
              "messageCount": 12,
              "projectPath": "/Users/test/cc-haha-session-mesh",
              "projectRoot": "/Users/test/cc-haha-session-mesh",
              "workDir": "/Users/test/cc-haha-session-mesh",
              "workspaceState": "ready",
              "agentProfile": "native",
              "permissionMode": "default",
              "runtimeProviderId": "sample-provider",
              "runtimeModelId": "sample-model",
              "effortLevel": "max",
              "openAIFastMode": false
            },
            {
              "id": "00000000-0000-4000-8000-000000000002",
              "createdAt": "2024-01-01T00:30:00.000Z",
              "modifiedAt": "2024-01-01T00:31:00.000Z"
            }
          ],
          "total": 41,
          "index": {
            "mode": "on",
            "state": "ready",
            "discovered": 90,
            "indexed": 90,
            "degradedSources": 0,
            "databaseBytes": 43810816,
            "walBytes": 16777216,
            "lastUpdatedAt": "2024-01-01T01:00:13.146Z",
            "lastErrorCode": null
          }
        }
        """
        let page = try LocalAPI.decodePage(from: Data(json.utf8))

        #expect(page.total == 41)
        #expect(page.sessions.count == 2)
        let first = page.sessions[0]
        #expect(first.id == "00000000-0000-4000-8000-000000000001")
        #expect(first.title == "sample session title")
        #expect(first.state == .unknown)
        #expect(first.projectRoot == "/Users/test/cc-haha-session-mesh")
        #expect(first.lastSeen == iso8601("2024-01-01T01:00:00.094Z"))
        #expect(page.sessions[1].title == "")
        #expect(page.sessions[1].lastSeen == iso8601("2024-01-01T00:31:00.000Z"))
    }

    // MARK: - Helpers

    private func makeSessions(prefix: String, count: Int) -> [Session] {
        (0..<count).map { index in
            Session(
                id: "\(prefix)-\(index)",
                title: "title-\(prefix)-\(index)",
                state: .unknown,
                lastSeen: Date(timeIntervalSince1970: Double(index)),
                projectRoot: nil,
                workDir: nil,
                parentSessionId: nil,
                rootSessionId: nil
            )
        }
    }

    private func iso8601(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }
}
