import Foundation
import Testing
@testable import AlfredClop

struct PipelineMenuTests {
    @Test
    func clearImageInputShowsOnlyCompatiblePipelinesWithoutRedundantTypeSubtitle() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "",
            provider: PipelineProviderStub()
        )

        #expect(response.items.map(\.title) == [
            "Search saved pipelines or type inline steps",
            "Any",
            "To WebP"
        ])
        #expect(response.items[0].subtitle == "Selected file · Example: convert(to: webp) · ⌘L Syntax")
        #expect(response.items[1].subtitle == "Selected file · ⌘L Details")
        #expect(response.items[2].subtitle == "Selected file · ⌘L Details")
        #expect(response.items[2].text?.largetype?.contains("Steps\nconvert(to: webp)") == true)

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((response.items[2].arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(name: "To WebP")))
    }

    @Test
    func mixedInputShowsMediaFilterRows() {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image, .video]),
            query: "",
            provider: PipelineProviderStub()
        )

        #expect(response.items.first?.title == "Pick a media type, search, or type inline steps")
        #expect(response.items.map(\.title).contains("Image Pipelines"))
        #expect(response.items.map(\.title).contains("Video Pipelines"))
        #expect(!response.items.map(\.title).contains("All-File Pipelines"))
        #expect(!response.items.map(\.title).contains("All Pipelines"))
    }

    @Test
    func mediaFilterShowsAcceptedTypeAndIncludesAllFilePipelines() {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image, .video]),
            query: "image",
            provider: PipelineProviderStub()
        )

        #expect(response.items.map(\.title) == ["Any", "To WebP"])
        #expect(response.items[0].subtitle.contains("All-file pipeline"))
        #expect(response.items[1].subtitle.contains("Image pipeline"))
    }

    @Test
    func mixedInputSearchesOnlyCompatiblePipelines() {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image, .video]),
            query: "to",
            provider: PipelineProviderStub()
        )

        #expect(Set(response.items.map(\.title)) == ["Any", "To WebP", "To GIF"])
        #expect(!response.items.map(\.title).contains("To MP3"))
    }

    @Test
    func inlineSyntaxRunsTypedStepsBeforeSavedMatches() throws {
        let steps = "crop(width: 1600) -> convert(to: webp)"
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: steps,
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Run inline pipeline")
        #expect(item.subtitle == "Selected file · Clop validates steps · ⌘L Syntax")
        #expect(item.text?.largetype?.contains("Steps\n\(steps)") == true)

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(name: steps)))
    }

    @Test
    func bareKnownPipelineStepCanRunInline() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.video]),
            query: "removeAudio",
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Run inline pipeline")

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(name: "removeAudio")))
    }

    @Test
    func plainUnmatchedSearchDoesNotRunInline() {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "not a pipeline",
            provider: PipelineProviderStub()
        )

        #expect(response.items.map(\.title) == ["No matching pipelines"])
        #expect(response.items.first?.valid == false)
        #expect(response.items.first?.subtitle == "Search saved pipelines or use steps like convert(to: webp)")
    }

    @Test
    func noSavedPipelinesStillAllowsInlineSyntax() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "convert(to: webp)",
            provider: PipelineProviderStub(pipelines: [])
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Run inline pipeline")

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(name: "convert(to: webp)")))
    }

    @Test
    func pipelineCommandIgnoresOutputAndCopySettings() throws {
        let execution = ExecutionOptions(
            showClopUI: true,
            copyResult: true,
            output: .sameFolder(template: "%P/%f-small"),
            backup: .trustClop,
            adaptiveOptimisation: nil,
            pdfDPI: nil,
            recursiveFolders: true,
            aggressiveProcessing: true
        )
        let command = try ClopCommandBuilder(discovery: StubDiscovery(
            diagnostics: ClopDiagnostics(
                found: true,
                path: "/tmp/Clop",
                source: "test",
                errors: []
            )
        )).command(for: OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .pipeline(PipelineRunRequest(name: "To WebP")),
            execution: execution
        ))
        #expect(command.arguments == [
            "pipeline",
            "run",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--gui",
            "--recursive",
            "To WebP",
            "/tmp/image.png"
        ])
    }

    @Test
    func pipelinesConfigurationParsesAddGrammarAndOffersReplaceModifier() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines add To WebP => convert(to: webp) ; img skip hide",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Pipeline To WebP already exists")
        #expect(item.valid == false)

        let replaceJSON = try #require(item.mods?.command?.arg)
        let state = try JSONDecoder().decode(
            MenuState.self,
            from: Data(replaceJSON.utf8)
        )
        let add = try #require(state.pipelineAction?.add)
        #expect(add == PipelineAddRequest(
            name: "To WebP",
            steps: "convert(to: webp)",
            fileType: .image,
            skipOptimisation: true,
            hideResult: true,
            replace: true
        ))
    }

    @Test
    func pipelinesConfigurationKeepsAddGuideFirstAndCategorySubtitlesClean() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        #expect(response.items.first?.title == "Add pipeline")
        let image = try #require(response.items.first { $0.title == "Image Pipelines" })
        #expect(image.subtitle == "1 Saved Pipeline")
        #expect(image.text?.largetype?.contains("Pipeline add syntax") == true)
    }

    @Test
    func pipelinesConfigurationKeepsAddGuideFirstDuringGlobalSearch() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines to",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        #expect(response.items.first?.title == "Add pipeline")
        #expect(response.items.dropFirst().map(\.title).contains("To WebP"))
    }

    @Test
    func pipelinesConfigurationAddsFromBareNameAndStepsSyntax() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines New Pipeline => removeAudio ; skip",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Add Pipeline New Pipeline")
        #expect(item.subtitle == "All file types · Skip optimization · ⌘L Reference")

        let json = try #require(item.arg)
        let state = try JSONDecoder().decode(
            MenuState.self,
            from: Data(json.utf8)
        )
        let add = try #require(state.pipelineAction?.add)
        #expect(add == PipelineAddRequest(
            name: "New Pipeline",
            steps: "removeAudio",
            skipOptimisation: true
        ))
    }

    @Test
    func pipelinesConfigurationSuggestsCreationWhenRootSearchHasNoMatches() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines New Pipeline",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        #expect(response.items.map(\.title) == ["Add a new pipeline"])
        #expect(response.items.first?.subtitle == "Use Name => steps ; img skip hide · ⌘L Reference")
        #expect(response.items.first?.autocomplete == ":pipelines New Pipeline")
    }

    @Test
    func pipelinesConfigurationDoesNotSuggestCreationInsideCategorySearch() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines image New Pipeline",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        #expect(response.items.map(\.title) == ["No matching image pipelines"])
        #expect(response.items.first?.subtitle == "Try another pipeline name.")
    }

    @Test
    func pipelinesConfigurationDeletesThroughConfirmationAndReturnsToFilter() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let list = ConfigurationMenu.namespaceResponse(
            query: ":pipelines image",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        let pipeline = try #require(list.items.first { $0.title == "To WebP" })
        #expect(pipeline.valid == false)
        let confirmJSON = try #require(pipeline.mods?.command?.arg)
        let confirmation = ConfigurationMenu.response(
            stateJSON: confirmJSON,
            query: "",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        #expect(confirmation.items.map(\.title) == [
            "Delete Pipeline To WebP?",
            "Cancel"
        ])
        #expect(confirmation.items[1].arg == ":pipelines image")
    }

    private func stateJSON(mediaKinds: [MediaKind]) -> String {
        let request = ParameterStepRequest(
            action: .pipeline,
            inputs: ["/tmp/image.png"],
            inputContext: .selected,
            mediaKinds: mediaKinds,
            itemKinds: [.localFile]
        )
        return (try? JSONOutput.string(
            for: MenuState.pipeline(request),
            prettyPrinted: false
        )) ?? ""
    }
}

private struct PipelineProviderStub: ClopPipelineProviding {
    var pipelines: [SavedPipeline] = [
        SavedPipeline(
            name: "To WebP",
            fileType: .image,
            rawText: "convert(to: webp)",
            skipOptimisation: true
        ),
        SavedPipeline(
            name: "To GIF",
            fileType: .video,
            rawText: "convert(to: gif)",
            skipOptimisation: true
        ),
        SavedPipeline(
            name: "To MP3",
            fileType: .audio,
            rawText: "convert(to: mp3)",
            skipOptimisation: true
        ),
        SavedPipeline(
            name: "Any",
            rawText: "copyToClipboard"
        )
    ]

    func listPipelines() throws -> [SavedPipeline] {
        pipelines
    }

    func addPipeline(_ request: PipelineAddRequest) throws {}

    func deletePipeline(named name: String) throws {}
}
