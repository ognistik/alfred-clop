import Foundation
import Testing
@testable import AlfredClop

struct PresetMigrationTests {
    @Test
    func detectsChangedDefaultToCustomLocationWithSpaces() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile)

        let migration = try #require(availableMigration(fixture.status()))

        #expect(migration.sourceURL == fixture.defaultFile)
        #expect(migration.destinationURL == fixture.customFile)
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))
    }

    @Test
    func movesDefaultToCustomOnlyAfterExplicitConfirmation() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile)
        let menu = fixture.actionMenu(context: .clipboard)
        let moveItem = try #require(menu.items.first {
            $0.title == "Move existing settings"
        })
        let confirmationState = try #require(moveItem.arg)

        #expect(FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))

        let confirmation = PresetMigrationMenu.response(
            stateJSON: confirmationState,
            environment: fixture.environment
        )
        let moveState = try #require(confirmation.items.first?.arg)

        #expect(confirmation.items.first?.title == "Move existing settings?")
        #expect(confirmation.items.first?.subtitle.contains(fixture.defaultFile.path) == false)
        #expect(confirmation.items.first?.subtitle.contains(fixture.customFile.path) == false)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))

        let returnedMenu = PresetMigrationMenu.response(
            stateJSON: moveState,
            environment: fixture.environment
        )

        #expect(!FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        #expect(try PresetStore(fileURL: fixture.customFile).load().presets.count == 1)
        #expect(!returnedMenu.items.contains {
            $0.title == "Move existing settings"
        })
        #expect(returnedMenu.items.first?.subtitle.hasPrefix("Copied input:") == true)
        #expect(
            returnedMenu.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.clipboard.rawValue
        )
        let inputJSON = try #require(
            returnedMenu.variables?[ActionMenu.inputJSONVariable]
        )
        #expect(
            try JSONDecoder().decode(
                MenuInput.self,
                from: Data(inputJSON.utf8)
            ).paths == fixture.inputs
        )
    }

    @Test
    func emptyClipboardStillOffersPendingSettingsMove() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile)

        let menu = ActionMenu.response(
            clipboard: EmptyMigrationClipboard(),
            query: "",
            environment: fixture.environment
        )
        let moveItem = try #require(menu.items.first)

        #expect(menu.items.map(\.title) == [
            "Move existing settings",
            "No supported files in clipboard"
        ])
        #expect(moveItem.valid)

        let confirmation = PresetMigrationMenu.response(
            stateJSON: try #require(moveItem.arg),
            environment: fixture.environment
        )
        let returnedMenu = PresetMigrationMenu.response(
            stateJSON: try #require(confirmation.items.first?.arg),
            environment: fixture.environment
        )

        #expect(returnedMenu.items.map(\.title) == [
            "No supported files in clipboard"
        ])
        #expect(try PresetStore(fileURL: fixture.customFile).load().presets.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.defaultFile.path))
    }

    @Test
    func movesCustomBackToDefaultWhenConfigurationIsCleared() throws {
        let fixture = try MigrationFixture(configured: true)
        _ = fixture.status()
        try fixture.savePreset(at: fixture.customFile)
        let defaultEnvironment = fixture.environment(configured: false)
        let coordinator = PresetMigrationCoordinator(
            environment: defaultEnvironment
        )
        let migration = try #require(availableMigration(coordinator.status()))

        #expect(migration.sourceURL == fixture.customFile)
        #expect(migration.destinationURL == fixture.defaultFile)

        try coordinator.move(migration)

        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))
        #expect(try PresetStore(fileURL: fixture.defaultFile).load().presets.count == 1)
    }

    @Test
    func pendingMoveCanResumeAndCompletePresetSave() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile, value: "1920")
        let request = ParameterStepRequest(
            action: .crop,
            inputs: fixture.inputs,
            inputContext: .selected
        )
        let stateJSON = try JSONOutput.string(
            for: MenuState.crop(request),
            prettyPrinted: false
        )
        let menu = CropParameterMenu.response(
            stateJSON: stateJSON,
            query: "w128",
            environment: fixture.environment
        )
        let saveStateJSON = try #require(
            menu.items.first?.mods?.control?
                .variables?[ActionMenu.menuStateVariable]
        )

        let response = CropParameterMenu.response(
            stateJSON: saveStateJSON,
            query: "",
            environment: fixture.environment
        )

        #expect(response.items.first?.title == "Move existing settings")
        #expect(response.items.first?.valid == true)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))

        let returnedMenu = PresetMigrationMenu.response(
            stateJSON: try #require(response.items.first?.arg),
            environment: fixture.environment
        )

        #expect(!FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        let presets = try PresetStore(fileURL: fixture.customFile).load().presets
        #expect(presets.count == 2)
        #expect(returnedMenu.items.count == 1)
        #expect(returnedMenu.items.first?.title == "Width 128, auto height")
        #expect(returnedMenu.items.first?.subtitle.contains("Saved preset") == true)
    }

    @Test
    func destinationIsAtomicallyWrittenAndValidatedBeforeSourceDeletion() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile)
        let writer = ControlledAtomicWriter()
        let coordinator = PresetMigrationCoordinator(
            environment: fixture.environment,
            writer: writer
        )
        let migration = try #require(availableMigration(coordinator.status()))

        try coordinator.move(migration)

        #expect(writer.urls.first == fixture.customFile)
        #expect(writer.urls.last == fixture.metadataFile)
        #expect(!FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        #expect(try PresetStore(fileURL: fixture.customFile).load().presets.count == 1)
    }

    @Test
    func sourceIsNotDeletedAfterDestinationWriteFailure() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile)
        let writer = ControlledAtomicWriter(destinationBehavior: .fail)
        let coordinator = PresetMigrationCoordinator(
            environment: fixture.environment,
            writer: writer
        )
        let migration = try #require(availableMigration(coordinator.status()))

        #expect(throws: (any Error).self) {
            try coordinator.move(migration)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))
    }

    @Test
    func sourceIsNotDeletedAfterDestinationValidationFailure() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile)
        let writer = ControlledAtomicWriter(destinationBehavior: .writeCorruptData)
        let coordinator = PresetMigrationCoordinator(
            environment: fixture.environment,
            writer: writer
        )
        let migration = try #require(availableMigration(coordinator.status()))

        #expect(throws: PresetMigrationError.destinationValidationFailed) {
            try coordinator.move(migration)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.defaultFile.path))
        #expect(FileManager.default.fileExists(atPath: fixture.customFile.path))
    }

    @Test
    func bothFilesProduceVisibleConflictWithoutChangingEither() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.savePreset(at: fixture.defaultFile, value: "w128")
        try fixture.savePreset(at: fixture.customFile, value: "h720")
        let sourceData = try Data(contentsOf: fixture.defaultFile)
        let destinationData = try Data(contentsOf: fixture.customFile)

        let response = fixture.actionMenu()

        #expect(response.items.first?.title == "Settings location conflict")
        #expect(response.items.first?.valid == false)
        #expect(response.items.first?.subtitle.contains("Automatic migration is unavailable") == true)
        #expect(response.items.first?.subtitle.contains(fixture.defaultFile.path) == false)
        #expect(response.items.first?.subtitle.contains(fixture.customFile.path) == false)
        #expect(try Data(contentsOf: fixture.defaultFile) == sourceData)
        #expect(try Data(contentsOf: fixture.customFile) == destinationData)
    }

    @Test
    func missingSourceProducesVisibleFeedbackWithoutCreatingDestination() throws {
        let fixture = try MigrationFixture(configured: true)
        try fixture.writeMetadata(lastActiveDirectory: fixture.defaultDirectory)

        let response = fixture.actionMenu()

        #expect(response.items.first?.title == "Previous settings file is missing")
        #expect(response.items.first?.valid == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))
    }

    @Test(arguments: [
        (#"not-json"#, "malformed or contains unsupported data"),
        (#"{"version":99,"presets":[]}"#, "schema version 99 is unsupported")
    ])
    func malformedAndUnsupportedSourcesAreVisibleAndNonDestructive(
        contents: String,
        expectedDetail: String
    ) throws {
        let fixture = try MigrationFixture(configured: true)
        try FileManager.default.createDirectory(
            at: fixture.defaultDirectory,
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fixture.defaultFile)

        let response = fixture.actionMenu()

        #expect(response.items.first?.title == "Previous settings cannot be moved")
        #expect(response.items.first?.subtitle.contains(expectedDetail) == true)
        #expect(try String(contentsOf: fixture.defaultFile, encoding: .utf8) == contents)
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))
    }

    @Test
    func metadataUsesCurrentVersionAndWorkflowDataLocation() throws {
        let fixture = try MigrationFixture(configured: false)

        #expect(fixture.status() == .none)
        let metadata = try JSONDecoder().decode(
            PresetLocationMetadata.self,
            from: Data(contentsOf: fixture.metadataFile)
        )

        #expect(metadata.version == PresetLocationMetadata.currentVersion)
        #expect(metadata.lastActiveDirectoryPath == fixture.defaultDirectory.path)
        #expect(fixture.metadataFile.deletingLastPathComponent() == fixture.defaultDirectory)
    }

    @Test(arguments: [
        #"not-json"#,
        #"{"version":99,"lastActiveDirectoryPath":"/tmp/old"}"#
    ])
    func malformedOrUnsupportedMetadataProducesVisibleFeedback(
        contents: String
    ) throws {
        let fixture = try MigrationFixture(configured: true)
        try FileManager.default.createDirectory(
            at: fixture.defaultDirectory,
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fixture.metadataFile)

        let response = fixture.actionMenu()

        #expect(response.items.first?.title == "Unable to read settings location")
        #expect(response.items.first?.valid == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.customFile.path))
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
    let root: URL
    let defaultDirectory: URL
    let customDirectory: URL
    let defaultFile: URL
    let customFile: URL
    let metadataFile: URL
    let environment: Environment
    let inputs = [
        "/tmp/First Input With Spaces.png",
        "/tmp/Second Input.pdf"
    ]

    init(configured: Bool) throws {
        root = try makeTemporaryDirectory()
            .appendingPathComponent("Migration Root With Spaces")
        defaultDirectory = root.appendingPathComponent(
            "Workflow Data With Spaces",
            isDirectory: true
        )
        customDirectory = root.appendingPathComponent(
            "Synced Presets With Spaces",
            isDirectory: true
        )
        defaultFile = defaultDirectory.appendingPathComponent("presets.json")
        customFile = customDirectory.appendingPathComponent("presets.json")
        metadataFile = defaultDirectory.appendingPathComponent(
            PresetMigrationCoordinator.metadataFileName
        )
        environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: defaultDirectory.path,
            PresetStore.configuredPathEnvironmentKey:
                configured ? customDirectory.path : ""
        ])
    }

    func environment(configured: Bool) -> Environment {
        Environment(values: [
            PresetStore.workflowDataEnvironmentKey: defaultDirectory.path,
            PresetStore.configuredPathEnvironmentKey:
                configured ? customDirectory.path : ""
        ])
    }

    func status() -> PresetMigrationStatus {
        PresetMigrationCoordinator(environment: environment).status()
    }

    func savePreset(at url: URL, value: String = "w128") throws {
        _ = try PresetStore(fileURL: url).save(.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse(value))
        )))
    }

    func writeMetadata(lastActiveDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: defaultDirectory,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(PresetLocationMetadata(
            lastActiveDirectoryPath: lastActiveDirectory.path
        )).write(to: metadataFile, options: .atomic)
    }

    func actionMenu(
        context: ActionInputContext = .arguments
    ) -> ScriptFilterResponse {
        ActionMenu.response(
            for: InputSelection(
                inputs: inputs,
                mediaKinds: [.image, .pdf]
            ),
            query: "",
            context: context,
            environment: environment
        )
    }
}

private final class ControlledAtomicWriter: AtomicDataWriting {
    enum DestinationBehavior {
        case normal
        case fail
        case writeCorruptData
    }

    var destinationBehavior: DestinationBehavior
    var urls: [URL] = []

    init(destinationBehavior: DestinationBehavior = .normal) {
        self.destinationBehavior = destinationBehavior
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        urls.append(url)
        if url.lastPathComponent == "presets.json" {
            switch destinationBehavior {
            case .normal:
                break
            case .fail:
                throw CocoaError(.fileWriteUnknown)
            case .writeCorruptData:
                try Data("not-json".utf8).write(to: url, options: .atomic)
                return
            }
        }
        try data.write(to: url, options: .atomic)
    }
}

private struct EmptyMigrationClipboard: ClipboardReading {
    func fileURLs() -> [URL] {
        []
    }

    func string() -> String? {
        nil
    }
}
