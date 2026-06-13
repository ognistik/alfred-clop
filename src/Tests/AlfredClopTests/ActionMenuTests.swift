import Foundation
import Testing
@testable import AlfredClop

struct ActionMenuTests {
    @Test
    func imageShowsConvert() {
        #expect(actions(for: [.image]).contains(.convertImage))
    }

    @Test
    func videoAndAudioShowTheirOwnConversionActions() {
        #expect(actions(for: [.video]).contains(.convertVideo))
        #expect(actions(for: [.audio]).contains(.convertAudio))
        #expect(!actions(for: [.video]).contains(.convertImage))
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
            .crop,
            .downscale,
            .stripMetadata
        ])
    }

    @Test
    func imageAndPDFIntersectionIsCorrect() {
        #expect(actions(for: [.image, .pdf]) == [
            .optimise,
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
    func ambiguousFolderShowsDocumentedFolderActions() {
        let response = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/folder"],
                mediaKinds: [],
                itemKinds: [.folder],
                ambiguousKinds: [.folder]
            ),
            query: ""
        )

        #expect(response.items.map(\.title) == [
            "Optimize",
            "Crop / Resize",
            "Downscale",
            "Convert Image",
            "Convert Video",
            "Convert Audio",
            "Crop PDF (Reversible)",
            "Uncrop PDF",
            "Strip Metadata",
            "Configuration"
        ])
        #expect(response.items[1].subtitle.contains("Image, video, or PDF only"))
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
        #expect(response.items[0].subtitle.hasPrefix("Selected input:"))
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

        #expect(response.items[0].subtitle == "Passed input: Compress with Clop")
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
        #expect(response.items[0].subtitle.hasPrefix("Copied input:"))
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

        #expect(response.items[0].subtitle == "Copied input: Compress with Clop")
        #expect(
            response.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.clipboard.rawValue
        )
    }

    @Test
    func rawClipboardImagePathSurvivesMenuReruns() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = InputCollector(
            clipboardImageMaterializer: FoundationClipboardImageMaterializer(
                directoryURL: directory.appendingPathComponent("clipboard cache")
            )
        )
        let first = ActionMenu.response(
            clipboard: ActionMenuClipboard(
                imageValue: ClipboardImage(
                    data: Data("raw image".utf8),
                    format: .tiff
                )
            ),
            query: "",
            collector: collector
        )
        let inputJSON = try #require(
            first.variables?[ActionMenu.inputJSONVariable]
        )
        let normalized = try JSONDecoder().decode(
            MenuInput.self,
            from: Data(inputJSON.utf8)
        )

        let rerun = ActionMenu.response(
            inputJSON: inputJSON,
            query: "crop",
            context: .clipboard
        )

        #expect(normalized.paths.count == 1)
        #expect(normalized.paths[0].hasSuffix(".tiff"))
        #expect(rerun.items.map(\.title) == ["Crop / Resize"])
        #expect(rerun.variables?[ActionMenu.inputJSONVariable] == inputJSON)
    }

    @Test
    func emptyClipboardReturnsVisibleErrorItem() {
        let response = ActionMenu.response(
            clipboard: ActionMenuClipboard(),
            query: ""
        )

        #expect(response.items.map(\.title) == [
            "Configuration",
            "No supported files in clipboard"
        ])
        #expect(response.items[1].valid == false)
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
    func ambiguousClipboardURLShowsURLCapableActions() {
        let response = ActionMenu.response(
            clipboard: ActionMenuClipboard(
                text: "https://example.com/download"
            ),
            query: ""
        )

        #expect(response.items.map(\.title) == [
            "Optimize",
            "Crop / Resize",
            "Downscale",
            "Convert Image",
            "Convert Video",
            "Convert Audio",
            "Configuration"
        ])
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
        #expect(
            response.items.first?.variables?[ActionMenu.requestKindVariable]
                == "operation"
        )
    }

    @Test(arguments: [
        ActionInputContext.selected,
        ActionInputContext.clipboard,
        ActionInputContext.arguments
    ])
    func cropRoutesToTypedCropMenuState(
        context: ActionInputContext
    ) throws {
        let inputs = ["/tmp/first image.png", "/tmp/second image.jpg"]
        let response = ActionMenu.response(
            for: InputSelection(inputs: inputs, mediaKinds: [.image]),
            query: "crop",
            context: context
        )
        let item = try #require(response.items.first)
        let argument = try #require(item.arg)
        let request = try JSONDecoder().decode(
            ParameterStepRequest.self,
            from: Data(argument.utf8)
        )
        let stateJSON = try #require(
            item.variables?[ActionMenu.menuStateVariable]
        )
        let state = try JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        )

        #expect(request.action == .crop)
        #expect(request.inputs == inputs)
        #expect(request.inputContext == context)
        #expect(state.mode == .crop)
        #expect(state.parameterRequest?.action == request.action)
        #expect(state.parameterRequest?.inputs == request.inputs)
        #expect(state.parameterRequest?.inputContext == request.inputContext)
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == "parameterStep"
        )
        #expect(
            item.variables?[ActionMenu.inputContextVariable]
                == context.rawValue
        )
        #expect(item.variables?[ActionMenu.publicRequestVariable] == "")
        let inputJSON = try #require(
            item.variables?[ActionMenu.inputJSONVariable]
        )
        let menuInput = try JSONDecoder().decode(
            MenuInput.self,
            from: Data(inputJSON.utf8)
        )
        #expect(menuInput.paths == inputs)
    }

    @Test
    func folderSubtitleIncludesExactCountWhenKnown() {
        let response = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/media"],
                mediaKinds: [.image],
                itemKinds: [.folder],
                processableItemCount: 3
            ),
            query: "optimize",
            context: .arguments
        )

        #expect(
            response.items[0].subtitle
                == "Passed input, folder: 3 items: Compress with Clop"
        )
    }

    @Test
    func ambiguousFolderSubtitleDoesNotClaimAnExactCount() {
        let response = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/media"],
                mediaKinds: [],
                itemKinds: [.folder],
                ambiguousKinds: [.folder]
            ),
            query: "optimize"
        )

        #expect(!response.items[0].subtitle.contains("items"))
    }

    @Test
    func extensionlessURLUsesConciseSourceAwareRequirements() {
        let response = ActionMenu.response(
            for: InputSelection(
                inputs: ["https://afadingthought.substack.com/p/notes-and-content"],
                mediaKinds: [],
                itemKinds: [.remoteURL],
                ambiguousKinds: [.remoteURL]
            ),
            query: "",
            context: .arguments
        )

        #expect(response.items[1].subtitle == "Passed input · Image, video, or PDF only")
        #expect(response.items[3].subtitle == "Passed input · Images only")
        #expect(response.items.allSatisfy { $0.subtitle.count < 60 })
    }

    @Test
    func recursionDisabledFolderErrorExplainsTheConfigurationFix() {
        let response = ActionMenu.collectionErrorResponse(
            InputCollectionError.recursionDisabledFolder("/tmp/media"),
            context: .arguments
        )

        #expect(response.items[0].title == "Supported media is in subfolders")
        #expect(
            response.items[0].subtitle
                == "Press Return to open workflow configuration."
        )
        #expect(response.items[0].valid)
        #expect(
            response.items[0].variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.workflowSettings.rawValue
        )
    }

    @Test
    func unimplementedParameterActionRemainsParameterStep() throws {
        let response = ActionMenu.response(
            for: InputSelection(inputs: ["/tmp/image.png"], mediaKinds: [.image]),
            query: "downscale"
        )
        let item = try #require(response.items.first)
        let request = try JSONDecoder().decode(
            ParameterStepRequest.self,
            from: Data(try #require(item.arg).utf8)
        )

        #expect(request.action == .downscale)
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == "parameterStep"
        )
    }

    @Test
    func smallerSearchDoesNotExposeStandaloneAggressiveOptimize() {
        let response = ActionMenu.response(
            for: InputSelection(inputs: ["/tmp/image.png"], mediaKinds: [.image]),
            query: "smaller"
        )

        #expect(response.items.map(\.title) == ["Downscale"])
    }

    private func actions(for kinds: [MediaKind]) -> [ClopAction] {
        ActionCatalog.validActions(for: kinds).map(\.action)
    }
}

private struct ActionMenuClipboard: ClipboardReading {
    var urls: [URL] = []
    var text: String?
    var imageValue: ClipboardImage?

    func fileURLs() -> [URL] {
        urls
    }

    func string() -> String? {
        text
    }

    func image() -> ClipboardImage? {
        imageValue
    }
}
