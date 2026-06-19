import Foundation
import Testing
@testable import AlfredClop

struct ClopCLIDiscoveryTests {
    @Test
    func overrideAcceptsExecutableFile() throws {
        let fixture = try executableFixture(named: "ClopCLI")
        let diagnostics = discovery(
            environment: [ClopCLIDiscovery.overrideEnvironmentKey: fixture.path]
        ).discover()

        #expect(diagnostics.found)
        #expect(diagnostics.path == fixture.path)
        #expect(diagnostics.source == "environmentOverride")
    }

    @Test
    func overrideRejectsMissingFile() {
        let path = "/tmp/alfred-clop-does-not-exist-\(UUID().uuidString)"
        let diagnostics = discovery(
            environment: [ClopCLIDiscovery.overrideEnvironmentKey: path]
        ).discover()

        #expect(!diagnostics.found)
        #expect(diagnostics.errors.contains { $0.contains("does not exist") })
    }

    @Test
    func overrideRejectsDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnostics = discovery(
            environment: [ClopCLIDiscovery.overrideEnvironmentKey: directory.path]
        ).discover()

        #expect(!diagnostics.found)
        #expect(diagnostics.errors.contains { $0.contains("is a directory") })
    }

    @Test
    func overrideRejectsNonExecutableFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("ClopCLI")
        try Data().write(to: file)

        let diagnostics = discovery(
            environment: [ClopCLIDiscovery.overrideEnvironmentKey: file.path]
        ).discover()

        #expect(!diagnostics.found)
        #expect(diagnostics.errors.contains { $0.contains("is not executable") })
    }

    @Test
    func pathLookupFindsExecutable() throws {
        let fixture = try executableFixture(named: "clop")
        let diagnostics = discovery(
            environment: ["PATH": fixture.deletingLastPathComponent().path]
        ).discover()

        #expect(diagnostics.found)
        #expect(diagnostics.path == fixture.path)
        #expect(diagnostics.source == "path")
    }

    @Test
    func diagnosticReportIncludesSupportFieldsWithoutInputData() throws {
        let directory = try makeTemporaryDirectory()
        let app = directory.appendingPathComponent(
            "Clop.app",
            isDirectory: true
        )
        let support = app
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )
        let info = app
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        try NSDictionary(dictionary: [
            "CFBundleIdentifier": "com.lowtechguys.Clop",
            "CFBundleShortVersionString": "2.5.0",
            "CFBundleVersion": "250"
        ]).write(to: info)
        let cli = support.appendingPathComponent("ClopCLI")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: cli)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: cli.path
        )

        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path,
            "alfred_workflow_name": "Clop",
            "alfred_workflow_bundleid": "com.aft.clop",
            "alfred_workflow_version": "1.2.3",
            "preserveOriginal": "true",
            "defaultOptimisation": "aggressive",
            "showClopUI": "false",
            "copyResult": "true",
            "recursiveFolders": "true",
            "readClipboardForKeyword": "false",
            "recoverClipboardHistory": "true",
            "completionNotifications": "false",
            "errorNotifications": "true",
            "cacheRetention": "14"
        ])
        let store = try PresetStore(environment: environment)
        _ = try store.save(.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse("16:9"))
        )))

        let report = ClopDiagnosticReport.text(
            environment: environment,
            discovery: StaticDiscovery(ClopDiagnostics(
                found: true,
                path: cli.path,
                source: "environmentOverride",
                errors: ["Override path was accepted after validation."]
            )),
            store: store,
            pipelineProvider: DiagnosticPipelineStub(count: 2)
        )

        #expect(report.contains("Alfred Clop Diagnostic Report"))
        #expect(report.contains("- Version: 1.2.3"))
        #expect(report.contains("- Path: \(cli.path)"))
        #expect(report.contains("- Discovery source: Override (ALFRED_CLOP_CLI_PATH)"))
        #expect(report.contains("- Executable: Yes"))
        #expect(report.contains("- App bundle ID: com.lowtechguys.Clop"))
        #expect(report.contains("- App version: 2.5.0 (250)"))
        #expect(report.contains("- Preserve originals: Yes"))
        #expect(report.contains("- Default optimization: Aggressive"))
        #expect(report.contains("- Floating Result: No"))
        #expect(report.contains("- Read Clipboard keyword input: No"))
        #expect(report.contains("- Crop / Resize presets: 1"))
        #expect(report.contains("- Saved pipelines: 2"))
        #expect(report.contains("- optimise, crop, downscale, convert"))
        #expect(report.contains("- Override path was accepted after validation."))
        #expect(!report.contains("PATH="))
        #expect(!report.contains("clipboard contents"))
    }

    private func discovery(environment: [String: String]) -> ClopCLIDiscovery {
        ClopCLIDiscovery(
            environment: environment,
            applicationPaths: []
        )
    }

    private func executableFixture(named name: String) throws -> URL {
        let directory = try makeTemporaryDirectory()
        let file = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: file.path
        )
        return file
    }
}

private struct StaticDiscovery: ClopCLIDiscovering {
    var diagnostics: ClopDiagnostics

    init(_ diagnostics: ClopDiagnostics) {
        self.diagnostics = diagnostics
    }

    func discover() -> ClopDiagnostics {
        diagnostics
    }
}

private struct DiagnosticPipelineStub: ClopPipelineProviding {
    var count: Int

    func listPipelines() throws -> [SavedPipeline] {
        (0..<count).map {
            SavedPipeline(name: "Pipeline \($0)", rawText: "optimise")
        }
    }

    func pipelinePrompt(task: String) throws -> String {
        ""
    }

    func addPipeline(_ request: PipelineAddRequest) throws {}

    func deletePipeline(named name: String) throws {}
}
