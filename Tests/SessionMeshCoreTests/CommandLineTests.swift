import Foundation
import Testing
@testable import SessionMeshCore

struct CommandLineTests {
    @Test func usageListsEveryCommand() {
        let commands = [
            "install", "uninstall", "doctor",
            "hook-start", "hook-prompt", "hook-stop", "hook-end",
            "help"
        ]

        for command in commands {
            #expect(SessionMeshCLI.usage.contains(command))
        }
        #expect(SessionMeshCLI.usage.contains("--scope project|user"))
    }

    @Test func noArgumentsShowsUsageAndSucceeds() {
        let result = runCommand([])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("Usage:"))
        #expect(result.error.isEmpty)
    }

    @Test func helpFlagsShowUsage() {
        for flag in ["help", "--help", "-h"] {
            let result = runCommand([flag])
            #expect(result.exitCode == 0)
            #expect(result.output.contains("Usage:"))
        }
    }

    @Test func installDefaultsToApplyModeAndProjectScope() throws {
        #expect(try SessionMeshCLI.parse(["install"]) == .install(.apply, .project))
    }

    @Test func installParsesDryRunMode() throws {
        #expect(try SessionMeshCLI.parse(["install", "--dry-run"]) == .install(.dryRun, .project))
    }

    @Test func installParsesCheckMode() throws {
        #expect(try SessionMeshCLI.parse(["install", "--check"]) == .install(.check, .project))
    }

    @Test func uninstallDefaultsToApplyModeAndProjectScope() throws {
        #expect(try SessionMeshCLI.parse(["uninstall"]) == .uninstall(.apply, .project))
    }

    @Test func uninstallParsesDryRunMode() throws {
        #expect(try SessionMeshCLI.parse(["uninstall", "--dry-run"]) == .uninstall(.dryRun, .project))
    }

    @Test func installParsesUserScope() throws {
        #expect(try SessionMeshCLI.parse(["install", "--scope", "user"]) == .install(.apply, .user))
    }

    @Test func installParsesScopeAfterMode() throws {
        #expect(
            try SessionMeshCLI.parse(["install", "--dry-run", "--scope", "user"])
                == .install(.dryRun, .user)
        )
    }

    @Test func uninstallParsesUserScope() throws {
        #expect(
            try SessionMeshCLI.parse(["uninstall", "--scope", "user", "--dry-run"])
                == .uninstall(.dryRun, .user)
        )
    }

    @Test func installRejectsInvalidScope() {
        #expect(throws: SessionMeshCLI.ParseError.invalidScope(command: "install", value: "team")) {
            try SessionMeshCLI.parse(["install", "--scope", "team"])
        }
    }

    @Test func scopeRequiresValue() {
        #expect(throws: SessionMeshCLI.ParseError.invalidScope(command: "install", value: "")) {
            try SessionMeshCLI.parse(["install", "--scope"])
        }
    }

    @Test func installRejectsDuplicateScope() {
        #expect(throws: SessionMeshCLI.ParseError.invalidOption(command: "install", option: "--scope")) {
            try SessionMeshCLI.parse(["install", "--scope", "user", "--scope", "project"])
        }
    }

    @Test func uninstallRejectsCheckMode() {
        #expect(throws: SessionMeshCLI.ParseError.invalidOption(command: "uninstall", option: "--check")) {
            try SessionMeshCLI.parse(["uninstall", "--check"])
        }
    }

    @Test func installRejectsUnknownOption() {
        #expect(throws: SessionMeshCLI.ParseError.invalidOption(command: "install", option: "--force")) {
            try SessionMeshCLI.parse(["install", "--force"])
        }
    }

    @Test func installRejectsConflictingModeOptions() {
        #expect(throws: SessionMeshCLI.ParseError.invalidOption(command: "install", option: "--check")) {
            try SessionMeshCLI.parse(["install", "--dry-run", "--check"])
        }
    }

    @Test func doctorRejectsExtraArguments() {
        #expect(throws: SessionMeshCLI.ParseError.unexpectedArguments("doctor")) {
            try SessionMeshCLI.parse(["doctor", "--verbose"])
        }
    }

    @Test func unknownCommandFailsWithUsageError() {
        let result = runCommand(["unknown"])

        #expect(result.exitCode == 2)
        #expect(result.output.isEmpty)
        #expect(result.error.contains("Unknown command: unknown"))
        #expect(result.error.contains("Usage:"))
    }

    @Test func hookCommandsSucceed() {
        for name in SessionMeshCLI.HookCommand.allCases.map(\.rawValue) {
            let result = runCommand([name])
            #expect(result.exitCode == 0)
        }
    }

    @Test func hookCommandsIgnoreExtraArguments() {
        let result = runCommand(["hook-start", "--unexpected"])

        #expect(result.exitCode == 0)
    }

    @Test func hookCommandsPrintHandlerOutput() throws {
        let input = try makeHookInput()
        let result = runCommand(
            ["hook-prompt"],
            hookInput: { input },
            hookOutput: { _ in "[mesh-roster] project=/tmp peers=0" }
        )

        #expect(result.exitCode == 0)
        #expect(result.output.contains("[mesh-roster] project=/tmp peers=0"))
        #expect(result.error.isEmpty)
    }

    @Test func hookCommandsStayFailOpenWithoutInput() {
        let result = runCommand(["hook-start"], hookInput: { nil })

        #expect(result.exitCode == 0)
        #expect(result.output.isEmpty)
        #expect(result.error.isEmpty)
    }

    @Test func hookCommandsStayFailOpenWhenHandlerReturnsEmpty() throws {
        let input = try makeHookInput()
        let result = runCommand(
            ["hook-end"],
            hookInput: { input },
            hookOutput: { _ in "" }
        )

        #expect(result.exitCode == 0)
        #expect(result.output.isEmpty)
    }

    // MARK: - Helpers

    private func makeHookInput() throws -> HookInput {
        let payload = Data(#"{"hook_event_name":"SessionStart","session_id":"session-1","cwd":"/tmp"}"#.utf8)
        return try #require(HookInput(data: payload))
    }

    private func runCommand(
        _ arguments: [String],
        hookInput: () -> HookInput? = { nil },
        hookOutput: (HookInput) -> String = { _ in "" }
    ) -> (exitCode: Int32, output: String, error: String) {
        var output = ""
        var error = ""
        let exitCode = SessionMeshCLI.run(
            arguments: arguments,
            writeOutput: { output += $0 + "\n" },
            writeError: { error += $0 + "\n" },
            hookInput: hookInput,
            hookOutput: hookOutput
        )
        return (exitCode, output, error)
    }
}
