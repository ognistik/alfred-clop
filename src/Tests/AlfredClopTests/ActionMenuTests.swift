import Foundation
import Testing
@testable import AlfredClop

struct ActionMenuTests {
    @Test
    func imageShowsConvert() {
        #expect(actions(for: [.image]).contains(.convert))
    }

    @Test
    func videoDoesNotShowConvert() {
        #expect(!actions(for: [.video]).contains(.convert))
    }

    @Test
    func pdfShowsCropAndUncropPDF() {
        let result = actions(for: [.pdf])

        #expect(result.contains(.cropPDF))
        #expect(result.contains(.uncropPDF))
    }

    @Test
    func audioShowsDownscaleButNotCrop() {
        let result = actions(for: [.audio])

        #expect(result.contains(.downscale))
        #expect(!result.contains(.crop))
    }

    @Test
    func imageAndVideoIntersectionIsCorrect() {
        #expect(actions(for: [.image, .video]) == [
            .optimise,
            .aggressiveOptimise,
            .crop,
            .downscale,
            .stripMetadata
        ])
    }

    @Test
    func imageAndPDFIntersectionIsCorrect() {
        #expect(actions(for: [.image, .pdf]) == [
            .optimise,
            .aggressiveOptimise,
            .crop
        ])
    }

    @Test
    func unknownReturnsUnsupportedItem() {
        let response = ActionMenu.response(
            for: InputSelection(inputs: ["/tmp/file.bin"], mediaKinds: [.unknown]),
            query: ""
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Unsupported file type")
        #expect(response.items[0].valid == false)
    }

    @Test
    func folderReturnsNotSupportedItem() {
        let response = ActionMenu.response(
            for: InputSelection(inputs: ["/tmp/folder"], mediaKinds: [.folder]),
            query: ""
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Folders are not supported yet")
        #expect(response.items[0].valid == false)
    }

    @Test
    func menuResponseIsValidScriptFilterJSON() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let input = try JSONOutput.string(
            for: MenuInput(paths: [file.path]),
            prettyPrinted: false
        )

        let response = ActionMenu.response(inputJSON: input, query: "webp")
        let data = try JSONOutput.data(for: response)
        let decoded = try JSONDecoder().decode(ScriptFilterResponse.self, from: data)
        let storedInputJSON = try #require(
            decoded.variables?[ActionMenu.inputJSONVariable]
        )
        let storedInput = try JSONDecoder().decode(
            MenuInput.self,
            from: Data(storedInputJSON.utf8)
        )

        #expect(decoded.items.map(\.title) == ["Convert Image"])
        #expect(decoded.items[0].arg?.contains(#""step":"parameters""#) == true)
        #expect(storedInput.paths == [file.resolvingSymlinksInPath().path])
    }

    @Test
    func directPathsSupportUniversalActionInput() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let response = ActionMenu.response(paths: [file.path], query: "exif")

        #expect(response.items.map(\.title) == ["Strip Metadata"])
        #expect(response.items[0].subtitle.hasPrefix("Selected files:"))
        #expect(response.variables?[ActionMenu.inputJSONVariable] != nil)
        #expect(
            response.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.selected.rawValue
        )
    }

    @Test
    func directArgumentsUsePassedFileContext() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let response = ActionMenu.response(
            paths: [file.path],
            query: "optimize",
            context: .arguments
        )

        #expect(response.items[0].subtitle == "Passed files: Compress with Clop")
        #expect(
            response.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.arguments.rawValue
        )
    }

    @Test
    func clipboardInputReusesActionCapabilitiesAndFuzzySearch() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let response = ActionMenu.response(
            clipboard: ActionMenuClipboard(urls: [file]),
            query: "exif"
        )

        #expect(response.items.map(\.title) == ["Strip Metadata"])
        #expect(response.items[0].subtitle.hasPrefix("Copied files:"))
        #expect(response.variables?[ActionMenu.inputJSONVariable] != nil)
        #expect(
            response.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.clipboard.rawValue
        )
    }

    @Test
    func clipboardContextSurvivesJSONMenuReruns() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let input = try JSONOutput.string(
            for: MenuInput(paths: [file.path]),
            prettyPrinted: false
        )

        let response = ActionMenu.response(
            inputJSON: input,
            query: "optimize",
            context: .clipboard
        )

        #expect(response.items[0].subtitle == "Copied files: Compress with Clop")
        #expect(
            response.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.clipboard.rawValue
        )
    }

    @Test
    func emptyClipboardReturnsVisibleErrorItem() {
        let response = ActionMenu.response(
            clipboard: ActionMenuClipboard(),
            query: ""
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "No supported files in clipboard")
        #expect(response.items[0].valid == false)
    }

    @Test
    func unsupportedClipboardFileReturnsVisibleErrorItem() throws {
        let file = try temporaryFile(named: "notes.txt")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let response = ActionMenu.response(
            clipboard: ActionMenuClipboard(urls: [file]),
            query: ""
        )

        #expect(response.items[0].title == "No supported files in clipboard")
        #expect(response.items[0].valid == false)
    }

    @Test
    func immediateActionEncodesOperationRequest() throws {
        let response = ActionMenu.response(
            for: InputSelection(inputs: ["/tmp/image.png"], mediaKinds: [.image]),
            query: "optimize"
        )
        let argument = try #require(response.items.first?.arg)
        let request = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data(argument.utf8)
        )

        #expect(request.inputs == ["/tmp/image.png"])
        #expect(request.action == .optimise(aggressive: false))
    }

    @Test
    func exactAliasRanksBeforePrefixAndSubsequenceMatches() {
        let response = ActionMenu.response(
            for: InputSelection(inputs: ["/tmp/image.png"], mediaKinds: [.image]),
            query: "smaller"
        )

        #expect(response.items.map(\.title).prefix(2) == [
            "Aggressive Optimize",
            "Downscale"
        ])
    }

    private func actions(for kinds: [MediaKind]) -> [ClopAction] {
        ActionCatalog.validActions(for: kinds).map(\.action)
    }
}

private struct ActionMenuClipboard: ClipboardReading {
    var urls: [URL] = []
    var text: String?

    func fileURLs() -> [URL] {
        urls
    }

    func string() -> String? {
        text
    }
}
