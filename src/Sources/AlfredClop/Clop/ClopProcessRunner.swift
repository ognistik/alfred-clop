import Foundation

struct ClopProcessResult: Equatable {
    var terminationStatus: Int32
    var standardOutput: Data
    var standardError: Data
}

protocol ClopProcessRunning {
    func run(_ command: ClopCommand) throws -> ClopProcessResult
}

struct FoundationClopProcessRunner: ClopProcessRunning {
    func run(_ command: ClopCommand) throws -> ClopProcessResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()
        process.waitUntilExit()
        try outputHandle.synchronize()
        try errorHandle.synchronize()

        return ClopProcessResult(
            terminationStatus: process.terminationStatus,
            standardOutput: try Data(contentsOf: outputURL),
            standardError: try Data(contentsOf: errorURL)
        )
    }
}
