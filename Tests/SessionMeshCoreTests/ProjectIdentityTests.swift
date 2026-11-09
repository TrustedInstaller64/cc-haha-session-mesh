import Foundation
import Testing
@testable import SessionMeshCore

struct ProjectIdentityTests {
    @Test func projectIdentityGroupsWorktrees() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(atPath: fixture.main, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: fixture.main)
        try writeCommit(in: fixture.main)
        try runGit(["worktree", "add", fixture.worktree], in: fixture.main)

        #expect(ProjectIdentity.projectRoot(for: fixture.worktree) == canonical(fixture.main))
        #expect(ProjectIdentity.projectRoot(for: fixture.main) == canonical(fixture.main))
        let worktreeSubdirectory = fixture.worktree + "/src"
        try FileManager.default.createDirectory(atPath: worktreeSubdirectory, withIntermediateDirectories: true)
        #expect(ProjectIdentity.projectRoot(for: worktreeSubdirectory) == canonical(fixture.main))
    }

    @Test func workingTreeRootUsesLinkedWorktreeRoot() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(atPath: fixture.main, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: fixture.main)
        try writeCommit(in: fixture.main)
        try runGit(["worktree", "add", fixture.worktree], in: fixture.main)
        try FileManager.default.createDirectory(atPath: fixture.plain, withIntermediateDirectories: true)

        #expect(ProjectIdentity.workingTreeRoot(for: fixture.worktree) == canonical(fixture.worktree))
        #expect(ProjectIdentity.workingTreeRoot(for: fixture.main) == canonical(fixture.main))
        #expect(ProjectIdentity.workingTreeRoot(for: fixture.plain) == canonical(fixture.plain))
    }

    @Test func projectRootReturnsRepositoryDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(atPath: fixture.main, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: fixture.main)
        let subdirectory = fixture.main + "/src"
        try FileManager.default.createDirectory(atPath: subdirectory, withIntermediateDirectories: true)

        #expect(ProjectIdentity.projectRoot(for: fixture.main) == canonical(fixture.main))
        #expect(ProjectIdentity.projectRoot(for: subdirectory) == canonical(fixture.main))
    }

    @Test func projectRootUsesSubmoduleWorkingTree() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let subSource = fixture.root.appendingPathComponent("subsource").path
        try FileManager.default.createDirectory(atPath: subSource, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: subSource)
        try writeCommit(in: subSource)
        try FileManager.default.createDirectory(atPath: fixture.main, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: fixture.main)
        try writeCommit(in: fixture.main)
        try runGit(
            ["-c", "protocol.file.allow=always", "submodule", "add", "-q", subSource, "modules/sub"],
            in: fixture.main
        )
        try runGit(["commit", "-qm", "add submodule"], in: fixture.main)
        let submodule = fixture.main + "/modules/sub"

        #expect(ProjectIdentity.projectRoot(for: submodule) == canonical(submodule))
        #expect(ProjectIdentity.workingTreeRoot(for: submodule) == canonical(submodule))
    }

    @Test func projectRootUsesExactPathOutsideGit() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(atPath: fixture.plain, withIntermediateDirectories: true)

        #expect(ProjectIdentity.projectRoot(for: fixture.plain) == fixture.plain)
    }

    @Test func projectRootReturnsBareRepositoryPath() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try runGit(["init", "--bare", "-q", fixture.bare], in: fixture.root.path)

        #expect(ProjectIdentity.projectRoot(for: fixture.bare) == canonical(fixture.bare))
    }

    @Test func projectRootUsesExactPathForNonexistentDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let missing = fixture.root.appendingPathComponent("missing").path

        #expect(ProjectIdentity.projectRoot(for: missing) == missing)
    }

    // MARK: - Fixture

    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func runGit(_ arguments: [String], in directory: String) throws {
        let result = try #require(Shell.run(
            executable: "/usr/bin/git",
            arguments: ["-C", directory] + arguments
        ))
        #expect(result.status == 0)
    }

    private func writeCommit(in directory: String) throws {
        let readme = URL(fileURLWithPath: directory).appendingPathComponent("README.md")
        try Data("init".utf8).write(to: readme)
        try runGit(["add", "."], in: directory)
        try runGit(
            ["-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-m", "init"],
            in: directory
        )
    }

    private struct Fixture {
        let root: URL
        let main: String
        let worktree: String
        let plain: String
        let bare: String

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("session-mesh-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            main = root.appendingPathComponent("main").path
            worktree = root.appendingPathComponent("linked").path
            plain = root.appendingPathComponent("plain").path
            bare = root.appendingPathComponent("bare").path
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
