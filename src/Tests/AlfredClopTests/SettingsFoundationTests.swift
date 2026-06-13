import Foundation
import Testing
@testable import AlfredClop

struct SettingsFoundationTests {
    @Test
    func outputTemplateRejectsEmptyAndUnknownTokens() {
        #expect(OutputTemplateValidator.validate(" ") == .empty)
        #expect(
            OutputTemplateValidator.validate("%P/%f-%Q")
                == .unsupportedToken("%Q")
        )
        #expect(OutputTemplateValidator.validate("%P/%f-clop") == nil)
        #expect(OutputTemplateValidator.validate("%P/%f.%e") == .automaticExtension)
        #expect(
            OutputTemplateValidator.validate("%P/%f-clop.png")
                == .explicitExtension(".png")
        )
        #expect(
            OutputTemplateValidator.validate("%P")
                == .missingFilename
        )
        #expect(
            OutputTemplateValidator.validate("%P/")
                == .missingFilename
        )
        #expect(
            OutputTemplateValidator.validate("%P/processed")
                == .missingVariableFilename
        )
        #expect(
            OutputTemplateValidator.validate("%f-clop")
                == .unpredictableLocation
        )
        #expect(OutputTemplateValidator.validate("%P/%f-%z-%s-%x-%q") == nil)
        #expect(OutputTemplateValidator.validate("%P/%z") == nil)
    }

    @Test
    func outputPlanningProtectsDuplicatesAndSources() throws {
        let firstDirectory = try makeTemporaryDirectory()
        let secondDirectory = try makeTemporaryDirectory()
        let first = firstDirectory.appendingPathComponent("same.png")
        let second = secondDirectory.appendingPathComponent("same.png")
        try Data().write(to: first)
        try Data().write(to: second)

        #expect(throws: OutputTemplateError.duplicateOutput(
            "/tmp/same-clop.png"
        )) {
            try OutputTemplateValidator.plan(
                template: "/tmp/%f-clop",
                inputs: [first.path, second.path]
            )
        }

        let existing = firstDirectory.appendingPathComponent("same-clop.png")
        try Data().write(to: existing)
        #expect(throws: OutputTemplateError.sourceCollision(first.path)) {
            try OutputTemplateValidator.plan(
                template: "%P/%f",
                inputs: [first.path]
            )
        }
    }

    @Test
    func outputPlanningAddsNextAvailableNumericSuffix() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try Data().write(to: source)
        try Data().write(
            to: directory.appendingPathComponent("photo-clop.png")
        )
        try Data().write(
            to: directory.appendingPathComponent("photo-clop-2.png")
        )

        let plan = try OutputTemplateValidator.plan(
            template: "%P/%f-clop",
            inputs: [source.path]
        )

        #expect(plan.template == "%P/%f-clop-3")
        #expect(plan.outputPaths == [
            directory.appendingPathComponent("photo-clop-3.png").path
        ])
    }

    @Test
    func tildeExpandsForPreviewAndPlanning() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try Data().write(to: source)

        let plan = try OutputTemplateValidator.plan(
            template: "~/Clop Test/%f-small",
            inputs: [source.path]
        )

        #expect(plan.template == "\(NSHomeDirectory())/Clop Test/%f-small")
        #expect(plan.outputPaths == [
            "\(NSHomeDirectory())/Clop Test/photo-small.png"
        ])
        #expect(
            OutputTemplateValidator.preview(
                template: "~/Clop Test/%f",
                homeDirectory: "/Users/example"
            ) == "/Users/example/Clop Test/Photo.png"
        )
    }

    @Test
    func environmentResolvesAllStaticExecutionSettings() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path,
            "preserveOriginal": "true",
            "defaultOptimisation": "aggressive",
            "showClopUI": "false",
            "copyResult": "true",
            "recursiveFolders": "true",
            "completionNotifications": "true",
            "errorNotifications": "false",
            "cacheRetention": "15"
        ])
        let execution = try environment.resolvedExecutionOptions()

        #expect(environment.aggressiveByDefault)
        #expect(environment.completionNotifications)
        #expect(!environment.errorNotifications)
        #expect(environment.clipboardImageRetentionDays == 15)
        #expect(!execution.showClopUI)
        #expect(execution.copyResult)
        #expect(execution.recursiveFolders)
        #expect(execution.output == .sameFolder(template: "%P/%f-clop"))
        #expect(Environment(values: [:]).completionNotifications)
    }

    @Test
    func optimizeAndCropExposeConfiguredDefaultInversions() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path,
            "preserveOriginal": "true",
            "defaultOptimisation": "aggressive"
        ])
        let optimize = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/photo.png"],
                mediaKinds: [.image]
            ),
            query: "optimize",
            environment: environment
        )
        let optimizeItem = try #require(optimize.items.first)
        let normal = try operation(optimizeItem.arg)
        let command = try operation(optimizeItem.mods?.command?.arg)
        let shift = try operation(optimizeItem.mods?.shift?.arg)

        #expect(normal.action == .optimise(aggressive: true))
        #expect(command.action == .optimise(aggressive: false))
        #expect(normal.execution.output == .sameFolder(template: "%P/%f-clop"))
        #expect(shift.execution.output == .inPlace)

        let request = ParameterStepRequest(
            action: .crop,
            inputs: ["/tmp/photo.png"]
        )
        let crop = CropParameterMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.crop(request),
                prettyPrinted: false
            ),
            query: "16:9",
            environment: environment
        )
        let cropItem = try #require(crop.items.first)
        #expect(cropItem.mods?.option != nil)
        #expect(cropItem.mods?.commandOptionShift != nil)
        let smart = try operation(cropItem.mods?.option?.arg)
        #expect(smart.action == .crop(
            size: "16:9",
            smartCrop: true,
            longEdge: false
        ))
    }

    @Test
    func configurationShowsIndependentConditionalResetActions() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let store = try PresetStore(environment: environment)
        _ = try store.save(.crop(CropActionPreset(
            size: try #require(CropSizeParser.parse("w128"))
        )))
        try store.updateOutputTemplate("%P/Processed/%f")
        let menu = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(),
                prettyPrinted: false
            ),
            query: "",
            environment: environment
        )
        let reset = try #require(menu.items.first {
            $0.title == "Reset output template"
        })
        let presets = try #require(menu.items.first {
            $0.title == "Remove all action presets"
        })
        #expect(reset.mods == nil)
        #expect(presets.subtitle.contains("1 saved preset"))

        let confirmation = ConfigurationMenu.response(
            stateJSON: try #require(
                reset.variables?[ActionMenu.menuStateVariable]
            ),
            query: "",
            environment: environment
        )
        #expect(
            confirmation.items.first?.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.configurationMutation.rawValue
        )
        #expect(ConfigurationMenu.quietMutationFeedback(
            stateJSON: try #require(confirmation.items.first?.arg),
            environment: environment
        ) == "Output template reset")

        let document = try store.load()
        #expect(document.outputTemplate == "%P/%f-clop")
        #expect(document.presets.count == 1)

        let afterReset = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(),
                prettyPrinted: false
            ),
            query: "",
            environment: environment
        )
        #expect(!afterReset.items.contains {
            $0.title == "Reset output template"
        })
        #expect(afterReset.items.contains {
            $0.title == "Remove all action presets"
        })

        let presetConfirmation = ConfigurationMenu.response(
            stateJSON: try #require(
                presets.variables?[ActionMenu.menuStateVariable]
            ),
            query: "",
            environment: environment
        )
        #expect(ConfigurationMenu.quietMutationFeedback(
            stateJSON: try #require(presetConfirmation.items.first?.arg),
            environment: environment
        ) == "Removed 1 action preset")
        let afterPresetRemoval = try store.load()
        #expect(afterPresetRemoval.outputTemplate == "%P/%f-clop")
        #expect(afterPresetRemoval.presets.isEmpty)
    }

    @Test
    func outputTemplateMenuOffersFriendlyChoicesAndLargeTypeReference() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let stateJSON = try JSONOutput.string(
            for: MenuState.configuration(mode: .configurationOutputTemplate),
            prettyPrinted: false
        )
        let configuration = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(),
                prettyPrinted: false
            ),
            query: "",
            environment: environment
        )
        #expect(!configuration.items.contains {
            $0.title == "Reset output template"
                || $0.title == "Remove all action presets"
        })

        let empty = ConfigurationMenu.response(
            stateJSON: stateJSON,
            query: "",
            environment: environment
        )
        #expect(empty.items.map(\.title) == [
            "Type a suffix, prefix, or advanced template"
        ])
        #expect(empty.items[0].subtitle.contains("Current: %P/%f-clop"))
        #expect(empty.items[0].subtitle.contains("⌘L"))
        let reference = try #require(empty.items[0].text?.largetype)
        #expect(reference.contains("%P  Source folder"))
        #expect(reference.contains("%i  Incrementing number"))
        #expect(!reference.contains("%e"))
        #expect(!reference.contains("%z"))

        let friendly = ConfigurationMenu.response(
            stateJSON: stateJSON,
            query: "optimized",
            environment: environment
        )
        #expect(friendly.items.map(\.title) == [
            "Add “-optimized”",
            "Add “optimized-”"
        ])
        #expect(friendly.items[0].subtitle.contains("Photo-optimized.png"))
        #expect(friendly.items[1].subtitle.contains("optimized-Photo.png"))
        #expect(friendly.items[0].subtitle.contains("Original folder/"))
        #expect(!friendly.items[0].subtitle.contains("~/Pictures"))
        #expect(friendly.items.allSatisfy {
            $0.subtitle.contains("⌘L")
                && $0.text?.largetype == reference
        })

        let advanced = ConfigurationMenu.response(
            stateJSON: stateJSON,
            query: "%P/Processed/%y-%m-%d-%f",
            environment: environment
        )
        #expect(advanced.items.count == 1)
        #expect(advanced.items[0].valid)
        #expect(advanced.items[0].subtitle.contains("%P/Processed"))
    }

    @Test
    func outputTemplateMenuValidatesAdvancedInputImmediately() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let stateJSON = try JSONOutput.string(
            for: MenuState.configuration(mode: .configurationOutputTemplate),
            prettyPrinted: false
        )

        for (input, message) in [
            ("%P", "filename"),
            ("%P/", "ends with a folder"),
            ("%f-clop", "predictable"),
            ("%P/%f.%e", "automatically"),
            ("%P/%f-clop.png", "automatically"),
            ("~someone/%f", "not supported")
        ] {
            let response = ConfigurationMenu.response(
                stateJSON: stateJSON,
                query: input,
                environment: environment
            )
            #expect(response.items.count == 1)
            #expect(!response.items[0].valid)
            #expect(response.items[0].subtitle.contains(message))
            #expect(response.items[0].subtitle.contains("⌘L"))
            #expect(
                response.items[0].text?.largetype?
                    .contains("%P  Source folder") == true
            )
        }

        let advancedTokens = ConfigurationMenu.response(
            stateJSON: stateJSON,
            query: "%P/%f-%z-%s-%x-%q",
            environment: environment
        )
        #expect(advancedTokens.items.first?.valid == true)

        let literalExtension = ConfigurationMenu.response(
            stateJSON: stateJSON,
            query: "optimized.png",
            environment: environment
        )
        #expect(literalExtension.items.first?.valid == false)
        #expect(literalExtension.items.first?.subtitle.contains("automatically") == true)
    }

    @Test
    func configurationMutationNotificationsFollowCompletionSetting() throws {
        let directory = try makeTemporaryDirectory()
        let enabled = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let disabled = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path,
            "completionNotifications": "false"
        ])
        let stateJSON = try JSONOutput.string(
            for: MenuState.configuration(
                mode: .configurationSaveOutput,
                value: "%P/%f-edited"
            ),
            prettyPrinted: false
        )

        #expect(ConfigurationMenu.quietMutationFeedback(
            stateJSON: stateJSON,
            environment: enabled
        ) == "Output template updated")
        #expect(ConfigurationMenu.quietMutationFeedback(
            stateJSON: stateJSON,
            environment: disabled
        ) == nil)

        let action = ConfigurationMenu.actionItem
        #expect(
            action.subtitle
                == "Output template, presets, and maintenance · ⌘⏎ Workflow settings"
        )
        #expect(
            action.mods?.command?.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.workflowSettings.rawValue
        )
    }

    @Test
    func cacheCleanupCountsOnlyWorkflowClipboardImages() throws {
        let directory = try makeTemporaryDirectory()
        let first = directory.appendingPathComponent("clipboard-one.png")
        let second = directory.appendingPathComponent("clipboard-two.tiff")
        let unrelated = directory.appendingPathComponent("other.png")
        try Data(repeating: 1, count: 10).write(to: first)
        try Data(repeating: 2, count: 20).write(to: second)
        try Data(repeating: 3, count: 40).write(to: unrelated)
        let cache = ClipboardImageCache(directories: [directory])

        #expect(cache.summary() == ClipboardImageCacheSummary(
            fileCount: 2,
            byteCount: 30
        ))
        #expect(cache.removeAll().fileCount == 2)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func operation(_ json: String?) throws -> OperationRequest {
        try JSONDecoder().decode(
            OperationRequest.self,
            from: Data(try #require(json).utf8)
        )
    }
}
