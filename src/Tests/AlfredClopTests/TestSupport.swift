import Foundation
@testable import AlfredClop

func makeExecutionOptions(
    output: OutputBehavior = .inPlace,
    backup: BackupBehavior = .trustClop
) -> ExecutionOptions {
    ExecutionOptions(
        showClopUI: true,
        copyResult: false,
        output: output,
        backup: backup,
        adaptiveOptimisation: nil,
        pdfDPI: nil
    )
}

func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

func temporaryFile(named name: String) throws -> URL {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent(name)
    try Data().write(to: file)
    return file
}
