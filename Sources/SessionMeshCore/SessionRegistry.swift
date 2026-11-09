import Foundation

struct SessionMember {
    let sessionId: String
    let state: String
    let parentSessionId: String?
    let rootSessionId: String?
}

struct TranscriptMetadata {
    var title: String?
    var workDir: String?
    var modifiedAt: Date?
}

enum SessionRegistry {
    static func loadSessions() -> [Session] {
        let apiSessions = try? LocalAPI.fetchSessions()
        let members = loadMembers()
        if let apiSessions {
            return enrich(apiSessions, with: members)
        }
        return loadFromMembers(members)
    }

    static func enrich(_ sessions: [Session], with members: [SessionMember]) -> [Session] {
        let byId = Dictionary(
            members.map { ($0.sessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return sessions.map { session in
            guard let member = byId[session.id] else {
                return session
            }
            var updated = session
            updated.state = SessionState(rawValue: member.state) ?? .unknown
            updated.parentSessionId = member.parentSessionId
            updated.rootSessionId = member.rootSessionId
            return updated
        }
    }

    static func loadFromMembers(
        _ members: [SessionMember],
        metadata: (String) -> TranscriptMetadata?
    ) -> [Session] {
        members.map { member in
            let meta = metadata(member.sessionId)
            return Session(
                id: member.sessionId,
                title: meta?.title ?? "",
                state: SessionState(rawValue: member.state) ?? .unknown,
                lastSeen: meta?.modifiedAt ?? Date(timeIntervalSince1970: 0),
                projectRoot: nil,
                workDir: meta?.workDir,
                parentSessionId: member.parentSessionId,
                rootSessionId: member.rootSessionId
            )
        }
    }

    static func members(from stateData: Data) throws -> [SessionMember] {
        struct StateDTO: Decodable {
            let members: [String: MemberDTO]
        }
        struct MemberDTO: Decodable {
            let sessionId: String?
            let state: String?
            let parentSessionId: String?
            let rootSessionId: String?
        }
        let state = try JSONDecoder().decode(StateDTO.self, from: stateData)
        return state.members.values.compactMap { member in
            guard let sessionId = member.sessionId else {
                return nil
            }
            return SessionMember(
                sessionId: sessionId,
                state: member.state ?? "unknown",
                parentSessionId: member.parentSessionId,
                rootSessionId: member.rootSessionId
            )
        }
    }

    static func parseTranscriptMetadata(from text: String) -> TranscriptMetadata? {
        var result = TranscriptMetadata()
        var found = false
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                continue
            }
            switch type {
            case "session-meta":
                result.workDir = object["workDir"] as? String
                found = true
            case "ai-title":
                result.title = object["aiTitle"] as? String
                found = true
            default:
                break
            }
        }
        return found ? result : nil
    }

    // MARK: - Fallback sources

    static func loadMembers() -> [SessionMember] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/cc-haha/session-collaboration/state.json")
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? members(from: data)) ?? []
    }

    private static func loadFromMembers(_ members: [SessionMember]) -> [Session] {
        loadFromMembers(members, metadata: { sessionId in
            TranscriptReader.metadata(for: sessionId)
        })
    }
}

enum TranscriptReader {
    static let scanLimit = 256 * 1024

    static func metadata(for sessionId: String) -> TranscriptMetadata? {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        return metadata(for: sessionId, projectsRoot: projects)
    }

    static func metadata(for sessionId: String, projectsRoot: URL) -> TranscriptMetadata? {
        // sessionId 来自 state.json，只接受 UUID，避免 ../ 拼进路径
        guard UUID(uuidString: sessionId) != nil else { return nil }
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        for directory in directories {
            let file = directory.appendingPathComponent("\(sessionId).jsonl")
            guard let data = boundedPrefix(of: file),
                  let text = String(data: data, encoding: .utf8),
                  var metadata = SessionRegistry.parseTranscriptMetadata(from: text) else {
                continue
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            metadata.modifiedAt = attributes?[.modificationDate] as? Date
            return metadata
        }
        return nil
    }

    private static func boundedPrefix(of file: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { try? handle.close() }
        return try? handle.read(upToCount: scanLimit)
    }
}
