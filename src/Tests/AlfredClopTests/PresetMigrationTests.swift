import Foundation
import Testing
@testable import AlfredClop

struct PresetMigrationTests {
    @Test
    func legacyPresetFileRequiresExplicitMigrationToSettings() throws {
        let fixture = try MigrationFixture(configured: false)
        try fixture.writeLegacyPreset(at: fixture.defaultLegacyFile)

        let migration = try #require(availableMigration(fixture.status()))

        #expect(migration.sourceURL == fixture.defaultLegacyFile)
        #expect(migration.destinationURL == fixture.defaultSettingsFile)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.defaultSettingsFile.path
        ))
    }

    @Test
    func legacyPresetsMoveWithoutDataLossAndGainBuiltInTemplate() throws {
        let fixture = try MigrationFixture(configured: false)
        try fixture.writeLegacyPreset(at: fixture.defaultLegacyFile, value: "w128")
        let migration = try #require(availableMigration(fixture.status()))

        try PresetMigrationCoordinator(environment: fixture.environment)
            .move(migration)

        let document = try PresetStore(
            fileURL: fixture.defaultSettingsFile
        ).load()
        #expect(document.presets.count == 1)
        #expect(document.outputTemplate == "%P/%f-clop")
        #expect(!FileManager.default.fileExists(
            atPath: fixture.defaultLegacyFile.path
        ))
    }

    @Test
    func legacyPresetsPathRemainsRecognizedDuringTransition() throws {
        let fixture = try MigrationFixture(configured: false)
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: fixture.defaultDirectory.path,
            PresetStore.legacyConfiguredPathEnvironmentKey:
                fixture.customDirectory.path
        ])

        #expect(
            try PresetStore.fileURL(environment: environment)
                == fixture.customSettingsFile
        )
    }

    @Test
    func newSettingsPathFindsLegacyPresetsPathInDifferentFolder() throws {
        let fixture = try MigrationFixture(configured: true)
        let oldDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("Old Synced Presets", isDirectory: true)
        let oldFile = oldDirectory.appendingPathComponent("presets.json")
        try fixture.writeLegacyPreset(at: oldFile)
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: fixture.defaultDirectory.path,
            PresetStore.configuredPathEnvironmentKey:
                fixture.customDirectory.path,
            PresetStore.legacyConfiguredPathEnvironmentKey: oldDirectory.path
        ])

        let migration = try #require(availableMigration(
            PresetMigrationCoordinator(environment: environment).status()
        ))

        #expect(migration.sourceURL == oldFile)
        #expect(migration.destinationURL == fixture.customSettingsFile)
    }

    @Test
    func changedSettingsPathRequiresExplicitMove() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(at: fixture.defaultSettingsFile)
        let migration = try #require(availableMigration(fixture.status()))

        #expect(migration.sourceURL == fixture.defaultSettingsFile)
        #expect(migration.destinationURL == fixture.customSettingsFile)

        try PresetMigrationCoordinator(environment: fixture.environment)
            .move(migration)

        #expect(!FileManager.default.fileExists(
            atPath: fixture.defaultSettingsFile.path
        ))
        #expect(try PresetStore(
            fileURL: fixture.customSettingsFile
        ).load().presets.count == 1)
    }

    @Test
    func configurationOwnsPendingMigrationAndMovesDirectly() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(at: fixture.defaultSettingsFile)
        let configuration = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(),
                prettyPrinted: false
            ),
            query: "",
            environment: fixture.environment
        )
        let move = try #require(configuration.items.first {
            $0.title == "Move existing settings"
        })

        #expect(move.valid)
        #expect(try JSONDecoder().decode(
            MenuState.self,
            from: Data(try #require(move.arg).utf8)
        ).mode == .presetMigration)

        _ = PresetMigrationMenu.response(
            stateJSON: try #require(move.arg),
            environment: fixture.environment
        )

        #expect(FileManager.default.fileExists(
            atPath: fixture.customSettingsFile.path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.defaultSettingsFile.path
        ))
    }

    @Test
    func bothSettingsFilesProduceConflictWithoutChanges() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(at: fixture.defaultSettingsFile, value: "w128")
        try fixture.writeSettings(at: fixture.customSettingsFile, value: "h720")
        let source = try Data(contentsOf: fixture.defaultSettingsFile)
        let destination = try Data(contentsOf: fixture.customSettingsFile)

        #expect({
            guard case .conflict = fixture.status() else { return false }
            return true
        }())
        #expect(try Data(contentsOf: fixture.defaultSettingsFile) == source)
        #expect(try Data(contentsOf: fixture.customSettingsFile) == destination)
    }

    @Test
    func destinationValidationFailureKeepsSource() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(at: fixture.defaultSettingsFile)
        let coordinator = PresetMigrationCoordinator(
            environment: fixture.environment,
            writer: MigrationWriter(corruptSettings: true)
        )
        let migration = try #require(availableMigration(coordinator.status()))

        #expect(throws: PresetMigrationError.destinationValidationFailed) {
            try coordinator.move(migration)
        }
        #expect(FileManager.default.fileExists(
            atPath: fixture.defaultSettingsFile.path
        ))
    }

    @Test
    func inlinePresetSaveMovesThenResumes() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(at: fixture.defaultSettingsFile, value: "1920")
        let request = ParameterStepRequest(
            action: .crop,
            inputs: ["/tmp/First Image.png"],
            inputContext: .selected
        )
        let menu = CropParameterMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.crop(request),
                prettyPrinted: false
            ),
            query: "w128",
            environment: fixture.environment
        )
        let saveState = try #require(
            menu.items.first?.mods?.control?
                .variables?[ActionMenu.menuStateVariable]
        )
        let pending = CropParameterMenu.response(
            stateJSON: saveState,
            query: "",
            environment: fixture.environment
        )

        #expect(pending.items.first?.title == "Move existing settings")

        _ = PresetMigrationMenu.response(
            stateJSON: try #require(pending.items.first?.arg),
            environment: fixture.environment
        )

        #expect(try PresetStore(
            fileURL: fixture.customSettingsFile
        ).load().presets.count == 2)
    }

    @Test
    func metadataIsVersionedInWorkflowData() throws {
        let fixture = try MigrationFixture(configured: false)

        #expect(fixture.status() == .none)
        let metadata = try JSONDecoder().decode(
            PresetLocationMetadata.self,
            from: Data(contentsOf: fixture.metadataFile)
        )
        #expect(metadata.version == PresetLocationMetadata.currentVersion)
        #expect(metadata.lastActiveDirectoryPath == fixture.defaultDirectory.path)
    }

    private func availableMigration(
        _ status: PresetMigrationStatus
    ) -> PresetMigration? {
        guard case let .available(migration) = status else {
            return nil
        }
        return migration
    }
}

