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
    static let configuredPathEnvironmentKey = "settingsPath"
    static let legacyConfiguredPathEnvironmentKey = "presetsPath"

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
        URL(
            fileURLWithPath: try configuredDirectoryPath(environment: environment),
            isDirectory: true
        )
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    static func configuredDirectoryPath(environment: Environment) throws -> String {
        let settingsPath = environment[configuredPathEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let settingsPath, !settingsPath.isEmpty {
            return NSString(string: settingsPath).expandingTildeInPath
        }
        let legacyPath = environment[legacyConfiguredPathEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let legacyPath, !legacyPath.isEmpty {
            return NSString(string: legacyPath).expandingTildeInPath
        }
        guard let workflowData = environment[workflowDataEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !workflowData.isEmpty else {
            throw PresetStoreError.missingWorkflowDataDirectory
        }
        return NSString(string: workflowData).expandingTildeInPath
    }

    static func legacyFileURL(directoryPath: String) -> URL {
        URL(
            fileURLWithPath: NSString(string: directoryPath).expandingTildeInPath,
            isDirectory: true
        ).appendingPathComponent("presets.json", isDirectory: false)
    }

    func load() throws -> SettingsDocument {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return SettingsDocument()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(SettingsDocument.self, from: data)
            guard document.version == SettingsDocument.currentVersion else {
                throw PresetStoreError.unsupportedVersion(document.version)
            }
            guard OutputTemplateValidator.validate(document.outputTemplate) == nil else {
                throw PresetStoreError.invalidFile
            }
            return SettingsDocument(
                presets: uniquePresets(document.presets),
                outputTemplate: document.outputTemplate
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

    func updateOutputTemplate(_ template: String) throws {
        if let error = OutputTemplateValidator.validate(template) {
            throw error
        }
        var document = try load()
        document.outputTemplate = template
        try persist(document)
    }

    @discardableResult
    func removeAllPresets() throws -> Int {
        var document = try load()
        let count = document.presets.count
        guard count > 0 else {
            return 0
        }
        document.presets = []
        try persist(document)
        return count
    }

    func persist(_ document: SettingsDocument) throws {
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
