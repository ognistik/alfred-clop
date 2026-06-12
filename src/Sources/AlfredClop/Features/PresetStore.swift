import Foundation

enum PresetStoreError: Error, Equatable {
    case missingWorkflowDataDirectory
    case unsupportedVersion(Int)
    case invalidFile
}

protocol AtomicDataWriting {
    func writeAtomically(_ data: Data, to url: URL) throws
}

struct FoundationAtomicDataWriter: AtomicDataWriting {
    func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

struct PresetStore {
    static let workflowDataEnvironmentKey = "alfred_workflow_data"
    static let configuredPathEnvironmentKey = "presetsPath"

    var fileURL: URL
    var fileManager: FileManager
    var writer: any AtomicDataWriting

    init(
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) throws {
        self.fileURL = try Self.fileURL(environment: environment)
        self.fileManager = fileManager
        self.writer = writer
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.writer = writer
    }

    static func fileURL(environment: Environment) throws -> URL {
        let configuredPath = environment[configuredPathEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let directoryPath: String

        if let configuredPath, !configuredPath.isEmpty {
            directoryPath = configuredPath
        } else if let workflowData = environment[workflowDataEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !workflowData.isEmpty {
            directoryPath = workflowData
        } else {
            throw PresetStoreError.missingWorkflowDataDirectory
        }

        let expandedPath = NSString(string: directoryPath).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
            .appendingPathComponent("presets.json", isDirectory: false)
    }

    func load() throws -> PresetDocument {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PresetDocument()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(PresetDocument.self, from: data)
            guard document.version == PresetDocument.currentVersion else {
                throw PresetStoreError.unsupportedVersion(document.version)
            }
            return PresetDocument(
                presets: uniquePresets(document.presets)
            )
        } catch let error as PresetStoreError {
            throw error
        } catch {
            throw PresetStoreError.invalidFile
        }
    }

    @discardableResult
    func save(_ preset: ActionPreset) throws -> Bool {
        var document = try load()
        guard !document.presets.contains(preset) else {
            return false
        }
        document.presets.append(preset)
        try persist(document)
        return true
    }

    @discardableResult
    func remove(_ preset: ActionPreset) throws -> Bool {
        var document = try load()
        let previousCount = document.presets.count
        document.presets.removeAll { $0 == preset }
        guard document.presets.count != previousCount else {
            return false
        }
        try persist(document)
        return true
    }

    private func persist(_ document: PresetDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(document)
        try writer.writeAtomically(data, to: fileURL)
    }

    private func uniquePresets(_ presets: [ActionPreset]) -> [ActionPreset] {
        var seen = Set<ActionPreset>()
        return presets.filter { seen.insert($0).inserted }
    }
}