private struct MigrationFixture {
    let defaultDirectory: URL
    let customDirectory: URL
    let defaultSettingsFile: URL
    let defaultLegacyFile: URL
    let customSettingsFile: URL
    let metadataFile: URL
    let environment: Environment

    init(configured: Bool) throws {
        let root = try makeTemporaryDirectory()
            .appendingPathComponent("Migration Root With Spaces")
        defaultDirectory = root.appendingPathComponent(
            "Workflow Data With Spaces",
            isDirectory: true
        )
        customDirectory = root.appendingPathComponent(
            "Synced Settings With Spaces",
            isDirectory: true
        )
        defaultSettingsFile = defaultDirectory
            .appendingPathComponent("settings.json")
        defaultLegacyFile = defaultDirectory
            .appendingPathComponent("presets.json")
        customSettingsFile = customDirectory
            .appendingPathComponent("settings.json")
        metadataFile = defaultDirectory.appendingPathComponent(
            PresetMigrationCoordinator.metadataFileName
        )
        environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: defaultDirectory.path,
            PresetStore.configuredPathEnvironmentKey:
                configured ? customDirectory.path : ""
        ])
    }

    func status() -> PresetMigrationStatus {
        PresetMigrationCoordinator(environment: environment).status()
    }

    func writeLegacyPreset(at url: URL, value: String = "w128") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let preset = ActionPreset.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse(value))
        ))
        try JSONEncoder().encode(PresetDocument(
            presets: [preset]
        )).write(to: url, options: .atomic)
    }

    func writeSettings(at url: URL, value: String = "w128") throws {
        let store = PresetStore(fileURL: url)
        _ = try store.save(.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse(value))
        )))
    }
}

private final class MigrationWriter: AtomicDataWriting {
    var corruptSettings: Bool

    init(corruptSettings: Bool) {
        self.corruptSettings = corruptSettings
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if corruptSettings, url.lastPathComponent == "settings.json" {
            try Data("not-json".utf8).write(to: url, options: .atomic)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }
}
