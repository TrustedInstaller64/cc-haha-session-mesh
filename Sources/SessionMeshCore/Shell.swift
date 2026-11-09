import Foundation

enum Shell {
    struct RunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(
        executable: String,
        arguments: [String],
        in directory: String? = nil
    ) -> RunResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        // 两条管道必须同时排空；顺序读取会在另一条管道写满时死锁
        let group = DispatchGroup()
        let stdoutBox = OutputBox()
        let stderrBox = OutputBox()
        drain(stdoutPipe, into: stdoutBox, group: group)
        drain(stderrPipe, into: stderrBox, group: group)
        process.waitUntilExit()
        group.wait()
        return RunResult(
            status: process.terminationStatus,
            stdout: String(data: stdoutBox.value, encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.value, encoding: .utf8) ?? ""
        )
    }

    private static func drain(_ pipe: Pipe, into box: OutputBox, group: DispatchGroup) {
        group.enter()
        // 独立线程不受 Swift 并发协作池限制；调用方可能正阻塞等待本结果
        let thread = Thread {
            box.value = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        thread.name = "session-mesh-shell-drain"
        thread.start()
    }

    private final class OutputBox {
        private let lock = NSLock()
        private var storage = Data()

        var value: Data {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock()
                storage = newValue
                lock.unlock()
            }
        }
    }
}
