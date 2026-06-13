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
    static let metadataFileName = "settings-location.json"
    static let legacyMetadataFileName = "preset-location.json"

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

            let existingMetadataURL = existingMetadataFileURL() ?? metadataURL
            guard fileManager.fileExists(atPath: existingMetadataURL.path) else {
                return try initialStatus(
                    destinationURL: destinationURL,
                    metadataURL: metadataURL
                )
            }

            let metadata = try loadMetadata(at: existingMetadataURL)
            let sourceURL = sourceFileURL(
                directoryPath: metadata.lastActiveDirectoryPath,
                destinationURL: destinationURL
            )
            guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
                if existingMetadataURL != metadataURL {
                    try persistMetadata(
                        directoryURL: destinationURL.deletingLastPathComponent(),
                        at: metadataURL
                    )
                    try? fileManager.removeItem(at: existingMetadataURL)
                }
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

        let sourceDocument: SettingsDocument
        do {
            sourceDocument = try loadMigrationSource(at: migration.sourceURL)
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
        try writer.writeAtomically(
            try JSONEncoder().encode(sourceDocument),
            to: migration.destinationURL
        )

        let destinationDocument: SettingsDocument
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
        let currentMetadataURL = try metadataFileURL()
        if let legacyMetadataURL = legacyMetadataFileURL(),
           legacyMetadataURL != currentMetadataURL {
            try? fileManager.removeItem(at: legacyMetadataURL)
        }
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
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        let legacyAtDestination = PresetStore.legacyFileURL(
            directoryPath: destinationDirectory.path
        )
        if fileManager.fileExists(atPath: legacyAtDestination.path) {
            return migrationStatus(PresetMigration(
                sourceURL: legacyAtDestination,
                destinationURL: destinationURL
            ))
        }

        if let legacyConfiguredPath = environment[
            PresetStore.legacyConfiguredPathEnvironmentKey
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyConfiguredPath.isEmpty {
            let legacyConfiguredURL = PresetStore.legacyFileURL(
                directoryPath: legacyConfiguredPath
            )
            if legacyConfiguredURL.standardizedFileURL
                != destinationURL.standardizedFileURL,
               fileManager.fileExists(atPath: legacyConfiguredURL.path) {
                return migrationStatus(PresetMigration(
                    sourceURL: legacyConfiguredURL,
                    destinationURL: destinationURL
                ))
            }
        }

        let defaultURL = try defaultSettingsFileURL()
        if destinationURL.standardizedFileURL != defaultURL.standardizedFileURL,
           fileManager.fileExists(atPath: defaultURL.path) {
            return migrationStatus(PresetMigration(
                sourceURL: defaultURL,
                destinationURL: destinationURL
            ))
        }

        let defaultLegacyURL = PresetStore.legacyFileURL(
            directoryPath: defaultURL.deletingLastPathComponent().path
        )
        if destinationURL.standardizedFileURL != defaultLegacyURL.standardizedFileURL,
           fileManager.fileExists(atPath: defaultLegacyURL.path) {
            return migrationStatus(PresetMigration(
                sourceURL: defaultLegacyURL,
                destinationURL: destinationURL
            ))
        }

        try persistMetadata(
            directoryURL: destinationDirectory,
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
            _ = try loadMigrationSource(at: migration.sourceURL)
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

    private func defaultSettingsFileURL() throws -> URL {
        var values = environment.values
        values[PresetStore.configuredPathEnvironmentKey] = nil
        values[PresetStore.legacyConfiguredPathEnvironmentKey] = nil
        return try PresetStore.fileURL(environment: Environment(values: values))
    }

    private func sourceFileURL(
        directoryPath: String,
        destinationURL: URL
    ) -> URL {
        let expandedPath = NSString(string: directoryPath).expandingTildeInPath
        let directory = URL(fileURLWithPath: expandedPath, isDirectory: true)
        let settingsURL = directory.appendingPathComponent(
            "settings.json",
            isDirectory: false
        )
        let legacyURL = directory.appendingPathComponent(
            "presets.json",
            isDirectory: false
        )
        if fileManager.fileExists(atPath: settingsURL.path) {
            return settingsURL
        }
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        return settingsURL.standardizedFileURL == destinationURL.standardizedFileURL
            ? settingsURL
            : legacyURL
    }

    private func loadMigrationSource(at url: URL) throws -> SettingsDocument {
        if url.lastPathComponent == "presets.json" {
            do {
                let document = try JSONDecoder().decode(
                    PresetDocument.self,
                    from: Data(contentsOf: url)
                )
                guard document.version == PresetDocument.currentVersion else {
                    throw PresetStoreError.unsupportedVersion(document.version)
                }
                return SettingsDocument(presets: document.presets)
            } catch let error as PresetStoreError {
                throw error
            } catch {
                throw PresetStoreError.invalidFile
            }
        }
        return try PresetStore(
            fileURL: url,
            fileManager: fileManager,
            writer: writer
        ).load()
    }

    private func existingMetadataFileURL() -> URL? {
        if let current = try? metadataFileURL(),
           fileManager.fileExists(atPath: current.path) {
            return current
        }
        if let legacy = legacyMetadataFileURL(),
           fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }
        return nil
    }

    private func legacyMetadataFileURL() -> URL? {
        guard let workflowData = environment[PresetStore.workflowDataEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !workflowData.isEmpty else {
            return nil
        }
        return URL(
            fileURLWithPath: NSString(string: workflowData).expandingTildeInPath,
            isDirectory: true
        ).appendingPathComponent(Self.legacyMetadataFileName)
    }
}
