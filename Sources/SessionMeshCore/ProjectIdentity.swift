import Foundation

enum ProjectIdentity {
    // 安装路径跟随当前 worktree；项目归并仍用 projectRoot
    static func workingTreeRoot(for directory: String) -> String {
        guard let result = Shell.run(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "rev-parse", "--show-toplevel"]
        ), result.status == 0 else {
            return URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
        }
        let topLevel = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: topLevel).resolvingSymlinksInPath().path
    }

    static func projectRoot(for directory: String) -> String {
        guard let result = Shell.run(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "rev-parse", "--git-common-dir"]
        ), result.status == 0 else {
            return directory
        }
        let commonDir = resolvePath(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            relativeTo: directory
        )
        let commonURL = URL(fileURLWithPath: commonDir)
        let root: String
        if commonURL.lastPathComponent == ".git" {
            root = commonURL.deletingLastPathComponent().path
        } else if commonDir.contains("/.git/modules/") {
            // submodule 的 common dir 在 superproject 的 .git 内，归属用工作目录
            root = workingTreeRoot(for: directory)
        } else {
            root = commonDir
        }
        // git 输出可能带 /private 前缀，归并前统一解析符号链接
        return URL(fileURLWithPath: root).resolvingSymlinksInPath().path
    }

    private static func resolvePath(_ path: String, relativeTo base: String) -> String {
        guard !path.hasPrefix("/") else {
            return path
        }
        let joined = base.hasSuffix("/") ? base + path : base + "/" + path
        return URL(fileURLWithPath: joined).standardizedFileURL.path
    }
}
