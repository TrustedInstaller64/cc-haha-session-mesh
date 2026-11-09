import Darwin
import Foundation

public enum SessionMeshCLI {
    enum Command: Equatable {
        case help
        case install(CommandMode, CommandScope)
        case uninstall(CommandMode, CommandScope)
        case doctor
        case hook(HookCommand)
    }

    enum CommandMode: Equatable {
        case apply
        case dryRun
        case check
    }

    enum CommandScope: String, CaseIterable, Equatable {
        case project
        case user
    }

    enum HookCommand: String, CaseIterable {
        case start = "hook-start"
        case prompt = "hook-prompt"
        case stop = "hook-stop"
        case end = "hook-end"
        case guardSpawn = "hook-guard"
    }

    enum ParseError: LocalizedError, Equatable {
        case unknownCommand(String)
        case invalidOption(command: String, option: String)
        case invalidScope(command: String, value: String)
        case unexpectedArguments(String)

        var errorDescription: String? {
            switch self {
            case .unknownCommand(let name):
                return "Unknown command: \(name)"
            case .invalidOption(let command, let option):
                return "Invalid option for \(command): \(option)"
            case .invalidScope(let command, let value):
                let display = value.isEmpty ? "(missing)" : value
                return "Invalid scope for \(command): \(display) (expected project or user)"
            case .unexpectedArguments(let command):
                return "Unexpected arguments for \(command)"
            }
        }
    }

    static let usage = """
    Usage:
      session-mesh install [--dry-run | --check] [--scope project|user]
      session-mesh uninstall [--dry-run] [--scope project|user]
      session-mesh doctor
      session-mesh hook-start | hook-prompt | hook-stop | hook-end | hook-guard
      session-mesh help

    Default scope: project.
    Exit codes: 0 success, 1 runtime failure, 2 usage error.
    Hook commands always exit 0.
    """

    public static func run(
        arguments: [String],
        writeOutput: @escaping (String) -> Void = { print($0) },
        writeError: @escaping (String) -> Void = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    ) -> Int32 {
        run(
            arguments: arguments,
            writeOutput: writeOutput,
            writeError: writeError,
            hookInput: {
                if isatty(STDIN_FILENO) != 0 {
                    return nil
                }
                return HookHandlers.readInput()
            },
            hookOutput: { HookHandlers.handle($0) }
        )
    }

    static func run(
        arguments: [String],
        writeOutput: @escaping (String) -> Void,
        writeError: @escaping (String) -> Void,
        hookInput: () -> HookInput?,
        hookOutput: (HookInput) -> String
    ) -> Int32 {
        let command: Command
        do {
            command = try parse(arguments)
        } catch {
            // hook 路径必须 fail-open，参数异常也不能阻塞宿主
            if let first = arguments.first, HookCommand(rawValue: first) != nil {
                return 0
            }
            writeError(error.localizedDescription)
            writeError(usage)
            return 2
        }

        switch command {
        case .help:
            writeOutput(usage)
            return 0
        case .install(let mode, let scope):
            return runInstaller(
                mode: mode,
                scope: scope,
                isInstalling: true,
                writeOutput: writeOutput,
                writeError: writeError
            )
        case .uninstall(let mode, let scope):
            return runInstaller(
                mode: mode,
                scope: scope,
                isInstalling: false,
                writeOutput: writeOutput,
                writeError: writeError
            )
        case .doctor:
            return Doctor.run(writeOutput: writeOutput)
        case .hook(.guardSpawn):
            return runHook(
                hookInput: hookInput,
                hookOutput: HookHandlers.handleGuard,
                writeOutput: writeOutput
            )
        case .hook:
            return runHook(hookInput: hookInput, hookOutput: hookOutput, writeOutput: writeOutput)
        }
    }

    static func parse(_ arguments: [String]) throws -> Command {
        guard let name = arguments.first else {
            return .help
        }
        let options = Array(arguments.dropFirst())

        switch name {
        case "help", "--help", "-h":
            return .help
        case "install":
            let parsed = try parseOptions(options, allowingCheck: true, command: name)
            return .install(parsed.mode, parsed.scope)
        case "uninstall":
            let parsed = try parseOptions(options, allowingCheck: false, command: name)
            return .uninstall(parsed.mode, parsed.scope)
        case "doctor":
            guard options.isEmpty else {
                throw ParseError.unexpectedArguments(name)
            }
            return .doctor
        default:
            if let hook = HookCommand(rawValue: name) {
                return .hook(hook)
            }
            throw ParseError.unknownCommand(name)
        }
    }

