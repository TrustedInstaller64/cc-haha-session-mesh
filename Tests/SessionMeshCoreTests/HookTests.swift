import Foundation
import Testing
@testable import SessionMeshCore

struct HookTests {
    @Test func hookInputDecodesAllObservedFields() {
        let json = """
        {
          "session_id": "s-1",
          "transcript_path": "/tmp/t.jsonl",
          "cwd": "/proj",
          "agent_type": "local",
          "permission_mode": "auto",
          "hook_event_name": "UserPromptSubmit",
          "prompt": "hello",
          "stop_hook_active": false,
          "last_assistant_message": "done"
        }
        """

        let input = HookInput(data: Data(json.utf8))

        #expect(input?.event == .userPromptSubmit)
        #expect(input?.sessionId == "s-1")
        #expect(input?.transcriptPath == "/tmp/t.jsonl")
        #expect(input?.cwd == "/proj")
        #expect(input?.agentType == "local")
        #expect(input?.permissionMode == "auto")
        #expect(input?.prompt == "hello")
        #expect(input?.stopHookActive == false)
        #expect(input?.lastAssistantMessage == "done")
    }

    @Test func hookInputAllowsMissingOptionalFields() {
        let json = """
        {"hook_event_name": "SessionStart", "session_id": "s-2"}
        """

        let input = HookInput(data: Data(json.utf8))

        #expect(input?.event == .sessionStart)
        #expect(input?.sessionId == "s-2")
        #expect(input?.permissionMode == nil)
        #expect(input?.prompt == nil)
        #expect(input?.source == nil)
    }

    @Test func hookInputIgnoresUnknownFields() {
        let json = """
        {"hook_event_name": "Stop", "session_id": "s-3", "future_field": [1, 2]}
        """

        let input = HookInput(data: Data(json.utf8))

        #expect(input?.event == .stop)
        #expect(input?.sessionId == "s-3")
    }

    @Test func hookInputReturnsNilForMalformedJSON() {
        #expect(HookInput(data: Data("not json".utf8)) == nil)
        #expect(HookInput(data: Data()) == nil)
    }

    @Test func hookInputDecodesToolName() {
        let json = """
        {"hook_event_name": "PreToolUse", "session_id": "s-5", "tool_name": "CreateSession"}
        """

        let input = HookInput(data: Data(json.utf8))

        #expect(input?.toolName == "CreateSession")
    }

