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
        #expect(response.items[1].subtitle == "Selected file · ⌃↩ Delete Pipeline · ⌘L Details")
        #expect(response.items[2].subtitle == "Selected file · ⌃↩ Delete Pipeline · ⌘L Details")
        #expect(response.items[0].icon == WorkflowIcon.guide)
        #expect(response.items[1].icon == WorkflowIcon.preset)
        #expect(response.items[2].icon == WorkflowIcon.preset)
        #expect(response.items[2].text?.largetype?.contains("Steps\nconvert(to: webp)") == true)

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((response.items[2].arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(pipeline: "To WebP")))
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
    func mixedInputShowsAllFileBranchWhenAMediaTypeHasNoSpecificPipeline() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image, .audio]),
            query: "",
            provider: PipelineProviderStub(pipelines: [
                SavedPipeline(
                    name: "To WebP",
                    fileType: .image,
                    rawText: "convert(to: webp)",
                    skipOptimisation: true
                ),
                SavedPipeline(
                    name: "Any",
                    rawText: "copyToClipboard"
                )
            ])
        )

        #expect(response.items.map(\.title).contains("Image Pipelines"))
        #expect(!response.items.map(\.title).contains("Audio Pipelines"))
        #expect(response.items.map(\.title).contains("All-File Pipelines"))

        let allFile = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image, .audio]),
            query: "all-file",
            provider: PipelineProviderStub(pipelines: [
                SavedPipeline(
                    name: "To WebP",
                    fileType: .image,
                    rawText: "convert(to: webp)",
                    skipOptimisation: true
                ),
                SavedPipeline(
                    name: "Any",
                    rawText: "copyToClipboard"
                )
            ])
        )

        #expect(allFile.items.map(\.title) == ["Any"])
        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((try #require(allFile.items.first?.arg)).utf8)
        )
        #expect(operation.inputs == ["/tmp/image.png"])
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
        #expect(item.subtitle == "Selected file · Steps Only · ⌃↩ Save Pipeline · ⌘L Syntax")
        #expect(item.icon == WorkflowIcon.inlinePipeline)
        #expect(item.text?.largetype?.contains("Steps\n\(steps)") == true)

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(
            pipeline: steps,
            isInline: true
        )))
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
        #expect(operation.action == .pipeline(PipelineRunRequest(
            pipeline: "removeAudio",
            isInline: true
        )))
    }

    @Test
    func newerBareKnownPipelineStepsCanRunInline() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.audio]),
            query: "normalize",
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Run inline pipeline")

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(
            pipeline: "normalize",
            isInline: true
        )))
    }

    @Test
    func inlineSyntaxGuidesUnknownStepNames() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "convertt(to: webp)",
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Unknown pipeline step convertt")
        #expect(item.subtitle.contains("Did you mean convert?"))
        #expect(item.valid == false)
        #expect(item.text?.largetype?.contains("Supported steps") == true)
    }

    @Test
    func inlineSyntaxGuidesUnknownOptions() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "convert(to: webp) ; hidden",
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Unknown pipeline option hidden")
        #expect(item.subtitle.contains("Use opt, hide"))
        #expect(item.valid == false)
    }

    @Test
    func inlineSyntaxGuidesUnbalancedParentheses() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "convert(to: webp",
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Close the pipeline step")
        #expect(item.subtitle.contains("Add the missing )"))
        #expect(item.valid == false)
    }

    @Test
    func inlineOptionParserIgnoresSemicolonsInsideStepValues() throws {
        let steps = #"runScript(code: "echo one; echo two") ; opt"#
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: steps,
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Run inline pipeline")

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(
            pipeline: #"runScript(code: "echo one; echo two")"#,
            isInline: true,
            optimizeFirst: true
        )))
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
        #expect(operation.action == .pipeline(PipelineRunRequest(
            pipeline: "convert(to: webp)",
            isInline: true
        )))
    }

    @Test
    func inlineOptionsNormalizeOptAndHide() throws {
        let response = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "convert(to: webp) ; opt hide",
            provider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.subtitle == "Selected file · Optimizes First · Hide Result · ⌃↩ Save Pipeline · ⌘L Syntax")

        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(operation.action == .pipeline(PipelineRunRequest(
            pipeline: "convert(to: webp)",
            isInline: true,
            optimizeFirst: true,
            hideResult: true
        )))
    }

    @Test
    func inlinePipelineCommandUsesWrittenStepsUnlessOptedIntoOptimise() throws {
        let builder = ClopCommandBuilder(discovery: StubDiscovery(
            diagnostics: ClopDiagnostics(
                found: true,
                path: "/tmp/Clop",
                source: "test",
                errors: []
            )
        ))
        let execution = ExecutionOptions(
            showClopUI: true,
            copyResult: false,
            output: .inPlace,
            backup: .trustClop,
            adaptiveOptimisation: nil,
            pdfDPI: nil,
            recursiveFolders: false
        )

        let stepsOnly = try builder.command(for: OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .pipeline(PipelineRunRequest(
                pipeline: "convert(to: webp)",
                isInline: true
            )),
            execution: execution
        ))
        #expect(stepsOnly.arguments == [
            "pipeline",
            "run",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--gui",
            "convert(to: webp)",
            "/tmp/image.png"
        ])

        let hiddenOptimizing = try builder.command(for: OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .pipeline(PipelineRunRequest(
                pipeline: "convert(to: webp)",
                isInline: true,
                optimizeFirst: true,
                hideResult: true
            )),
            execution: execution
        ))
        #expect(hiddenOptimizing.arguments == [
            "pipeline",
            "run",
            "--json",
            "--no-progress",
            "--skip-errors",
            "optimise -> convert(to: webp)",
            "/tmp/image.png"
        ])

        let normalized = try builder.command(for: OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .pipeline(PipelineRunRequest(
                pipeline: "optimize -> convert(to: webp)",
                isInline: true
            )),
            execution: execution
        ))
        #expect(normalized.arguments.contains("optimise -> convert(to: webp)"))
    }

    @Test
    func controlReturnSavesInlinePipelineFromPipelineMenu() throws {
        let provider = PipelineProviderStub(pipelines: [])
        let inline = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "convert(to: webp) ; opt hide",
            provider: provider
        )
        let nameStateJSON = try #require(inline.items.first?.mods?.control?.variables?[ActionMenu.menuStateVariable])

        let naming = PipelineMenu.response(
            stateJSON: nameStateJSON,
            query: "To WebP",
            provider: provider
        )
        let saveJSON = try #require(naming.items.first?.arg)

        _ = PipelineMenu.response(
            stateJSON: saveJSON,
            query: "",
            provider: provider
        )

        #expect(provider.added == PipelineAddRequest(
            name: "To WebP",
            steps: "convert(to: webp)",
            fileType: .image,
            optimizeFirst: true,
            hideResult: true
        ))
    }

    @Test
    func controlReturnDeletesSavedPipelineThroughConfirmation() throws {
        let provider = PipelineProviderStub()
        let list = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "",
            provider: provider
        )
        let pipeline = try #require(list.items.first { $0.title == "To WebP" })
        let confirmJSON = try #require(pipeline.mods?.control?.arg)
        let confirmation = PipelineMenu.response(
            stateJSON: confirmJSON,
            query: "",
            provider: provider
        )

        #expect(confirmation.items.map(\.title) == [
            "Delete Pipeline To WebP?",
            "Cancel"
        ])
        #expect(confirmation.items.first?.icon == WorkflowIcon.destructive)

        let deleteJSON = try #require(confirmation.items.first?.arg)
        _ = PipelineMenu.response(
            stateJSON: deleteJSON,
            query: "",
            provider: provider
        )
        #expect(provider.deleted == "To WebP")
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
            query: ":pipelines add To WebP => convert(to: webp) ; img opt hide",
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
            optimizeFirst: true,
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
        #expect(response.items[1].title == "AI pipeline prompt")
        #expect(response.items[1].autocomplete == ":pipelines prompt ")
        let image = try #require(response.items.first { $0.title == "Image Pipelines" })
        #expect(image.subtitle == "1 Saved Pipeline")
        let remove = try #require(response.items.last)
        #expect(remove.title == "Remove all saved pipelines")
        #expect(remove.subtitle == "4 Saved Pipelines in Clop")
        #expect(remove.icon == WorkflowIcon.destructive)
        #expect(image.text?.largetype?.contains("Pipeline add syntax") == true)
        #expect(image.text?.largetype?.contains("targetSize") == true)
        #expect(image.text?.largetype?.contains("copyToClipboard is a step") == true)
    }

    @Test
    func pipelinesConfigurationPromptBranchCopiesGeneratedPrompt() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines prompt shrink screenshots to webp under 500KB",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Copy AI pipeline prompt")
        #expect(item.subtitle == "Generate prompt from typed task · ⌘L Details")
        #expect(item.arg == "shrink screenshots to webp under 500KB")
        #expect(item.variables?[ActionMenu.requestKindVariable] == WorkflowRequestKind.pipelinePromptCopy.rawValue)
        #expect(item.mods?.command == nil)
        #expect(item.text?.largetype?.contains("It does not send anything to AI.") == true)
        #expect(item.text?.largetype?.contains("shrink screenshots to webp under 500KB") == true)
    }

    @Test
    func pipelinesConfigurationPromptGuideAsksForTask() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines prompt",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        #expect(response.items.first?.title == "Describe the pipeline task")
        #expect(response.items.first?.subtitle == "Type a task, e.g. resize videos to 1080p mp4 · ⌘L Details")
        #expect(response.items.first?.valid == false)
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
        let pipeline = try #require(response.items.dropFirst().first {
            $0.title == "To WebP"
        })
        #expect(pipeline.icon == WorkflowIcon.preset)
    }

    @Test
    func pipelinesConfigurationCanSearchForRemoveAllPipelines() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines remove",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        #expect(response.items.map(\.title).contains("Remove all saved pipelines"))
    }

    @Test
    func pipelinesConfigurationAddsFromBareNameAndStepsSyntax() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines New Pipeline => removeAudio",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Add Pipeline New Pipeline")
        #expect(item.subtitle == "All file types · Steps only · ⌘L Reference")

        let json = try #require(item.arg)
        let state = try JSONDecoder().decode(
            MenuState.self,
            from: Data(json.utf8)
        )
        let add = try #require(state.pipelineAction?.add)
        #expect(add == PipelineAddRequest(
            name: "New Pipeline",
            steps: "removeAudio"
        ))
    }

    @Test
    func pipelinesConfigurationGuidesInvalidPipelineSteps() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: ":pipelines New Pipeline => convertt(to: webp) ; img",
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Unknown pipeline step convertt")
        #expect(item.subtitle.contains("Did you mean convert?"))
        #expect(item.valid == false)
    }

    @Test
    func pipelineSyntaxGuidesObviousParameterMistakes() throws {
        let badScript = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: #"runScript(code: "echo hi -> cat")"#,
            provider: PipelineProviderStub()
        )
        #expect(badScript.items.first?.title == "Adjust the inline script")

        let badFactor = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "downscale(factor: 1.5)",
            provider: PipelineProviderStub()
        )
        #expect(badFactor.items.first?.title == "Use a downscale factor from 0.0 to 1.0")

        let badCrop = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "crop(location: sameFolder)",
            provider: PipelineProviderStub()
        )
        #expect(badCrop.items.first?.title == "Add a crop size")

        let badConvert = PipelineMenu.response(
            stateJSON: stateJSON(mediaKinds: [.image]),
            query: "convert(to: tga)",
            provider: PipelineProviderStub()
        )
        #expect(badConvert.items.first?.title == "Unknown conversion target tga")
    }

    @Test
    func pipelinesConfigurationIgnoresSemicolonsInsideStepValues() throws {
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let response = ConfigurationMenu.namespaceResponse(
            query: #":pipelines Script => runScript(code: "echo one; echo two") ; img opt"#,
            environment: environment,
            pipelineProvider: PipelineProviderStub()
        )

        let item = try #require(response.items.first)
        #expect(item.title == "Add Pipeline Script")
        #expect(item.subtitle == "Image · Optimizes first · ⌘L Reference")

        let state = try JSONDecoder().decode(
            MenuState.self,
            from: Data((item.arg ?? "").utf8)
        )
        #expect(state.pipelineAction?.add == PipelineAddRequest(
            name: "Script",
            steps: #"runScript(code: "echo one; echo two")"#,
            fileType: .image,
            optimizeFirst: true
        ))
    }

    @Test
    func pipelineProviderAddsSavedPipelinesAsStepsOnlyUnlessOptedIn() throws {
        let runner = CapturingPipelineRunner()
        let provider = ClopPipelineProvider(
            discovery: StubDiscovery(diagnostics: ClopDiagnostics(
                found: true,
                path: "/tmp/Clop",
                source: "test",
                errors: []
            )),
            runner: runner
        )

        try provider.addPipeline(PipelineAddRequest(
            name: "To WebP",
            steps: "optimize -> convert(to: webp)",
            fileType: .image
        ))
        try provider.addPipeline(PipelineAddRequest(
            name: "Small WebP",
            steps: "convert(to: webp)",
            fileType: .image,
            optimizeFirst: true
        ))

        #expect(runner.arguments[0] == [
            "pipeline",
            "add",
            "--file-type",
            "image",
            "--skip-optimisation",
            "To WebP",
            "optimise -> convert(to: webp)"
        ])
        #expect(runner.arguments[1] == [
            "pipeline",
            "add",
            "--file-type",
            "image",
            "Small WebP",
            "convert(to: webp)"
        ])
    }

    @Test
    func pipelineProviderGeneratesPromptWithTaskArgument() throws {
        let runner = CapturingPipelineRunner()
        runner.standardOutput = Data("PROMPT".utf8)
        let provider = ClopPipelineProvider(
            discovery: StubDiscovery(diagnostics: ClopDiagnostics(
                found: true,
                path: "/tmp/Clop",
                source: "test",
                errors: []
            )),
            runner: runner
        )

        let prompt = try provider.pipelinePrompt(task: "shrink screenshots")

        #expect(prompt == "PROMPT")
        #expect(runner.arguments == [[
            "pipeline",
            "prompt",
            "shrink screenshots"
        ]])
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
        #expect(response.items.first?.subtitle == "Use Name => steps ; img opt hide · ⌘L Reference")
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
        #expect(pipeline.icon == WorkflowIcon.preset)
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
        #expect(confirmation.items.first?.icon == WorkflowIcon.destructive)
        #expect(confirmation.items[1].arg == ":pipelines image")
    }

    @Test
    func pipelinesConfigurationRemovesAllPipelinesThroughConfirmation() throws {
        let provider = PipelineProviderStub()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: try makeTemporaryDirectory().path
        ])
        let list = ConfigurationMenu.namespaceResponse(
            query: ":pipelines",
            environment: environment,
            pipelineProvider: provider
        )
        let remove = try #require(list.items.first {
            $0.title == "Remove all saved pipelines"
        })
        #expect(remove.icon == WorkflowIcon.destructive)
        let confirmation = ConfigurationMenu.response(
            stateJSON: try #require(remove.arg),
            query: "",
            environment: environment,
            pipelineProvider: provider
        )

        #expect(confirmation.items.first?.title == "Remove all 4 saved pipelines?")
        let deleteJSON = try #require(confirmation.items.first?.arg)
        _ = ConfigurationMenu.response(
            stateJSON: deleteJSON,
            query: "",
            environment: environment,
            pipelineProvider: provider
        )

        #expect(provider.deletedNames == ["To WebP", "To GIF", "To MP3", "Any"])
        #expect(provider.pipelines.isEmpty)
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