    private struct ParsedOptions {
        var mode: CommandMode = .apply
        var scope: CommandScope = .project
    }

    private static func parseOptions(
        _ options: [String],
        allowingCheck: Bool,
        command: String
    ) throws -> ParsedOptions {
        var parsed = ParsedOptions()
        var index = 0
        var hasScope = false

        while index < options.count {
            let option = options[index]
            switch option {
            case "--dry-run":
                guard parsed.mode == .apply else {
                    throw ParseError.invalidOption(command: command, option: option)
                }
                parsed.mode = .dryRun
                index += 1
            case "--check" where allowingCheck:
                guard parsed.mode == .apply else {
                    throw ParseError.invalidOption(command: command, option: option)
                }
                parsed.mode = .check
                index += 1
            case "--scope":
                guard !hasScope else {
                    throw ParseError.invalidOption(command: command, option: option)
                }
                guard index + 1 < options.count else {
                    throw ParseError.invalidScope(command: command, value: "")
                }
                let rawScope = options[index + 1]
                guard let scope = CommandScope(rawValue: rawScope) else {
                    throw ParseError.invalidScope(command: command, value: rawScope)
                }
                parsed.scope = scope
                hasScope = true
                index += 2
            default:
                throw ParseError.invalidOption(command: command, option: option)
            }
        }
        return parsed
    }

    private static func runHook(
        hookInput: () -> HookInput?,
        hookOutput: (HookInput) -> String,
        writeOutput: (String) -> Void
    ) -> Int32 {
        guard let input = hookInput() else {
            return 0
        }
        let output = hookOutput(input)
        if !output.isEmpty {
            writeOutput(output)
        }
        return 0
    }

    private static func runInstaller(
        mode: CommandMode,
        scope: CommandScope,
        isInstalling: Bool,
        writeOutput: (String) -> Void,
        writeError: (String) -> Void
    ) -> Int32 {
        let projectRootPath = ProjectIdentity.workingTreeRoot(
            for: FileManager.default.currentDirectoryPath
        )
        let installer = Installer(
            scope: makeInstallScope(scope),
            projectRoot: URL(fileURLWithPath: projectRootPath, isDirectory: true)
        )
        do {
            let installMode = makeInstallMode(mode)
            let plan = isInstalling
                ? try installer.install(mode: installMode)
                : try installer.uninstall(mode: installMode)
            writeOutput(describe(plan, mode: mode, isInstalling: isInstalling))
            return 0
        } catch {
            writeError(error.localizedDescription)
            return 1
        }
    }

    private static func makeInstallMode(_ mode: CommandMode) -> InstallMode {
        switch mode {
        case .apply:
            return .apply
        case .dryRun:
            return .dryRun
        case .check:
            return .check
        }
    }

    private static func makeInstallScope(_ scope: CommandScope) -> InstallScope {
        switch scope {
        case .project:
            return .project
        case .user:
            return .user
        }
    }

    private static func describe(_ plan: InstallPlan, mode: CommandMode, isInstalling: Bool) -> String {
        let action = isInstalling ? "install" : "uninstall"
        let prefix: String
        switch mode {
        case .apply:
            prefix = action
        case .dryRun:
            prefix = "\(action) (dry run)"
        case .check:
            prefix = "\(action) (check)"
        }
        let scopeName: String
        switch plan.scope {
        case .project:
            scopeName = "project"
        case .user:
            scopeName = "user"
        }
        var lines = [
            "\(prefix): settings=\(plan.settingsURL.path)",
            "scope: \(scopeName) root=\(plan.projectRoot?.path ?? "-")",
            "binary: \(plan.binaryDestination.path)",
            "skill: \(plan.skillDestination.path)"
        ]
        lines.append(contentsOf: plan.notes)
        return lines.joined(separator: "\n")
    }
}
