import Foundation
import Testing
@testable import AlfredClop

struct ClopRequestDispatcherTests {
    @Test
    func versionedInputAndRouteModelsRoundTrip() throws {
        let request = ClopRequest(
            input: .explicit(
                items: [
                    "/tmp/first image.png",
                    "https://example.com/video.mp4"
                ],
                extractText: false
            ),
            route: .execute(action: .optimise(aggressive: true))
        )

        #expect(try roundTrip(request) == request)
    }

    @Test
    func menuRouteWithoutActionOpensMainMenu() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .menu(action: nil)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder()
        )

        #expect(response.items.map(\.title).contains("Optimize"))
        #expect(response.items.first?.subtitle.hasPrefix("Passed input:") == true)
    }

    @Test
    func cropMenuRouteOpensCleanParameterMenu() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .menu(action: .crop)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder()
        )

        #expect(response.items.first?.title == "Type crop or resize parameters")
    }

    @Test
    func accidentalMenuParameterObjectIsIgnored() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let json = """
        {
          "version": 1,
          "input": {"source": "explicit", "items": ["\(file.path)"]},
          "route": {
            "type": "menu",
            "action": {"type": "crop", "size": "1200x630"}
          }
        }
        """

        let response = ClopRequestDispatcher.response(
            requestJSON: json,
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder()
        )

        #expect(response.items.map(\.title).contains("Optimize"))
        #expect(response.items.first?.title != "Use 1200x630")
    }

    @Test
    func executeRouteInheritsWorkflowConfiguration() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(action: .optimise(aggressive: false))
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: Environment(values: [
                "copyResult": "1",
                "recursiveFolders": "true"
            ]),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Optimization complete")
        #expect(runner.command?.arguments.contains("--copy") == true)
        #expect(runner.command?.arguments.contains("--recursive") == true)
    }

    @Test
    func emptyFinderSelectionStopsWithoutClipboardFallback() throws {
        let request = ClopRequest(
            input: .finderSelection,
            route: .menu(action: nil)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(
                text: "https://example.com/photo.png"
            ),
            finder: DispatcherFinder()
        )

        #expect(response.items.first?.title == "No Finder selection")
    }

    @Test
    func unsupportedRequestVersionIsVisible() throws {
        let request = ClopRequest(
            version: 99,
            input: .clipboard,
            route: .menu(action: nil)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder()
        )

        #expect(response.items.first?.title == "Unsupported Clop request")
    }

    @Test
    func ambiguousURLShowsOnlyURLCapableActions() {
        let response = ActionMenu.response(
            for: InputSelection(
                inputs: ["https://example.com/download"],
                mediaKinds: [],
                itemKinds: [.remoteURL],
                ambiguousKinds: [.remoteURL]
            ),
            query: ""
        )

        #expect(response.items.map(\.title) == [
            "Optimize",
            "Aggressive Optimize",
            "Crop / Resize",
            "Downscale",
            "Convert Image"
        ])
        #expect(response.items[2].subtitle.contains("Requires image, video, or PDF"))
    }
}

private struct DispatcherClipboard: ClipboardReading {
    var urls: [URL] = []
    var text: String?

    func fileURLs() -> [URL] {
        urls
    }

    func string() -> String? {
        text
    }
}

private struct DispatcherFinder: FinderSelectionReading {
    var items: [String] = []

    func selectedItems() throws -> [String] {
        items
    }
}

private final class CapturingDispatcherRunner: ClopProcessRunning,
    @unchecked Sendable {
    var command: ClopCommand?

    func run(_ command: ClopCommand) throws -> ClopProcessResult {
        self.command = command
        return ClopProcessResult(
            terminationStatus: 0,
            standardOutput: Data(#"{"done":[],"failed":[]}"#.utf8),
            standardError: Data()
        )
    }
}

private func dispatcherBuilder() -> ClopCommandBuilder {
    ClopCommandBuilder(discovery: StubDiscovery(
        diagnostics: ClopDiagnostics(
            found: true,
            path: "/tmp/ClopCLI",
            source: "test",
            errors: []
        )
    ))
}