private final class PipelineProviderStub: ClopPipelineProviding {
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
    var added: PipelineAddRequest?
    var deleted: String?
    var deletedNames = [String]()

    init(pipelines: [SavedPipeline]? = nil) {
        if let pipelines {
            self.pipelines = pipelines
        }
    }

    func listPipelines() throws -> [SavedPipeline] {
        pipelines
    }

    func pipelinePrompt(task: String) throws -> String {
        "Prompt for \(task)"
    }

    func addPipeline(_ request: PipelineAddRequest) throws {
        added = request
        if request.replace {
            pipelines.removeAll {
                $0.name.caseInsensitiveCompare(request.name) == .orderedSame
            }
        }
        pipelines.append(SavedPipeline(
            name: request.name,
            fileType: request.fileType,
            rawText: request.steps,
            skipOptimisation: !request.optimizeFirst,
            hideResult: request.hideResult
        ))
    }

    func deletePipeline(named name: String) throws {
        deleted = name
        deletedNames.append(name)
        pipelines.removeAll {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}

private final class CapturingPipelineRunner: ClopProcessRunning {
    var arguments = [[String]]()
    var standardOutput = Data()

    func run(_ command: ClopCommand) throws -> ClopProcessResult {
        arguments.append(command.arguments)
        return ClopProcessResult(
            terminationStatus: 0,
            standardOutput: standardOutput,
            standardError: Data()
        )
    }
}
