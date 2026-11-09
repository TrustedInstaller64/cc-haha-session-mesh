import Foundation

enum HookEvent: Equatable {
    case sessionStart
    case userPromptSubmit
    case stop
    case sessionEnd
    case unknown(String)

    init(name: String?) {
        switch name {
        case "SessionStart":
            self = .sessionStart
        case "UserPromptSubmit":
            self = .userPromptSubmit
        case "Stop":
            self = .stop
        case "SessionEnd":
            self = .sessionEnd
        case let other?:
            self = .unknown(other)
        case nil:
            self = .unknown("")
        }
    }
}

struct HookInput: Equatable {
    let event: HookEvent
    let sessionId: String?
    let transcriptPath: String?
    let cwd: String?
    let agentType: String?
    let permissionMode: String?
    let source: String?
    let prompt: String?
    let stopHookActive: Bool?
    let lastAssistantMessage: String?
    let toolName: String?

    // hook 路径 fail-open：任何解析失败返回 nil，调用方照常 exit 0
    init?(data: Data) {
        guard let raw = try? JSONDecoder().decode(RawPayload.self, from: data) else {
            return nil
        }
        event = HookEvent(name: raw.hookEventName)
        sessionId = raw.sessionId
        transcriptPath = raw.transcriptPath
        cwd = raw.cwd
        agentType = raw.agentType
        permissionMode = raw.permissionMode
        source = raw.source
        prompt = raw.prompt
        stopHookActive = raw.stopHookActive
        lastAssistantMessage = raw.lastAssistantMessage
        toolName = raw.toolName
    }
}

private struct RawPayload: Decodable {
    let hookEventName: String?
    let sessionId: String?
    let transcriptPath: String?
    let cwd: String?
    let agentType: String?
    let permissionMode: String?
    let source: String?
    let prompt: String?
    let stopHookActive: Bool?
    let lastAssistantMessage: String?
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case agentType = "agent_type"
        case permissionMode = "permission_mode"
        case source
        case prompt
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
        case toolName = "tool_name"
    }
}
