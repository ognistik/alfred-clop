import Foundation
import Testing
@testable import AlfredClop

struct InputCollectorTests {
    @Test
    func clipboardNativeFileURLsUseExistingInputPipeline() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let clipboard = StubClipboard(
            urls: [file, file],
            text: "/ignored/path.jpg"
        )

        let selection = try InputCollector().collect(clipboard: clipboard)

        #expect(selection.inputs == [file.standardizedFileURL.path])
        #expect(selection.mediaKinds == [.image])
    }

    @Test
    func clipboardAcceptsFileURLsAndNewlineSeparatedPaths() throws {
        let first = try temporaryFile(named: "first.png")
        let second = first.deletingLastPathComponent().appendingPathComponent("second.pdf")
        try Data().write(to: second)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        let clipboard = StubClipboard(
            text: "\(first.absoluteString)\n\(second.path)\n\(first.path)"
        )

        let selection = try InputCollector().collect(clipboard: clipboard)

        #expect(selection.inputs == [
            first.standardizedFileURL.path,
            second.standardizedFileURL.path
        ])
        #expect(selection.mediaKinds == [.image, .pdf])
    }

    @Test
    func clipboardAcceptsSingleCopiedPath() throws {
        let file = try temporaryFile(named: "movie.mp4")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let selection = try InputCollector().collect(
            clipboard: StubClipboard(text: "  \(file.path)  ")
        )

        #expect(selection.inputs == [file.standardizedFileURL.path])
        #expect(selection.mediaKinds == [.video])
    }

    @Test
    func validPathsJSONDecodesAndNormalizes() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let input = MenuInput(paths: [file.path, file.path])
        let json = try JSONOutput.string(for: input, prettyPrinted: false)

        let selection = try InputCollector().collect(json: json)

        #expect(selection.inputs == [file.standardizedFileURL.path])
        #expect(selection.mediaKinds == [.image])
    }

    @Test
    func invalidJSONProducesAlfredErrorResponse() {
        let response = ActionMenu.response(inputJSON: "{bad json", query: "")

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Unable to read selected files")
        #expect(response.items[0].valid == false)
    }

    @Test
    func alfredSerializedPathsAreExpanded() throws {
        let first = try temporaryFile(named: "first.png")
        let second = first.deletingLastPathComponent().appendingPathComponent("second.jpg")
        try Data().write(to: second)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }

        let selection = try InputCollector().collect(
            paths: ["\(first.path)\t\(second.path)"]
        )

        #expect(selection.inputs.count == 2)
        #expect(selection.mediaKinds == [.image, .image])
    }

    @Test
    func JSONSerializedAlfredPathsAreExpanded() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let serialized = try JSONOutput.string(
            for: [file.path],
            prettyPrinted: false
        )

        let selection = try InputCollector().collect(paths: [serialized])

        #expect(selection.inputs == [file.resolvingSymlinksInPath().path])
    }

    @Test
    func newlineSeparatedArgumentPathsAreExpanded() throws {
        let first = try temporaryFile(named: "first.png")
        let second = first.deletingLastPathComponent().appendingPathComponent("second.pdf")
        try Data().write(to: second)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }

        let selection = try InputCollector().collect(
            paths: ["\(first.path)\n\(second.path)"]
        )

        #expect(selection.inputs == [
            first.standardizedFileURL.path,
            second.standardizedFileURL.path
        ])
        #expect(selection.mediaKinds == [.image, .pdf])
    }
}

private struct StubClipboard: ClipboardReading {
    var urls: [URL] = []
    var text: String?

    func fileURLs() -> [URL] {
        urls
    }

    func string() -> String? {
        text
    }
}
