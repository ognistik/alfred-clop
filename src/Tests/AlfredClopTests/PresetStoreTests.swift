import Foundation
import Testing
@testable import AlfredClop

struct PresetStoreTests {
    @Test
    func schemaRoundTripsWithCurrentVersion() throws {
        let preset = ActionPreset.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse("w128"))
        ))
        let document = SettingsDocument(presets: [preset])

        let decoded = try roundTrip(document)

        #expect(decoded.version == 1)
        #expect(decoded.presets == [preset])
        #expect(decoded.outputTemplate == "%P/%f-clop")
    }

    @Test
    func defaultLocationUsesAlfredWorkflowData() throws {
        let directory = try makeTemporaryDirectory()
            .appendingPathComponent("Workflow Data With Spaces")
        let url = try PresetStore.fileURL(environment: Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ]))

        #expect(url == directory.appendingPathComponent("settings.json"))
    }

    @Test
    func configuredLocationOverridesWorkflowDataWithoutMovingFiles() throws {
        let defaultDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("Default Data")
        let configuredDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("Synced Presets With Spaces")
        let defaultFile = defaultDirectory.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: defaultDirectory,
            withIntermediateDirectories: true
        )
        try Data("default".utf8).write(to: defaultFile)

        let url = try PresetStore.fileURL(environment: Environment(values: [
            PresetStore.workflowDataEnvironmentKey: defaultDirectory.path,
            PresetStore.configuredPathEnvironmentKey: configuredDirectory.path
        ]))

        #expect(url == configuredDirectory.appendingPathComponent("settings.json"))
        #expect(try String(contentsOf: defaultFile, encoding: .utf8) == "default")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func changingLocationUsesIndependentSettings() throws {
        let root = try makeTemporaryDirectory()
        let defaultDirectory = root.appendingPathComponent("Default")
        let customDirectory = root.appendingPathComponent("Custom")
        try PresetStore(
            fileURL: defaultDirectory.appendingPathComponent("settings.json")
        ).persist(SettingsDocument(outputTemplate: "%P/%f-default"))

        let customEnvironment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: defaultDirectory.path,
            PresetStore.configuredPathEnvironmentKey: customDirectory.path
        ])
        let customStore = try PresetStore(environment: customEnvironment)

        #expect(try customStore.load() == SettingsDocument())
        #expect(!FileManager.default.fileExists(atPath: customStore.fileURL.path))

        try customStore.updateOutputTemplate("%P/%f-custom")
        #expect(try customStore.load().outputTemplate == "%P/%f-custom")
        #expect(
            try PresetStore(
                fileURL: defaultDirectory.appendingPathComponent("settings.json")
            ).load().outputTemplate == "%P/%f-default"
        )
    }

    @Test
    func persistenceUsesAtomicWriterAtFinalLocation() throws {
        let directory = try makeTemporaryDirectory()
            .appendingPathComponent("Preset Folder With Spaces")
        let fileURL = directory.appendingPathComponent("settings.json")
        let writer = RecordingAtomicWriter()
        let store = PresetStore(fileURL: fileURL, writer: writer)

        _ = try store.save(.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse("1200x630"))
        )))

        #expect(writer.urls == [fileURL])
        let data = try #require(writer.data)
        let document = try JSONDecoder().decode(SettingsDocument.self, from: data)
        #expect(document.presets.count == 1)
    }

    @Test
    func equivalentValuesDoNotCreateDuplicatePresets() throws {
        let fileURL = try makeTemporaryDirectory()
            .appendingPathComponent("settings.json")
        let store = PresetStore(fileURL: fileURL)
        let friendly = ActionPreset.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse("w128"))
        ))
        let native = ActionPreset.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse("128x0"))
        ))

        #expect(try store.save(friendly))
        #expect(try !store.save(native))
        #expect(try store.load().presets == [friendly])
    }

    @Test
    func unsupportedVersionIsRejectedWithoutChangingTheFile() throws {
        let fileURL = try makeTemporaryDirectory()
            .appendingPathComponent("settings.json")
        let original = #"{"version":2,"presets":[],"outputTemplate":"%P/%f-clop"}"#
        try Data(original.utf8).write(to: fileURL)
        let store = PresetStore(fileURL: fileURL)

        #expect(throws: PresetStoreError.unsupportedVersion(2)) {
            try store.load()
        }
        #expect(throws: PresetStoreError.unsupportedVersion(2)) {
            try store.save(.crop(CropActionPreset(
                size: CropSizeParser.parse("1920")!
            )))
        }
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == original)
    }

    @Test(arguments: [
        #"{"version":1,"presets":[{"type":"rotate","degrees":90}],"outputTemplate":"%P/%f-clop"}"#,
        #"{"version":1,"presets":[{"type":"crop","size":"w128","longEdge":false}],"outputTemplate":"%P/%f-clop"}"#,
        #"{"version":1,"presets":"not-an-array","outputTemplate":"%P/%f-clop"}"#,
        #"not-json"#
    ])
    func malformedOrUnsupportedFilesAreRejected(contents: String) throws {
        let fileURL = try makeTemporaryDirectory()
            .appendingPathComponent("settings.json")
        try Data(contents.utf8).write(to: fileURL)

        #expect(throws: PresetStoreError.invalidFile) {
            try PresetStore(fileURL: fileURL).load()
        }
    }
}

private final class RecordingAtomicWriter: AtomicDataWriting {
    var data: Data?
    var urls: [URL] = []

    func writeAtomically(_ data: Data, to url: URL) throws {
        self.data = data
        urls.append(url)
    }
}
