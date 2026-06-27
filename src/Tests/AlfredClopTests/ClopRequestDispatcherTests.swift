import Foundation
import Testing
@testable import AlfredClop

struct ClopRequestDispatcherTests {
    @Test
    func versionedInputAndRouteModelsRoundTrip() throws {
        let request = ClopRequest(
            version: 1,
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
    func currentContractRequestOmitsVersionWhenEncoded() throws {
        let request = ClopRequest(
            input: .clipboard,
            route: .menu(action: nil)
        )

        let json = try JSONOutput.string(for: request, prettyPrinted: false)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any]
        )

        #expect(object["version"] == nil)
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
            finder: DispatcherFinder(),
            environment: try dispatcherEnvironment()
        )

        #expect(response.items.map(\.title).contains("Optimize"))
        #expect(response.items.first?.subtitle.hasPrefix("Passed file ·") == true)
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
            finder: DispatcherFinder(),
            environment: try dispatcherEnvironment()
        )

        #expect(response.items.first?.title == "Type crop or resize parameters")
    }

    @Test
    func cropPDFMenuRouteOpensCropPDFBranches() throws {
        let file = try temporaryFile(named: "document.pdf")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .menu(action: .cropPDF)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: try dispatcherEnvironment()
        )

        #expect(response.items.map(\.title).prefix(3) == [
            "Custom Ratio / Resolution",
            "Apple Device",
            "Paper Size"
        ])
    }

    @Test
    func clipboardHistoryFallbackAppliesToDirectSubmenus() throws {
        let file = try temporaryFile(named: "history image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let history = StubClipboardHistoryReader([.files([file.path])])
        let request = ClopRequest(
            input: .clipboard,
            route: .menu(action: .crop)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(for: request, prettyPrinted: false),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            collector: InputCollector(clipboardHistory: history),
            environment: Environment(values: [
                "recoverClipboardHistory": "true"
            ])
        )

        #expect(response.items.first?.title == "Type crop or resize parameters")
        #expect(response.items.contains {
            $0.subtitle.hasPrefix("History · file ·")
        })
        #expect(history.makeReaderCallCount == 1)
    }

    @Test
    func headlessClipboardExecutionNeverConsultsHistory() throws {
        let file = try temporaryFile(named: "history image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let history = StubClipboardHistoryReader([.files([file.path])])
        let request = ClopRequest(
            input: .clipboard,
            route: .execute(action: .optimise(aggressive: false))
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(for: request, prettyPrinted: false),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            collector: InputCollector(clipboardHistory: history),
            environment: Environment(values: [
                "recoverClipboardHistory": "true"
            ])
        )

        #expect(response.items.first?.title == "No supported clipboard content")
        #expect(history.makeReaderCallCount == 0)
    }

    @Test
    func menuHandoffKeepsRequestInVariableAndClearsVisibleArgument() throws {
        let publicRequest = """
        crop:

        /tmp/first "quoted" image.png
        /tmp/second image.png
        """
        let handoffJSON = try #require(
            AlfredClopCommand.menuHandoffJSON(publicRequest: publicRequest)
        )
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(handoffJSON.utf8))
                as? [String: Any]
        )
        let workflow = try #require(
            root["alfredworkflow"] as? [String: Any]
        )
        let variables = try #require(
            workflow["variables"] as? [String: String]
        )

        #expect(workflow["arg"] as? String == "")
        #expect(variables[ActionMenu.publicRequestVariable] == publicRequest)
        #expect(variables["alfred_clop_public_route"] == "menu")
    }

    @Test
    func configurationHandoffPrefillsNamespaceAndPreservesRequest() throws {
        let publicRequest = """
        menu: Configuration

        clipboard
        """
        let handoffJSON = try #require(
            AlfredClopCommand.menuHandoffJSON(publicRequest: publicRequest)
        )
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(handoffJSON.utf8))
                as? [String: Any]
        )
        let workflow = try #require(
            root["alfredworkflow"] as? [String: Any]
        )
        let variables = try #require(
            workflow["variables"] as? [String: String]
        )

        #expect(workflow["arg"] as? String == ":")
        #expect(variables[ActionMenu.publicRequestVariable] == publicRequest)
    }

    @Test
    func configurationRouteUsesQueryNamespaceAndCanReturnToActions() throws {
        let file = try temporaryFile(named: "image.png")
        defer {
            try? FileManager.default.removeItem(
                at: file.deletingLastPathComponent()
            )
        }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .configuration
        )
        let requestJSON = try JSONOutput.string(
            for: request,
            prettyPrinted: false
        )

        let configuration = ClopRequestDispatcher.response(
            requestJSON: requestJSON,
            query: ":",
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: try dispatcherEnvironment()
        )
        let actions = ClopRequestDispatcher.response(
            requestJSON: requestJSON,
            query: "",
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: try dispatcherEnvironment()
        )

        #expect(configuration.items.first?.title == "Output Template")
        #expect(actions.items.contains { $0.title == "Optimize" })
    }

    @Test(arguments: [
        ("image.png", ClopAction.convertImage),
        ("video.mp4", ClopAction.convertVideo),
        ("audio.mp3", ClopAction.convertAudio)
    ])
    func mediaSpecificConversionRoutesOpenTheirFormatMenus(
        filename: String,
        action: ClopAction
    ) throws {
        let file = try temporaryFile(named: filename)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .menu(action: action)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: try dispatcherEnvironment()
        )

        #expect(response.items.first?.title.hasPrefix("Convert to ") == true)
        #expect(response.items.first?.valid == true)
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
    func mediaSpecificOptimizeExecutionFiltersMixedInputs() throws {
        let image = try temporaryFile(named: "image.png")
        let video = try temporaryFile(named: "movie with spaces.mp4")
        defer { try? FileManager.default.removeItem(at: image.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: video.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(
                items: [image.path, video.path],
                extractText: false
            ),
            route: .execute(action: .optimiseMedia(OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(
                    playbackSpeed: 2
                ))
            )))
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Optimization complete")
        #expect(runner.command?.arguments == [
            "optimise",
            "video",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--playback-speed-factor",
            "2",
            "--gui",
            video.path
        ])
    }

    @Test
    func mediaSpecificOptimizeExecutionPreservesAmbiguousMixedInputs() throws {
        let imageURL = "https://example.com/photo.jpg"
        let ambiguousURL = "https://example.com/download"
        let request = ClopRequest(
            input: .explicit(
                items: [imageURL, ambiguousURL],
                extractText: false
            ),
            route: .execute(action: .optimiseMedia(OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(removeAudio: true))
            )))
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Optimization complete")
        #expect(runner.command?.arguments == [
            "optimise",
            "video",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--remove-audio",
            "--gui",
            imageURL,
            ambiguousURL
        ])
    }

    @Test
    func executeRouteCanOverridePreservationForHeadlessModifiers() throws {
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
                "preserveOriginal": "true"
            ]),
            builder: dispatcherBuilder(),
            runner: runner,
            preserveOriginalOverride: false
        )

        #expect(response.items.first?.title == "Optimization complete")
        #expect(runner.command?.arguments.contains("--output") == false)
        #expect(runner.command?.arguments.contains("%P/%f-clop") == false)
    }

    @Test
    func executeRouteOutputTemplateOverrideForcesConfiguredTemplate() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let settings = try makeTemporaryDirectory()
        try PresetStore(
            fileURL: settings.appendingPathComponent("settings.json")
        ).persist(SettingsDocument(outputTemplate: "%P/%f-custom"))
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(
                action: .optimise(aggressive: false),
                overrides: ExecutionOverrides(output: .template)
            )
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
                PresetStore.workflowDataEnvironmentKey: settings.path,
                "preserveOriginal": "false"
            ]),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Optimization complete")
        #expect(runner.command?.arguments.contains("--output") == true)
        #expect(runner.command?.arguments.contains("%P/%f-custom") == true)
    }

    @Test
    func executeRouteCustomOutputTemplateOverrideIsOneOff() throws {
        let file = try temporaryFile(named: "audio.wav")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(
                action: .convert(ConversionChoice(media: .audio, format: "mp3")),
                overrides: ExecutionOverrides(
                    output: .customTemplate("%P/%f-podcast")
                )
            )
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: Environment(values: ["preserveOriginal": "false"]),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Conversion complete")
        #expect(runner.command?.arguments.contains("--output") == true)
        #expect(runner.command?.arguments.contains("%P/%f-podcast") == true)
    }

    @Test
    func executeRouteInlinePipelineOutputOverridePrependsCopyStep() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(
                action: .pipeline(PipelineRunRequest(
                    pipeline: "convert(to: webp)",
                    isInline: true,
                    optimizeFirst: true
                )),
                overrides: ExecutionOverrides(output: .customTemplate("%P/%f-pipe"))
            )
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: Environment(values: ["preserveOriginal": "false"]),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Pipeline complete")
        #expect(runner.command?.arguments.contains(
            #"copy(to: "%P/%f-pipe") -> optimise -> convert(to: webp)"#
        ) == true)
    }

    @Test
    func executeRouteSavedPipelineOutputOverrideReadsSavedSteps() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(
                action: .pipeline(PipelineRunRequest(name: "To WebP")),
                overrides: ExecutionOverrides(output: .template)
            )
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            builder: dispatcherBuilder(),
            runner: runner,
            pipelineProvider: DispatcherPipelineProvider(pipelines: [
                SavedPipeline(
                    name: "To WebP",
                    rawText: "uploadWith(app: dropshare) -> delete",
                    skipOptimisation: false,
                    hideResult: true
                )
            ])
        )

        #expect(response.items.first?.title == "Pipeline complete")
        #expect(runner.command?.arguments.contains(
            #"copy(to: "%P/%f-clop") -> optimise -> uploadWith(app: dropshare) -> delete"#
        ) == true)
        #expect(runner.command?.arguments.contains("--hide-result") == true)
    }

    @Test
    func executeRouteSavedPipelineOutputOverrideReportsMissingPipeline() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(
                action: .pipeline(PipelineRunRequest(name: "Missing")),
                overrides: ExecutionOverrides(output: .template)
            )
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            builder: dispatcherBuilder(),
            runner: runner,
            pipelineProvider: DispatcherPipelineProvider(pipelines: [])
        )

        #expect(response.items.first?.title == "Unable to prepare Pipeline")
        #expect(response.items.first?.subtitle == "Saved pipeline Missing was not found.")
        #expect(runner.command == nil)
    }

    @Test
    func stripMetadataRejectsOutputOverridesBeforeLaunchingClop() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(
                action: .stripMetadata,
                overrides: ExecutionOverrides(output: .disabled)
            )
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Output override not supported")
        #expect(runner.command == nil)
    }

    @Test
    func conversionMismatchIsRejectedBeforeLaunchingClop() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(action: .convert(ConversionChoice(
                media: .audio,
                format: "mp3"
            )))
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Conversion does not support this input")
        #expect(response.items.first?.subtitle == "MP3 conversion requires audio input.")
        #expect(runner.command == nil)
    }

    @Test
    func headlessExecutionUsesOnlyConfiguredSettingsLocation() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let root = try makeTemporaryDirectory()
        let defaultDirectory = root.appendingPathComponent("Default")
        let configured = root.appendingPathComponent("Configured")
        try PresetStore(
            fileURL: defaultDirectory.appendingPathComponent("settings.json")
        ).persist(SettingsDocument(outputTemplate: "%P/%f-default"))
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: defaultDirectory.path,
            PresetStore.configuredPathEnvironmentKey: configured.path,
            "preserveOriginal": "true",
            "showClopUI": "false",
            "errorNotifications": "true"
        ])
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(action: .optimise(aggressive: false))
        )
        let json = try JSONOutput.string(for: request, prettyPrinted: false)
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: json,
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: environment,
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Optimization complete")
        #expect(runner.command?.arguments.contains("%P/%f-clop") == true)
        #expect(runner.command?.arguments.contains("%P/%f-default") == false)
        #expect(ClopRequestDispatcher.quietFeedback(
            requestJSON: json,
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: environment,
            builder: dispatcherBuilder(),
            runner: CapturingDispatcherRunner()
        ) == "Optimization complete: Clop processed 1 file.")
    }

    @Test
    func publicTextOnlySuccessNotifiesEvenWhenClopUIIsEnabled() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let environment = try dispatcherEnvironment()
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(action: .stripMetadata)
        )

        let feedback = ClopRequestDispatcher.quietFeedback(
            requestJSON: try JSONOutput.string(for: request, prettyPrinted: false),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: environment,
            builder: dispatcherBuilder(),
            runner: CapturingDispatcherRunner()
        )

        #expect(feedback == "Metadata removed: Clop processed 1 file.")
    }

    @Test
    func aggressiveExecuteRouteUsesOptimizeCapabilityWithoutMenuItem() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(action: .optimise(aggressive: true))
        )
        let runner = CapturingDispatcherRunner()

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(response.items.first?.title == "Aggressive optimization complete")
        #expect(runner.command?.arguments.contains("--aggressive") == true)
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

        #expect(response.items.map(\.title) == ["No Finder selection"])
    }

    @Test
    func clipboardFolderWithoutSupportedContentShowsVisibleError() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("notes".utf8).write(
            to: directory.appendingPathComponent("notes.txt")
        )
        let request = ClopRequest(
            input: .clipboard,
            route: .menu(action: nil)
        )

        let response = ClopRequestDispatcher.response(
            requestJSON: try JSONOutput.string(
                for: request,
                prettyPrinted: false
            ),
            clipboard: DispatcherClipboard(urls: [directory]),
            finder: DispatcherFinder()
        )

        #expect(response.items.map(\.title) == [
            "No supported clipboard content"
        ])
        #expect(response.items[0].subtitle == "Copy a supported file, folder, URL, or image and try again.")
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
    func missingRequestVersionUsesCurrentContract() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let json = """
        {
          "input": {"source": "explicit", "items": ["\(file.path)"]},
          "route": {"type": "menu"}
        }
        """

        let response = ClopRequestDispatcher.response(
            requestJSON: json,
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder()
        )

        #expect(response.items.map(\.title).contains("Optimize"))
    }

    @Test
    func nullRequestVersionIsAVisibleDecodingError() {
        let json = """
        {
          "version": null,
          "input": {"source": "clipboard"},
          "route": {"type": "menu"}
        }
        """

        let response = ClopRequestDispatcher.response(
            requestJSON: json,
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder()
        )

        #expect(response.items.first?.title == "Invalid Clop request")
    }

    @Test
    func dndSuppressesQuietFailureFeedbackOnly() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let request = ClopRequest(
            input: .explicit(items: [file.path], extractText: false),
            route: .execute(action: .optimise(aggressive: false))
        )
        let json = try JSONOutput.string(for: request, prettyPrinted: false)
        let runner = FailingDispatcherRunner()

        let quiet = ClopRequestDispatcher.quietFeedback(
            requestJSON: json,
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: Environment(values: ["dnd": "true"]),
            builder: dispatcherBuilder(),
            runner: runner
        )
        let interactive = ClopRequestDispatcher.response(
            requestJSON: json,
            clipboard: DispatcherClipboard(),
            finder: DispatcherFinder(),
            environment: Environment(values: ["dnd": "true"]),
            builder: dispatcherBuilder(),
            runner: runner
        )

        #expect(quiet == nil)
        #expect(interactive.items.first?.title == "Clop operation failed")
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
            "Crop / Resize",
            "Downscale",
            "Convert Image",
            "Convert Video",
            "Convert Audio"
        ])
        #expect(response.items[1].subtitle.contains("Image, video, or PDF only"))
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

private struct DispatcherPipelineProvider: ClopPipelineProviding {
    var pipelines: [SavedPipeline]

    func listPipelines() throws -> [SavedPipeline] {
        pipelines
    }

    func pipelinePrompt(task: String) throws -> String {
        "Prompt"
    }

    func addPipeline(_ request: PipelineAddRequest) throws {}

    func deletePipeline(named name: String) throws {}
}

private struct FailingDispatcherRunner: ClopProcessRunning {
    func run(_ command: ClopCommand) throws -> ClopProcessResult {
        ClopProcessResult(
            terminationStatus: 2,
            standardOutput: Data(),
            standardError: Data("Failed".utf8)
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

private func dispatcherEnvironment() throws -> Environment {
    let directory = try makeTemporaryDirectory()
    return Environment(values: [
        PresetStore.workflowDataEnvironmentKey: directory.path
    ])
}