    @Test func hookInputMapsUnknownEventNames() {
        let input = HookInput(data: Data(#"{"hook_event_name": "SomethingElse"}"#.utf8))

        #expect(input?.event == .unknown("SomethingElse"))
    }

    @Test func hookInputDecodesStopEvent() {
        let json = """
        {
          "session_id": "s-4",
          "hook_event_name": "Stop",
          "stop_hook_active": false,
          "last_assistant_message": "done"
        }
        """

        let input = HookInput(data: Data(json.utf8))

        #expect(input?.event == .stop)
        #expect(input?.stopHookActive == false)
        #expect(input?.lastAssistantMessage == "done")
    }

    @Test func hookHandlersHandleReturnsEmptyForAnyInput() {
        let input = HookInput(data: Data(#"{"hook_event_name": "UserPromptSubmit"}"#.utf8))

        #expect(HookHandlers.handle(input!) == "")
    }

    @Test func hookHandlersReadInputFailsOpenOnEmptyStdin() {
        let pipe = Pipe()
        pipe.fileHandleForWriting.closeFile()

        #expect(HookHandlers.readInput(from: pipe.fileHandleForReading) == nil)
    }

    // MARK: - Phase 2: store 与名册输出

    @Test func hookStartRegistersSessionAndOutputsRoster() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let input = makeInput(event: "SessionStart", sessionId: "self", prompt: nil)

        let output = HookHandlers.handle(
            input,
            now: now,
            stateURL: temp.appendingPathComponent("roster.json"),
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [] }
        )

        #expect(output.hasPrefix("[mesh-roster] project="))
        #expect(output.contains("peers=0"))
        let store = HookHandlers.loadStore(from: temp.appendingPathComponent("roster.json"))
        #expect(store["self"]?.projectRoot.hasSuffix("session-mesh-proj") == true)
        #expect(store["self"]?.lastSeen == now)
        #expect(store["self"]?.title == "")
        let lockURL = temp.appendingPathComponent("roster.json.lock")
        #expect(FileManager.default.fileExists(atPath: lockURL.path))
        let lockAttributes = try? FileManager.default.attributesOfItem(atPath: lockURL.path)
        #expect(lockAttributes?[.posixPermissions] as? Int == 0o600)
    }

    @Test func concurrentHookUpdatesKeepAllSessions() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        let ids = (0..<16).map { _ in UUID().uuidString }

        let queue = DispatchQueue(label: "session-mesh-hooks", attributes: .concurrent)
        let group = DispatchGroup()
        for id in ids {
            group.enter()
            queue.async {
                _ = HookHandlers.handle(
                    makeInput(event: "SessionStart", sessionId: id, prompt: nil),
                    now: now,
                    stateURL: stateURL,
                    logURL: logURL,
                    loadSessions: { [] }
                )
                group.leave()
            }
        }
        group.wait()

        let store = HookHandlers.loadStore(from: stateURL)
        #expect(Set(store.keys) == Set(ids))
    }

    @Test func hookPromptUpdatesTitleAndLastSeen() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let start = Date(timeIntervalSince1970: 1_000_000)
        let later = start.addingTimeInterval(300)
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        _ = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: start,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        let output = HookHandlers.handle(
            makeInput(event: "UserPromptSubmit", sessionId: "self", prompt: "Fix the roster\nsecond line"),
            now: later,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        let store = HookHandlers.loadStore(from: stateURL)
        #expect(store["self"]?.title == "Fix the roster")
        #expect(store["self"]?.lastSeen == later)
        #expect(output.contains(HookHandlers.policyLine))
    }

    @Test func hookStartPreservesExistingTitle() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        _ = HookHandlers.handle(
            makeInput(event: "UserPromptSubmit", sessionId: "self", prompt: "Keep this title"),
            now: Date(timeIntervalSince1970: 1_000_000),
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )
        _ = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: Date(timeIntervalSince1970: 1_000_001),
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        #expect(HookHandlers.loadStore(from: stateURL)["self"]?.title == "Keep this title")
    }

    @Test func hookStorePrunesRecordsOlderThanRetention() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        let stale = HookSessionRecord(
            sessionId: "stale",
            projectRoot: "/tmp",
            agentType: nil,
            title: "",
            lastSeen: now.addingTimeInterval(-HookHandlers.storeRetention - 1),
            state: .stopped
        )
        let fresh = HookSessionRecord(
            sessionId: "fresh",
            projectRoot: "/tmp",
            agentType: nil,
            title: "",
            lastSeen: now,
            state: .running
        )

        HookHandlers.saveStore(["stale": stale, "fresh": fresh], to: stateURL, logURL: logURL, now: now)

