import Foundation

enum PresetMigrationError: Error, Equatable {
    case missingWorkflowDataDirectory
    case invalidMetadata
    case unsupportedMetadataVersion(Int)
    case sourceMissing
    case sourceInvalid
    case sourceUnsupportedVersion(Int)
    case destinationConflict
    case destinationValidationFailed
    case locationChanged
}

struct PresetMigration: Equatable {
    var sourceURL: URL
    var destinationURL: URL
}

enum PresetMigrationStatus: Equatable {
    case none
    case available(PresetMigration)
    case conflict(PresetMigration)
    case sourceMissing(PresetMigration)
    case sourceInvalid(PresetMigration, PresetMigrationError)
    case metadataInvalid(PresetMigrationError)
}

struct PresetMigrationCoordinator {
    static let metadataFileName = "preset-location.json"

    var environment: Environment
    var fileManager: FileManager
    var writer: any AtomicDataWriting

    init(
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.writer = writer
    }

    func status() -> PresetMigrationStatus {
        do {
            let destinationURL = try PresetStore.fileURL(environment: environment)
            let metadataURL = try metadataFileURL()

            guard fileManager.fileExists(atPath: metadataURL.path) else {
                return try initialStatus(
                    destinationURL: destinationURL,
                    metadataURL: metadataURL
                )
            }

            let metadata = try loadMetadata(at: metadataURL)
            let sourceURL = presetFileURL(
                directoryPath: metadata.lastActiveDirectoryPath
            )
            guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
                return .none
            }

            return migrationStatus(
                PresetMigration(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL
                )
            )
        } catch PresetMigrationError.missingWorkflowDataDirectory {
            return .none
        } catch PresetStoreError.missingWorkflowDataDirectory {
            return .none
        } catch let error as PresetMigrationError {
            return .metadataInvalid(error)
        } catch {
            return .metadataInvalid(.invalidMetadata)
        }
    }

    func move(_ migration: PresetMigration) throws {
        guard case let .available(currentMigration) = status(),
              currentMigration == migration else {
            throw PresetMigrationError.locationChanged
        }

        let sourceStore = PresetStore(
            fileURL: migration.sourceURL,
            fileManager: fileManager,
            writer: writer
        )
        let sourceDocument: PresetDocument
        do {
            sourceDocument = try sourceStore.load()
        } catch PresetStoreError.unsupportedVersion(let version) {
            throw PresetMigrationError.sourceUnsupportedVersion(version)
        } catch {
            throw PresetMigrationError.sourceInvalid
        }

        guard !fileManager.fileExists(atPath: migration.destinationURL.path) else {
            throw PresetMigrationError.destinationConflict
        }

        let destinationDirectory = migration.destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let sourceData = try Data(contentsOf: migration.sourceURL)
        try writer.writeAtomically(sourceData, to: migration.destinationURL)

        let destinationDocument: PresetDocument
        do {
            destinationDocument = try PresetStore(
                fileURL: migration.destinationURL,
                fileManager: fileManager,
                writer: writer
            ).load()
        } catch {
            throw PresetMigrationError.destinationValidationFailed
        }
        guard destinationDocument == sourceDocument else {
            throw PresetMigrationError.destinationValidationFailed
        }

        try fileManager.removeItem(at: migration.sourceURL)
        try persistMetadata(
            directoryURL: destinationDirectory,
            at: metadataFileURL()
        )
    }

    func metadataFileURL() throws -> URL {
        guard let workflowData = environment[PresetStore.workflowDataEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !workflowData.isEmpty else {
            throw PresetMigrationError.missingWorkflowDataDirectory
        }
        let expandedPath = NSString(string: workflowData).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
            .appendingPathComponent(Self.metadataFileName, isDirectory: false)
    }

    private func initialStatus(
        destinationURL: URL,
        metadataURL: URL
    ) throws -> PresetMigrationStatus {
        let defaultURL = try defaultPresetFileURL()
        if destinationURL.standardizedFileURL != defaultURL.standardizedFileURL,
           fileManager.fileExists(atPath: defaultURL.path) {
            return migrationStatus(PresetMigration(
                sourceURL: defaultURL,
                destinationURL: destinationURL
            ))
        }

        try persistMetadata(
            directoryURL: destinationURL.deletingLastPathComponent(),
            at: metadataURL
        )
        return .none
    }

    private func migrationStatus(
        _ migration: PresetMigration
    ) -> PresetMigrationStatus {
        let sourceExists = fileManager.fileExists(atPath: migration.sourceURL.path)
        let destinationExists = fileManager.fileExists(
            atPath: migration.destinationURL.path
        )

        if sourceExists && destinationExists {
            return .conflict(migration)
        }
        guard sourceExists else {
            return .sourceMissing(migration)
        }

        do {
            _ = try PresetStore(
                fileURL: migration.sourceURL,
                fileManager: fileManager,
                writer: writer
            ).load()
            return .available(migration)
        } catch PresetStoreError.unsupportedVersion(let version) {
            return .sourceInvalid(
                migration,
                .sourceUnsupportedVersion(version)
            )
        } catch {
            return .sourceInvalid(migration, .sourceInvalid)
        }
    }

    private func loadMetadata(at url: URL) throws -> PresetLocationMetadata {
        let metadata: PresetLocationMetadata
        do {
            metadata = try JSONDecoder().decode(
                PresetLocationMetadata.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw PresetMigrationError.invalidMetadata
        }
        guard metadata.version == PresetLocationMetadata.currentVersion else {
            throw PresetMigrationError.unsupportedMetadataVersion(
                metadata.version
            )
        }
        guard !metadata.lastActiveDirectoryPath
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PresetMigrationError.invalidMetadata
        }
        return metadata
    }

    private func persistMetadata(directoryURL: URL, at url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let metadata = PresetLocationMetadata(
            lastActiveDirectoryPath: directoryURL.standardizedFileURL.path
        )
        try writer.writeAtomically(
            try JSONEncoder().encode(metadata),
            to: url
        )
    }

    private func defaultPresetFileURL() throws -> URL {
        var values = environment.values
        values[PresetStore.configuredPathEnvironmentKey] = nil
        return try PresetStore.fileURL(environment: Environment(values: values))
    }

    private func presetFileURL(directoryPath: String) -> URL {
        let expandedPath = NSString(string: directoryPath).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
            .appendingPathComponent("presets.json", isDirectory: false)
    }
}
