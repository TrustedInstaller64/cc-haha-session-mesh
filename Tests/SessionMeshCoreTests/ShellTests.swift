import Foundation
import Testing
@testable import SessionMeshCore

struct ShellTests {
    @Test func shellDrainsLargeStderrWithoutDeadlock() throws {
        let result = try #require(
            Shell.run(
                executable: "/bin/sh",
                arguments: ["-c", "yes x | head -c 524288 >&2"]
            )
        )

        #expect(result.status == 0)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.utf8.count == 524288)
    }
}