        #expect(Set(HookHandlers.loadStore(from: stateURL).keys) == ["fresh"])
    }

    @Test func hookStoreCapsRecordCount() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        var store: [String: HookSessionRecord] = [:]
        for index in 0..<(HookHandlers.maxStoredSessions + 10) {
            store["s-\(index)"] = HookSessionRecord(
                sessionId: "s-\(index)",
                projectRoot: "/tmp",
                agentType: nil,
                title: "",
                lastSeen: now.addingTimeInterval(-Double(index)),
                state: .running
            )
        }

        HookHandlers.saveStore(store, to: stateURL, logURL: logURL, now: now)
        let loaded = HookHandlers.loadStore(from: stateURL)

        #expect(loaded.count == HookHandlers.maxStoredSessions)
        #expect(loaded["s-0"] != nil)
        #expect(loaded["s-\(HookHandlers.maxStoredSessions + 9)"] == nil)
    }

    @Test func hookRecordsKeepWorkDirForGeneratedChildFiltering() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let childId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let normal = HookSessionRecord(
            sessionId: "normal",
            projectRoot: temp.path,
            agentType: nil,
            title: "normal",
            lastSeen: now,
            state: .running,
            workDir: temp.path
        )
        let child = HookSessionRecord(
            sessionId: childId,
            projectRoot: temp.path,
            agentType: nil,
            title: "child",
            lastSeen: now,
            state: .running,
            workDir: temp.appendingPathComponent(".claude/worktrees/desktop-main-aaaaaaaa").path
        )

        let sessions = HookHandlers.sessionsForProject(
            referenceRoot: temp.path,
            records: ["normal": normal, childId: child],
            loaded: []
        )
        let peers = Roster.peers(from: sessions, excluding: "self", now: now)

        #expect(peers.map(\.id) == ["normal"])
    }

    @Test func guardDeniesChildSessionCreateSession() throws {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let sessionId = UUID().uuidString
        let input = makeInput(
            event: "PreToolUse",
            sessionId: sessionId,
            prompt: nil,
            toolName: "CreateSession"
        )
        let members = [
            SessionMember(
                sessionId: sessionId,
                state: "running",
                parentSessionId: "parent",
                rootSessionId: "parent"
            )
        ]
        let logURL = temp.appendingPathComponent("guard.log")

        let output = HookHandlers.handleGuard(input, members: members, logURL: logURL)

        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        )
        let specific = try #require(object["hookSpecificOutput"] as? [String: Any])
        #expect(specific["hookEventName"] as? String == "PreToolUse")
        #expect(specific["permissionDecision"] as? String == "deny")
        #expect(try String(contentsOf: logURL, encoding: .utf8).contains("guard deny"))
    }

    @Test func guardAllowsTopLevelSession() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let sessionId = UUID().uuidString
        let input = makeInput(
            event: "PreToolUse",
            sessionId: sessionId,
            prompt: nil,
            toolName: "CreateSessions"
        )
        let members = [
            SessionMember(
                sessionId: sessionId,
                state: "running",
                parentSessionId: nil,
                rootSessionId: nil
            )
        ]

        let output = HookHandlers.handleGuard(
            input,
            members: members,
            logURL: temp.appendingPathComponent("guard.log")
        )

        #expect(output.isEmpty)
    }

    @Test func guardIgnoresOtherTools() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let sessionId = UUID().uuidString
        let input = makeInput(
            event: "PreToolUse",
            sessionId: sessionId,
            prompt: nil,
            toolName: "Bash"
        )
        let members = [
            SessionMember(
                sessionId: sessionId,
                state: "running",
                parentSessionId: "parent",
                rootSessionId: "parent"
            )
        ]

        #expect(
            HookHandlers.handleGuard(
                input,
                members: members,
                logURL: temp.appendingPathComponent("guard.log")
            ).isEmpty
        )
    }

    @Test func guardFailsOpenForUnknownSession() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let input = makeInput(
            event: "PreToolUse",
            sessionId: UUID().uuidString,
            prompt: nil,
            toolName: "CreateSession"
        )

        #expect(
            HookHandlers.handleGuard(
                input,
                members: [],
                logURL: temp.appendingPathComponent("guard.log")
            ).isEmpty
        )
    }

    @Test func hookLogRotatesWhenLarge() throws {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let logURL = temp.appendingPathComponent("errors.log")
        let filler = Data(repeating: 0x41, count: Int(HookHandlers.logRotationThreshold))
        try filler.write(to: logURL)

        HookHandlers.appendLog("entry", to: logURL)

        let rotated = URL(fileURLWithPath: logURL.path + ".1")
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        #expect(try String(contentsOf: logURL, encoding: .utf8).contains("entry"))
        let attributes = try FileManager.default.attributesOfItem(atPath: rotated.path)
        #expect((attributes[.size] as? NSNumber)?.intValue == filler.count)
    }

    @Test func hookSynthesizesPeersFromRegisteredSessions() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        _ = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "a", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "b", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        #expect(output.contains("[mesh-peer] a running"))
        #expect(!output.contains("[mesh-peer] b"))
    }

    @Test func hookFiltersPeersByProjectRoot() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            makeSession(id: "other", projectRoot: "/tmp/other-proj", lastSeen: now),
            makeSession(id: "same", projectRoot: "/tmp/session-mesh-proj", lastSeen: now)
        ]

        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: now,
            stateURL: temp.appendingPathComponent("roster.json"),
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { sessions }
        )

        #expect(output.contains("[mesh-peer] same"))
        #expect(!output.contains("[mesh-peer] other"))
    }

    @Test func hookMatchesPeersByWorkDirWhenProjectRootMissing() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        var session = makeSession(id: "by-workdir", projectRoot: nil, lastSeen: now)
        session.workDir = "/tmp/session-mesh-proj"

        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: now,
            stateURL: temp.appendingPathComponent("roster.json"),
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [session] }
        )

        #expect(output.contains("[mesh-peer] by-workdir"))
    }

    @Test func hookMissingSessionIdReturnsEmpty() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let stateURL = temp.appendingPathComponent("roster.json")
        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: nil, prompt: nil),
            now: Date(timeIntervalSince1970: 1_000_000),
            stateURL: stateURL,
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [] }
        )

        #expect(output == "")
        #expect(!FileManager.default.fileExists(atPath: stateURL.path))
    }

    @Test func hookCorruptStoreFailsOpen() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        try? Data("garbage".utf8).write(to: stateURL)

        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [] }
        )

        #expect(output.contains("peers=0"))
        #expect(HookHandlers.loadStore(from: stateURL)["self"] != nil)
    }

    @Test func hookTopicUsesFirstLineAndSanitizes() {
        #expect(HookHandlers.topic(from: nil) == "")
        #expect(HookHandlers.topic(from: "line1\nline2") == "line1")
        #expect(HookHandlers.topic(from: String(repeating: "x", count: 100)) == String(repeating: "x", count: 60))
    }

    @Test func hookTopicSkipsTeammateMessageWrapper() {
        let wrapped = """
        <teammate-message teammate_id="team-lead" summary="sync">
        Fix the roster now
        </teammate-message>
        """
        #expect(HookHandlers.topic(from: wrapped) == "Fix the roster now")

        let wrapperOnly = """
        <teammate-message teammate_id="team-lead" summary="empty">
        </teammate-message>
        """
        #expect(HookHandlers.topic(from: wrapperOnly) == "")
    }

    @Test func hookDescribeFormatsRelativeTime() {
        #expect(HookHandlers.describe(30) == "now")
        #expect(HookHandlers.describe(300) == "5m")
        #expect(HookHandlers.describe(7_200) == "2h")
    }

    @Test func hookOutputLinesFormat() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let peers = [
            RosterPeer(id: "p1", title: "T", state: .running, lastSeen: now.addingTimeInterval(-300)),
            RosterPeer(id: "p2", title: "", state: .stopped, lastSeen: now.addingTimeInterval(-7_200))
        ]

        let withoutPolicy = HookHandlers.output(projectRoot: "/p", peers: peers, includePolicy: false, now: now)
        #expect(withoutPolicy.split(separator: "\n").count == 3)
        #expect(!withoutPolicy.contains("mesh-policy"))
        #expect(withoutPolicy.contains("[mesh-peer] p1 running 5m T"))
        #expect(withoutPolicy.contains("[mesh-peer] p2 idle 2h"))

        let withPolicy = HookHandlers.output(projectRoot: "/p", peers: peers, includePolicy: true, now: now)
        #expect(withPolicy.contains(HookHandlers.policyLine))
    }

    @Test func hookOutputDoesNotTruncateProjectPath() {
        let longPath = "/tmp/" + String(repeating: "d", count: 80) + "/proj"
        let now = Date(timeIntervalSince1970: 1_000_000)

        let output = HookHandlers.output(projectRoot: longPath, peers: [], includePolicy: false, now: now)

        #expect(output.contains("project=\(longPath)"))
    }

    @Test func hookLoadStoreClearsWrapperPollutedTitles() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let stateURL = temp.appendingPathComponent("roster.json")
        let legacy = """
        {"version":1,"sessions":{"polluted":{"sessionId":"polluted","projectRoot":"/p","title":"<teammate-message teammate_id=\\"x\\" summary=\\"y\\"","lastSeen":1000000},"clean":{"sessionId":"clean","projectRoot":"/p","title":"ok","lastSeen":1000000}}}
        """
        try? Data(legacy.utf8).write(to: stateURL)

        let store = HookHandlers.loadStore(from: stateURL)
        #expect(store["polluted"]?.title == "")
        #expect(store["clean"]?.title == "ok")
    }

    @Test func hookRosterDeduplicatesSameAgentGhosts() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let records = [
            "old": HookSessionRecord(
                sessionId: "old",
                projectRoot: "/p",
                agentType: "some-agent",
                title: "stale",
                lastSeen: now.addingTimeInterval(-600),
                state: .stopped
            ),
            "new": HookSessionRecord(
                sessionId: "new",
                projectRoot: "/p",
                agentType: "some-agent",
                title: "fresh",
                lastSeen: now,
                state: .running
            )
        ]

        let sessions = HookHandlers.sessionsForProject(referenceRoot: "/p", records: records, loaded: [])

        #expect(sessions.map(\.id) == ["new"])
        #expect(sessions.first?.title == "fresh")
    }

    // MARK: - Phase 2: stop/end 状态与格式

    @Test func hookStopMarksSessionStoppedAndOutputsNothing() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        _ = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        let output = HookHandlers.handle(
            makeInput(event: "Stop", sessionId: "self", prompt: nil),
            now: now.addingTimeInterval(60),
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        #expect(output == "")
        #expect(HookHandlers.loadStore(from: stateURL)["self"]?.state == .stopped)
        #expect(HookHandlers.loadStore(from: stateURL)["self"]?.lastSeen == now.addingTimeInterval(60))
    }

    @Test func hookEndMarksSessionCompleted() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        _ = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [] }
        )
        _ = HookHandlers.handle(
            makeInput(event: "SessionEnd", sessionId: "self", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [] }
        )

        #expect(HookHandlers.loadStore(from: stateURL)["self"]?.state == .completed)
    }

    @Test func hookStoppedPeerShowsAsIdle() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stateURL = temp.appendingPathComponent("roster.json")
        let logURL = temp.appendingPathComponent("errors.log")
        _ = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "a", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )
        _ = HookHandlers.handle(
            makeInput(event: "Stop", sessionId: "a", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "b", prompt: nil),
            now: now,
            stateURL: stateURL,
            logURL: logURL,
            loadSessions: { [] }
        )

        #expect(output.contains("[mesh-peer] a idle"))
    }

    @Test func hookUnknownEventWritesNothing() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let stateURL = temp.appendingPathComponent("roster.json")

        let output = HookHandlers.handle(
            makeInput(event: "PermissionRequest", sessionId: "self", prompt: nil),
            now: Date(timeIntervalSince1970: 1_000_000),
            stateURL: stateURL,
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [] }
        )

        #expect(output == "")
        #expect(!FileManager.default.fileExists(atPath: stateURL.path))
    }

    @Test func hookOutputEscapesAndTruncatesNastyTitles() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let nasty = "a\"b\\c\nd" + String(repeating: "x", count: 70)
        var session = makeSession(id: "nasty", projectRoot: "/tmp/session-mesh-proj", lastSeen: now)
        session.title = nasty

        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: now,
            stateURL: temp.appendingPathComponent("roster.json"),
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [session] }
        )

        let peerLine = output.split(separator: "\n").first { $0.contains("nasty") }
        #expect(peerLine != nil)
        #expect(!String(peerLine!).contains("\n"))
        #expect(String(peerLine!).contains("\\\""))
        #expect(String(peerLine!).contains("\\\\"))
        #expect(String(peerLine!).count < 120)
    }

    @Test func hookStoreToleratesMissingStateField() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let stateURL = temp.appendingPathComponent("roster.json")
        let legacy = """
        {"version":1,"sessions":{"old":{"sessionId":"old","projectRoot":"/p","title":"t","lastSeen":1000000}}}
        """
        try? Data(legacy.utf8).write(to: stateURL)

        let store = HookHandlers.loadStore(from: stateURL)
        #expect(store["old"]?.state == nil)

        let sessions = HookHandlers.sessionsForProject(
            referenceRoot: "/p",
            records: store,
            loaded: []
        )
        #expect(sessions.first?.id == "old")
        #expect(sessions.first?.state == .running)
    }

    @Test func hookStoreToleratesWrongTypes() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let stateURL = temp.appendingPathComponent("roster.json")
        try? Data(#"{"version":1,"sessions":[]}"#.utf8).write(to: stateURL)

        #expect(HookHandlers.loadStore(from: stateURL).isEmpty)
    }

    @Test func hookGroupsWorktreePeersUnderMainRoot() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let main = temp.appendingPathComponent("main")
        let worktree = temp.appendingPathComponent("wt")
        try? FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        _ = Shell.run(executable: "/usr/bin/git", arguments: ["-C", main.path, "init", "-q"])
        _ = Shell.run(executable: "/usr/bin/git", arguments: ["-C", main.path, "config", "user.email", "t@t"])
        _ = Shell.run(executable: "/usr/bin/git", arguments: ["-C", main.path, "config", "user.name", "t"])
        try? Data("x".utf8).write(to: main.appendingPathComponent("f.txt"))
        _ = Shell.run(executable: "/usr/bin/git", arguments: ["-C", main.path, "add", "-A"])
        _ = Shell.run(executable: "/usr/bin/git", arguments: ["-C", main.path, "commit", "-q", "-m", "init"])
        _ = Shell.run(executable: "/usr/bin/git", arguments: ["-C", main.path, "worktree", "add", "-q", worktree.path])
        defer { _ = Shell.run(executable: "/usr/bin/git", arguments: ["-C", main.path, "worktree", "remove", "--force", worktree.path]) }

        let now = Date(timeIntervalSince1970: 1_000_000)
        let mainRoot = ProjectIdentity.projectRoot(for: main.path)
        #expect(ProjectIdentity.projectRoot(for: worktree.path) == mainRoot)

        let peer = makeSession(id: "wt-peer", projectRoot: mainRoot, lastSeen: now)
        let output = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil, cwd: worktree.path),
            now: now,
            stateURL: temp.appendingPathComponent("roster.json"),
            logURL: temp.appendingPathComponent("errors.log"),
            loadSessions: { [peer] }
        )

        #expect(output.contains("[mesh-peer] wt-peer"))
    }

    @Test func hookLogFileGetsOwnerOnlyPermissions() {
        let temp = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let logURL = temp.appendingPathComponent("errors.log")
        try? Data("block".utf8).write(to: temp.appendingPathComponent("blocker"))

        _ = HookHandlers.handle(
            makeInput(event: "SessionStart", sessionId: "self", prompt: nil),
            now: Date(timeIntervalSince1970: 1_000_000),
            stateURL: temp.appendingPathComponent("blocker/roster.json"),
            logURL: logURL,
            loadSessions: { [] }
        )

        let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        #expect(attributes?[.posixPermissions] as? Int == 0o600)
    }

    // MARK: - Helpers

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeInput(
        event: String,
        sessionId: String?,
        prompt: String?,
        cwd: String = "/tmp/session-mesh-proj",
        toolName: String? = nil
    ) -> HookInput {
        var payload: [String: String] = [
            "hook_event_name": event,
            "cwd": cwd
        ]
        if let sessionId {
            payload["session_id"] = sessionId
        }
        if let prompt {
            payload["prompt"] = prompt
        }
        if let toolName {
            payload["tool_name"] = toolName
        }
        return HookInput(data: try! JSONSerialization.data(withJSONObject: payload))!
    }

    private func makeSession(
        id: String,
        projectRoot: String?,
        lastSeen: Date
    ) -> Session {
        Session(
            id: id,
            title: "title-\(id)",
            state: .running,
            lastSeen: lastSeen,
            projectRoot: projectRoot,
            workDir: nil,
            parentSessionId: nil,
            rootSessionId: nil
        )
    }
}
