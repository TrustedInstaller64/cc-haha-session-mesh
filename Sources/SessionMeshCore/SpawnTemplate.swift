import Foundation

struct SpawnRequest {
    var projectShortName: String
    var role: String
    var task: String
    var goal: String
    var background: String
    var constraints: [String]
    var workDir: String
    var deliverable: String
    var acceptanceCriteria: [String]
    var collaboration: String
    var reportTo: String
    var isChildSession: Bool = false
}

struct SpawnPlan: Equatable {
    let title: String
    let prompt: String
}

enum SpawnTemplateError: LocalizedError, Equatable {
    case emptyField(String)
    case invalidSessionCount(Int, maximum: Int)
    case recursionNotAllowed

    var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "Spawn field is empty: \(field)"
        case .invalidSessionCount(let count, let maximum):
            return "Spawn count \(count) is outside 1...\(maximum)"
        case .recursionNotAllowed:
            return "Child sessions must not create further sessions"
        }
    }
}

enum SpawnTemplate {
    static let maxTitleLength = 60
    static let maxNewSessionsPerRequest = 2
    static let titleSeparator = " · "
    static let sectionTitles = [
        "目标", "背景", "约束", "工作目录", "交付物", "验收", "协作协议", "回报对象"
    ]
    static let capabilityPolicy = "- 允许使用会话语义内的智能体团队、斜杠命令、工作流（优先 deep-research）、技能与 MCP；不创建全局 Team、不合并 peer 团队、不绕过权限/模型卡。"

    /// 不写入 runtime 选择；调用方必须经模型分配卡由用户确认后再创建。
    static func plan(for request: SpawnRequest) throws -> SpawnPlan {
        guard !request.isChildSession else {
            throw SpawnTemplateError.recursionNotAllowed
        }
        return SpawnPlan(
            title: try makeTitle(
                projectShortName: request.projectShortName,
                role: request.role,
                task: request.task
            ),
            prompt: try makePrompt(for: request)
        )
    }

    static func makeTitle(projectShortName: String, role: String, task: String) throws -> String {
        let segments = try [projectShortName, role, task].map { try normalized($0, field: "title") }
        let title = segments.joined(separator: titleSeparator)
        guard title.count > maxTitleLength else {
            return title
        }
        return String(title.prefix(maxTitleLength - 1)) + "…"
    }

    static func validateNewSessionCount(_ count: Int) throws {
        guard (1...maxNewSessionsPerRequest).contains(count) else {
            throw SpawnTemplateError.invalidSessionCount(count, maximum: maxNewSessionsPerRequest)
        }
    }

    static func makePrompt(for request: SpawnRequest) throws -> String {
        let goal = try normalized(request.goal, field: "goal")
        let background = try normalized(request.background, field: "background")
        let constraints = try normalizedList(request.constraints, field: "constraints")
        let workDir = try normalized(request.workDir, field: "workDir")
        let deliverable = try normalized(request.deliverable, field: "deliverable")
        let acceptance = try normalizedList(request.acceptanceCriteria, field: "acceptanceCriteria")
        let collaboration = try normalized(request.collaboration, field: "collaboration")
        let reportTo = try normalized(request.reportTo, field: "reportTo")

        let sections = [
            ("目标", goal),
            ("背景", background),
            ("约束", bulletList(constraints)),
            ("工作目录", workDir),
            ("交付物", deliverable),
            ("验收", bulletList(acceptance)),
            ("协作协议", collaboration + "\n- 不要自行新建会话；需要额外会话时写进报告，由发起方处理。\n" + capabilityPolicy),
            ("回报对象", reportTo)
        ]
        return sections.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n\n")
    }

    private static func normalized(_ value: String, field: String) throws -> String {
        let cleaned = Redaction.stripControlCharacters(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw SpawnTemplateError.emptyField(field)
        }
        return cleaned
    }

    private static func normalizedList(_ values: [String], field: String) throws -> [String] {
        guard !values.isEmpty else {
            throw SpawnTemplateError.emptyField(field)
        }
        return try values.map { try normalized($0, field: field) }
    }

    private static func bulletList(_ values: [String]) -> String {
        values.map { "- \($0)" }.joined(separator: "\n")
    }
}
