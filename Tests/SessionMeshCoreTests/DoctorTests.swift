import Foundation
import Testing
@testable import SessionMeshCore

struct DoctorTests {
    // MARK: - Settings file

    @Test func settingsFileAcceptsValidJSON() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeSettings(#"{"hooks":{}}"#)

        let check = Doctor.checkSettingsFile(environment: fixture.environment)

        #expect(check.status == .pass)
    }

    @Test func settingsFileWarnsWhenMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let check = Doctor.checkSettingsFile(environment: fixture.environment)

        #expect(check.status == .warning)
    }

    @Test func settingsFileFailsOnInvalidJSON() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeSettings("{")

        let check = Doctor.checkSettingsFile(environment: fixture.environment)

        #expect(check.status == .failure)
    }

    @Test func settingsFileFailsWhenHooksIsNotAnObject() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeSettings(#"{"hooks":[]}"#)

        let check = Doctor.checkSettingsFile(environment: fixture.environment)

        #expect(check.status == .failure)
    }

    // MARK: - Settings permissions

    @Test func settingsPermissionsAcceptReadWrite() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeSettings("{}")

        let check = Doctor.checkSettingsPermissions(environment: fixture.environment)

        #expect(check.status == .pass)
    }

    @Test func settingsPermissionsFailWhenReadOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.writeSettings("{}")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: fixture.environment.settingsURL.path
        )

        let check = Doctor.checkSettingsPermissions(environment: fixture.environment)

        #expect(check.status == .failure)
    }

    @Test func settingsPermissionsWarnWhenMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let check = Doctor.checkSettingsPermissions(environment: fixture.environment)

        #expect(check.status == .warning)
    }

    // MARK: - Runtime directory

    @Test func runtimeDirectoryAccepts0700() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.makeRuntimeDirectory(mode: 0o700)

        let check = Doctor.checkRuntimeDirectory(environment: fixture.environment)

        #expect(check.status == .pass)
    }

    @Test func runtimeDirectoryWarnsOnLoosePermissions() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.makeRuntimeDirectory(mode: 0o755)

        let check = Doctor.checkRuntimeDirectory(environment: fixture.environment)

        #expect(check.status == .warning)
    }

    @Test func runtimeDirectoryAcceptsMissingRootWithWritableParent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.makeClaudeDirectory()

        let check = Doctor.checkRuntimeDirectory(environment: fixture.environment)

        #expect(check.status == .pass)
    }

    @Test func runtimeDirectoryFailsWhenParentIsMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let check = Doctor.checkRuntimeDirectory(environment: fixture.environment)

        #expect(check.status == .failure)
    }

    // MARK: - Fixture

    private struct Fixture {
        let home: URL
        let environment: Doctor.Environment

        init() throws {
            home = FileManager.default.temporaryDirectory
                .appendingPathComponent("session-mesh-doctor-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: home,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            environment = Doctor.Environment(
                homeDirectory: home,
                runtimeRoot: home.appendingPathComponent(".claude/session-mesh", isDirectory: true)
            )
        }

        var claudeDirectory: URL {
            home.appendingPathComponent(".claude", isDirectory: true)
        }

        func makeClaudeDirectory() throws {
            try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        }

        func writeSettings(_ text: String) throws {
            try makeClaudeDirectory()
            try text.write(to: environment.settingsURL, atomically: true, encoding: .utf8)
        }

        func makeRuntimeDirectory(mode: Int) throws {
            try FileManager.default.createDirectory(
                at: environment.runtimeRoot,
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: mode],
                ofItemAtPath: environment.runtimeRoot.path
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: home)
        }
    }
}
