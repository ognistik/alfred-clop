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
