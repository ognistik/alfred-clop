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
    func configuredSettingsAreAuthoritativeWhenBothFilesExist() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(at: fixture.defaultSettingsFile, value: "w128")
        try fixture.writeSettings(at: fixture.customSettingsFile, value: "h720")
        let source = try Data(contentsOf: fixture.defaultSettingsFile)

        guard case .authoritative(let document) =
            PresetMigrationCoordinator(environment: fixture.environment).resolution()
        else {
            Issue.record("Expected authoritative configured settings")
            return
        }
        #expect(document.presets == [
            .crop(CropActionPreset(
                size: try #require(CropSizeParser.parse("h720"))
            ))
        ])
        #expect(try Data(contentsOf: fixture.defaultSettingsFile) == source)
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
    func pendingLocationHidesPresetsAndBlocksInlineMutation() throws {
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
        #expect(menu.items.first?.title == "Presets are in the previous location")
        #expect(menu.items.first?.subtitle == "Press Return to move settings here")
        #expect(!menu.items.contains { $0.title == "1920" })
        let typed = try #require(menu.items.first { $0.title == "Width 128, auto height" })
        let saveState = try #require(
            typed.mods?.control?
                .variables?[ActionMenu.menuStateVariable]
        )
        let pending = CropParameterMenu.response(
            stateJSON: saveState,
            query: "",
            environment: fixture.environment
        )

        #expect(pending.items.first?.title == "Resolve the settings location first")
        #expect(!FileManager.default.fileExists(
            atPath: fixture.customSettingsFile.path
        ))
    }

    @Test
    func malformedConfiguredSettingsDoNotFallBack() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(
            at: fixture.defaultSettingsFile,
            value: "w128",
            outputTemplate: "%P/%f-previous"
        )
        try FileManager.default.createDirectory(
            at: fixture.customDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.customSettingsFile)

        #expect(
            PresetMigrationCoordinator(environment: fixture.environment)
                .resolution() == .failure(.invalidFile)
        )
        #expect(throws: PresetStoreError.invalidFile) {
            try fixture.environment.resolvedExecutionOptions()
        }
    }

    @Test
    func configurationOffersMoveAndStartFreshWhileWritesAreBlocked() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(
            at: fixture.defaultSettingsFile,
            value: "w128",
            outputTemplate: "%P/%f-previous"
        )
        let menu = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(),
                prettyPrinted: false
            ),
            query: "",
            environment: fixture.environment
        )

        #expect(menu.items.prefix(2).map(\.title) == [
            "Move existing settings",
            "Start with new settings"
        ])
        #expect(!menu.items.contains { $0.title == "Remove all action presets" })
        #expect(!menu.items.contains { $0.title == "Reset output template" })

        let blocked = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(
                    mode: .configurationSaveOutput,
                    value: "%P/%f-new"
                ),
                prettyPrinted: false
            ),
            query: "",
            environment: fixture.environment
        )
        #expect(blocked.items.first?.title == "Resolve the settings location first")
        #expect(!FileManager.default.fileExists(
            atPath: fixture.customSettingsFile.path
        ))
    }

    @Test
    func startFreshCreatesDefaultsWithoutDeletingPreviousSettings() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(
            at: fixture.defaultSettingsFile,
            value: "w128",
            outputTemplate: "%P/%f-previous"
        )

        try PresetMigrationCoordinator(environment: fixture.environment)
            .startFresh()

        #expect(FileManager.default.fileExists(
            atPath: fixture.defaultSettingsFile.path
        ))
        #expect(try PresetStore(fileURL: fixture.customSettingsFile).load()
            == SettingsDocument())
        guard case .authoritative =
            PresetMigrationCoordinator(environment: fixture.environment).resolution()
        else {
            Issue.record("Expected configured settings to become authoritative")
            return
        }
    }

    @Test
    func moveStopsFallbackAndDeletesPreviousSettings() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeSettings(
            at: fixture.defaultSettingsFile,
            value: "w128",
            outputTemplate: "%P/%f-previous"
        )
        let coordinator = PresetMigrationCoordinator(environment: fixture.environment)
        let migration = try #require(availableMigration(coordinator.status()))

        try coordinator.move(migration)

        #expect(!FileManager.default.fileExists(
            atPath: fixture.defaultSettingsFile.path
        ))
        #expect(try fixture.environment.resolvedExecutionOptions().output
            == .inPlace)
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

    func writeSettings(
        at url: URL,
        value: String = "w128",
        outputTemplate: String = SettingsDocument.builtInOutputTemplate
    ) throws {
        try PresetStore(fileURL: url).persist(SettingsDocument(
            presets: [
                .crop(CropActionPreset(
                    size: try #require(CropSizeParser.parse(value))
                ))
            ],
            outputTemplate: outputTemplate
        ))
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
