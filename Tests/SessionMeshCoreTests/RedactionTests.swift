import Foundation
import Testing
@testable import SessionMeshCore

struct RedactionTests {
    @Test func truncateKeepsShortText() {
        #expect(Redaction.truncate("hi", to: 60) == "hi")
    }

    @Test func truncateCapsAtGraphemeBoundary() {
        let text = String(repeating: "a", count: 10) + "👨‍👩‍👧‍👦"

        let truncated = Redaction.truncate(text, to: 10)

        #expect(truncated.count == 10)
        #expect(truncated == String(repeating: "a", count: 10))
    }

    @Test func stripControlCharactersRemovesControls() {
        let text = "a\nb\tc\u{7}d中e👨‍👩‍👧‍👦"

        #expect(Redaction.stripControlCharacters(text) == "abcd中e👨‍👩‍👧‍👦")
    }

    @Test func escapeEscapesQuotesAndBackslashes() {
        #expect(Redaction.escape("a\"b\\c") == "a\\\"b\\\\c")
    }

    @Test func sanitizeCapsAndStripsAndEscapes() {
        let text = String(repeating: "x", count: 70) + "\n"

        let sanitized = Redaction.sanitize(text)

        #expect(sanitized.count == 60)
        #expect(!sanitized.contains("\n"))
    }

    @Test func sanitizePathStripsAndEscapesWithoutTruncating() {
        let path = String(repeating: "p", count: 80) + "/sub\"dir\\x\n"

        let sanitized = Redaction.sanitizePath(path)

        #expect(sanitized.count > 60)
        #expect(!sanitized.contains("\n"))
        #expect(sanitized.contains("\\\""))
        #expect(sanitized.contains("\\\\"))
    }

    @Test func atomicWriteCreatesFileWithSecurePermissions() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sub/roster.json")

        try AtomicFile.write(Data("hello".utf8), to: file)

        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: file, encoding: .utf8) == "hello")
        #expect(permissions(of: file) == 0o600)
        #expect(permissions(of: file.deletingLastPathComponent()) == 0o700)
    }

    @Test func atomicWriteOverwritesExistingContent() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("state.json")
        try AtomicFile.write(Data("first".utf8), to: file)
        try AtomicFile.write(Data("second".utf8), to: file)

        #expect(try String(contentsOf: file, encoding: .utf8) == "second")
        #expect(permissions(of: file) == 0o600)
    }

    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-mesh-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func permissions(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
