import Foundation
import Testing
@testable import SessionMeshCore

struct RegistryTests {
    @Test func registryEnrichesAPISessionsWithMemberState() {
        let sessions = [
            makeSession(id: "aaa"),
            makeSession(id: "bbb"),
            makeSession(id: "ccc")
        ]
        let members = [
            SessionMember(sessionId: "aaa", state: "running", parentSessionId: nil, rootSessionId: "aaa"),
            SessionMember(sessionId: "bbb", state: "stopped", parentSessionId: "aaa", rootSessionId: "aaa")
        ]

        let enriched = SessionRegistry.enrich(sessions, with: members)

        #expect(enriched[0].state == .running)
        #expect(enriched[0].rootSessionId == "aaa")
        #expect(enriched[1].state == .stopped)
        #expect(enriched[1].parentSessionId == "aaa")
        #expect(enriched[2].state == .unknown)
    }

    @Test func transcriptReaderRejectsNonUUIDSessionId() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-mesh-transcripts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(TranscriptReader.metadata(for: "../escape", projectsRoot: root) == nil)
    }

    @Test func registryParsesMembersFromStateJSON() throws {
        let json = """
        {
          "version": 1,
          "revision": 10,
          "members": {
            "aaa": {
              "sessionId": "aaa",
              "rootSessionId": "aaa",
              "parentSessionId": null,
              "state": "running",
              "stopped": false,
              "result": {"huge": "ignored"}
            },
            "bbb": {
              "sessionId": "bbb",
              "rootSessionId": "aaa",
              "parentSessionId": "aaa",
              "state": "completed",
              "stopped": true,
              "result": null
            }
          },
          "batches": [],
          "messages": []
        }
        """

        let members = try SessionRegistry.members(from: Data(json.utf8))

        #expect(members.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.sessionId, $0) })
        #expect(byId["aaa"]?.state == "running")
        #expect(byId["aaa"]?.parentSessionId == nil)
        #expect(byId["bbb"]?.state == "completed")
        #expect(byId["bbb"]?.rootSessionId == "aaa")
    }

    @Test func registryLoadsFromMembersWithTranscriptMetadata() {
        let members = [
            SessionMember(sessionId: "aaa", state: "running", parentSessionId: nil, rootSessionId: "aaa"),
            SessionMember(sessionId: "bbb", state: "running", parentSessionId: nil, rootSessionId: "bbb")
        ]
        let modifiedAt = Date(timeIntervalSince1970: 500)

        let sessions = SessionRegistry.loadFromMembers(members) { sessionId in
            sessionId == "aaa"
                ? TranscriptMetadata(title: "title-a", workDir: "/Users/test/project", modifiedAt: modifiedAt)
                : nil
        }

        #expect(sessions.count == 2)
        #expect(sessions[0].title == "title-a")
        #expect(sessions[0].workDir == "/Users/test/project")
        #expect(sessions[0].lastSeen == modifiedAt)
        #expect(sessions[1].title == "")
        #expect(sessions[1].lastSeen == Date(timeIntervalSince1970: 0))
    }

    @Test func registryParsesTranscriptMetadata() {
        let text = """
        {"type":"session-meta","workDir":"/Users/test/project","agentProfile":"native"}
        {"type":"user","message":"hi"}
        {"type":"ai-title","aiTitle":"sample session title"}
        """

        let metadata = SessionRegistry.parseTranscriptMetadata(from: text)

        #expect(metadata?.workDir == "/Users/test/project")
        #expect(metadata?.title == "sample session title")
    }

    @Test func registryTranscriptMetadataRequiresKnownEntry() {
        let metadata = SessionRegistry.parseTranscriptMetadata(
            from: #"{"type":"user","message":"hi"}"#
        )

        #expect(metadata == nil)
    }

    @Test func registryEnrichToleratesDuplicateMemberIds() {
        let sessions = [makeSession(id: "aaa")]
        let members = [
            SessionMember(sessionId: "aaa", state: "running", parentSessionId: nil, rootSessionId: "aaa"),
            SessionMember(sessionId: "aaa", state: "stopped", parentSessionId: nil, rootSessionId: "aaa")
        ]

        let enriched = SessionRegistry.enrich(sessions, with: members)

        #expect(enriched.count == 1)
        #expect(enriched[0].state == .running)
    }

    @Test func registryParsesMembersSkippingInvalidEntries() throws {
        let json = """
        {
          "members": {
            "aaa": {
              "sessionId": "aaa",
              "state": "running"
            },
            "broken": {
              "state": "running"
            },
            "partial": {
              "sessionId": "bbb",
              "parentSessionId": "aaa"
            }
          }
        }
        """

        let members = try SessionRegistry.members(from: Data(json.utf8))

        #expect(members.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.sessionId, $0) })
        #expect(byId["aaa"]?.state == "running")
        #expect(byId["bbb"]?.state == "unknown")
        #expect(byId["bbb"]?.parentSessionId == "aaa")
    }

    @Test func transcriptReaderScansProjectsWithBoundedRead() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-mesh-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("-Users-test-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("00000000-0000-4000-8000-000000000001.jsonl")
        let text = """
        {"type":"session-meta","workDir":"/Users/test/project"}
        {"type":"ai-title","aiTitle":"sample session title"}
        """
        try Data(text.utf8).write(to: file)
        let modifiedAt = Date(timeIntervalSince1970: 700)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: file.path
        )

        let metadata = TranscriptReader.metadata(
            for: "00000000-0000-4000-8000-000000000001",
            projectsRoot: root
        )

        #expect(metadata?.workDir == "/Users/test/project")
        #expect(metadata?.title == "sample session title")
        #expect(metadata?.modifiedAt == modifiedAt)
    }

    // MARK: - Helpers

    private func makeSession(id: String) -> Session {
        Session(
            id: id,
            title: "title-\(id)",
            state: .unknown,
            lastSeen: Date(timeIntervalSince1970: 0),
            projectRoot: nil,
            workDir: nil,
            parentSessionId: nil,
            rootSessionId: nil
        )
    }
}
