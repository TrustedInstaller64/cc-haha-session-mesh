import Foundation
import Testing
@testable import SessionMeshCore

struct SpawnTemplateTests {
    @Test func titleJoinsProjectRoleAndTask() throws {
        let title = try SpawnTemplate.makeTitle(
            projectShortName: "session-mesh",
            role: "docs",
            task: "skill policy"
        )

        #expect(title == "session-mesh · docs · skill policy")
    }

    @Test func titleTruncatesToSixtyCharacters() throws {
        let title = try SpawnTemplate.makeTitle(
            projectShortName: "session-mesh",
            role: "engineer",
            task: String(repeating: "x", count: 80)
        )

        #expect(title.count == SpawnTemplate.maxTitleLength)
        #expect(title.hasSuffix("…"))
    }

    @Test func titleStripsControlCharacters() throws {
        let title = try SpawnTemplate.makeTitle(
            projectShortName: "session\nmesh",
            role: "docs",
            task: "policy"
        )

        #expect(title == "sessionmesh · docs · policy")
    }

    @Test func titleRejectsEmptySegment() {
        #expect(throws: SpawnTemplateError.emptyField("title")) {
            try SpawnTemplate.makeTitle(projectShortName: " ", role: "docs", task: "policy")
        }
    }

    @Test func promptContainsEightSectionsInOrder() throws {
        let prompt = try SpawnTemplate.makePrompt(for: makeRequest())
        let blocks = prompt.components(separatedBy: "\n\n")

        #expect(blocks.count == SpawnTemplate.sectionTitles.count)
        for (index, section) in SpawnTemplate.sectionTitles.enumerated() {
            #expect(blocks[index].hasPrefix(section + "\n"))
        }
    }

    @Test func promptIncludesSelfContainedContext() throws {
        let request = makeRequest()
        let prompt = try SpawnTemplate.makePrompt(for: request)

        #expect(prompt.contains(request.goal))
        #expect(prompt.contains(request.background))
        #expect(prompt.contains(request.constraints[0]))
        #expect(prompt.contains(request.workDir))
        #expect(prompt.contains(request.deliverable))
        #expect(prompt.contains(request.acceptanceCriteria[0]))
        #expect(prompt.contains(request.collaboration))
        #expect(prompt.contains(request.reportTo))
        #expect(prompt.contains("- 不要自行新建会话"))
        #expect(prompt.contains("智能体团队"))
        #expect(prompt.contains("deep-research"))
        #expect(prompt.contains("不创建全局 Team"))
    }

    @Test func promptRejectsEmptyField() {
        var request = makeRequest()
        request.background = "  \n"

        #expect(throws: SpawnTemplateError.emptyField("background")) {
            try SpawnTemplate.makePrompt(for: request)
        }
    }

    @Test func promptRejectsEmptyList() {
        var request = makeRequest()
        request.acceptanceCriteria = []

        #expect(throws: SpawnTemplateError.emptyField("acceptanceCriteria")) {
            try SpawnTemplate.makePrompt(for: request)
        }
    }

    @Test func childSessionCannotSpawn() {
        var request = makeRequest()
        request.isChildSession = true

        #expect(throws: SpawnTemplateError.recursionNotAllowed) {
            try SpawnTemplate.plan(for: request)
        }
    }

    @Test func planRendersTitleAndPrompt() throws {
        let plan = try SpawnTemplate.plan(for: makeRequest())

        #expect(plan.title == "session-mesh · docs · summarize findings")
        #expect(plan.prompt.hasPrefix("目标\nSummarize Phase 0 findings."))
    }

    @Test func sessionLimitAcceptsOneOrTwo() throws {
        try SpawnTemplate.validateNewSessionCount(1)
        try SpawnTemplate.validateNewSessionCount(2)
    }

    @Test func sessionLimitRejectsZeroAndThree() {
        #expect(throws: SpawnTemplateError.invalidSessionCount(0, maximum: 2)) {
            try SpawnTemplate.validateNewSessionCount(0)
        }
        #expect(throws: SpawnTemplateError.invalidSessionCount(3, maximum: 2)) {
            try SpawnTemplate.validateNewSessionCount(3)
        }
    }

    // MARK: - Helpers

    private func makeRequest() -> SpawnRequest {
        SpawnRequest(
            projectShortName: "session-mesh",
            role: "docs",
            task: "summarize findings",
            goal: "Summarize Phase 0 findings.",
            background: "The findings file mixes hooks and transport evidence.",
            constraints: ["Do not copy transcripts.", "Keep markers."],
            workDir: "/tmp/session-mesh",
            deliverable: "Updated findings document.",
            acceptanceCriteria: ["Every fact has a V or A marker.", "No secrets."],
            collaboration: "Ask the transport owner for missing evidence.",
            reportTo: "team-lead"
        )
    }
}
