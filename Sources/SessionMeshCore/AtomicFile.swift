import Foundation

enum AtomicFile {
    static func write(
        _ data: Data,
        to url: URL,
        filePermissions: NSNumber = 0o600,
        directoryPermissions: NSNumber = 0o700
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        let temporary = directory.appendingPathComponent(
            ".\(url.lastPathComponent).tmp-\(ProcessInfo.processInfo.globallyUniqueString)"
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: filePermissions],
            ofItemAtPath: temporary.path
        )
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
