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
            OutputTemplateValidator.validate("%P/%f")
                == .sourceCollision("%P/%f")
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
    func conversionOutputPlanningUsesTheTargetExtension() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try Data().write(to: source)
        try Data().write(
            to: directory.appendingPathComponent("photo-clop.webp")
        )

        let plan = try OutputTemplateValidator.plan(
            template: "%P/%f-clop",
            inputs: [source.path],
            outputExtension: "webp"
        )

        #expect(plan.template == "%P/%f-clop-2")
        #expect(plan.outputPaths == [
            directory.appendingPathComponent("photo-clop-2.webp").path
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
        let menuRequest = try JSONDecoder().decode(
            ParameterStepRequest.self,
            from: Data((try #require(optimizeItem.arg)).utf8)
        )
        let command = try operation(optimizeItem.mods?.command?.arg)
        let option = try operation(optimizeItem.mods?.option?.arg)
        let shift = try operation(optimizeItem.mods?.shift?.arg)

        #expect(menuRequest.action == .optimise)
        #expect(command.action == .optimise(aggressive: true))
        #expect(option.action == .optimise(aggressive: false))
        #expect(command.execution.output == .sameFolder(template: "%P/%f-clop"))
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
            query: "16:9 sc",
            environment: environment
        )
        let cropItem = try #require(crop.items.first)
        #expect(cropItem.mods?.option == nil)
        #expect(cropItem.mods?.commandOptionShift == nil)
        let smart = try operation(cropItem.arg)
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
            $0.title == "Manage action presets"
        })
        #expect(reset.mods == nil)
        #expect(presets.subtitle.contains("1 Saved Preset"))

        let confirmation = ConfigurationMenu.response(
            stateJSON: try #require(
                reset.variables?[ActionMenu.menuStateVariable]
            ),
            query: "",
            environment: environment
        )
        #expect(
            confirmation.items.first?.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.parameterStep.rawValue
        )
        #expect(
            confirmation.items.first?.mods?.command?
                .variables?[ActionMenu.requestKindVariable]
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
            $0.title == "Manage action presets"
        })

        let presetMenu = ConfigurationMenu.namespaceResponse(
            query: ":presets",
            environment: environment
        )
        let removeAll = try #require(presetMenu.items.first {
            $0.title == "Remove all action presets"
        })
        let presetConfirmation = ConfigurationMenu.response(
            stateJSON: try #require(
                removeAll.variables?[ActionMenu.menuStateVariable]
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
            "Photo.png → Original folder/Photo-optimized.png",
            "Photo.png → Original folder/optimized-Photo.png"
        ])
        #expect(friendly.items.allSatisfy {
            $0.subtitle == "↩ Apply · ⌘↩ Apply and close · ⌘L Reference"
                && $0.text?.largetype == reference
        })

        let advanced = ConfigurationMenu.response(
            stateJSON: stateJSON,
            query: "%P/Processed/%y-%m-%d-%f",
            environment: environment
        )
        #expect(advanced.items.count == 1)
        #expect(advanced.items[0].valid)
        #expect(advanced.items[0].title.contains("Original folder/Processed"))
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
            ("%f-clop", "predictable"),
            ("%P/%f.%e", "automatically"),
            ("%P/%f-clop.png", "automatically"),
            ("%P/%f", "overwrite the original file"),
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

        for (input, subtitle) in [
            ("%P", "Try %P/%f-clop · ⌘L Reference"),
            ("%P/", "Try %P/%f-clop · ⌘L Reference"),
            ("~", "Try ~/%f-clop · ⌘L Reference")
        ] {
            let response = ConfigurationMenu.response(
                stateJSON: stateJSON,
                query: input,
                environment: environment
            )
            #expect(response.items.first?.title == "Add a filename after the folder")
            #expect(response.items.first?.subtitle == subtitle)
        }

        let unsupportedTilde = ConfigurationMenu.response(
            stateJSON: stateJSON,
            query: "~desk",
            environment: environment
        )
        #expect(unsupportedTilde.items.first?.title == "Use ~/ for your home folder")
        #expect(unsupportedTilde.items.first?.subtitle == "Example: ~/Desktop/%f · ⌘L Reference")

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

        let menu = ConfigurationMenu.namespaceResponse(
            query: ":",
            environment: enabled
        )
        let settings = try #require(menu.items.first {
            $0.title == "Workflow Settings"
        })
        let filePath = directory.appendingPathComponent("settings.json").path
        #expect(
            settings.subtitle
                == "↩ Open Workflow Configuration · ⌘↩ Reveal Settings Folder"
        )
        #expect(settings.type == "file")
        #expect(settings.arg == filePath)
        #expect(settings.quickLookURL == filePath)
        #expect(settings.action?.file == .single(filePath))
        #expect(settings.autocomplete == ":settings")
        #expect(
            settings.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.workflowSettings.rawValue
        )
        #expect(
            settings.mods?.command?
                .variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.revealFolder.rawValue
        )
        #expect(settings.mods?.command?.arg == directory.path)
    }

    @Test
    func configurationLargeTypeShowsReadableSettingsSummary() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let store = try PresetStore(environment: environment)
        _ = try store.save(.crop(CropActionPreset(size: try #require(
            CropSizeParser.parse("16:9")
        ))))
        _ = try store.save(.downscale(DownscaleActionPreset(factor: 0.5)))
        for format in ["webp", "avif", "heic", "jxl", "jpeg", "png"] {
            _ = try store.save(.conversion(ConversionActionPreset(
                choice: ConversionChoice(
                    media: .image,
                    format: format,
                    setting: .compression(70)
                )
            )))
        }

        let menu = ConfigurationMenu.namespaceResponse(
            query: ":",
            environment: environment
        )
        let largeType = try #require(menu.items.first?.text?.largetype)

        #expect(largeType.contains("SETTINGS\n\(store.fileURL.path)"))
        #expect(largeType.contains("OUTPUT TEMPLATE\n%P/%f-clop"))
        #expect(largeType.contains("PRESETS\nCrop / Resize: 1"))
        #expect(largeType.contains("Crop / Resize: 1"))
        #expect(largeType.contains("- 16:9"))
        #expect(largeType.contains("- 16:9\n\nDownscale: 1"))
        #expect(largeType.contains("- 50%"))
        #expect(largeType.contains("- 50%\n\nConvert Image: 6"))
        #expect(largeType.contains("- WebP · Compression 70"))
        #expect(largeType.contains("... and 1 more"))

        let templateState = try JSONOutput.string(
            for: MenuState.configuration(mode: .configurationOutputTemplate),
            prettyPrinted: false
        )
        let templateEditor = ConfigurationMenu.response(
            stateJSON: templateState,
            query: "",
            environment: environment
        )
        #expect(
            templateEditor.items.first?.text?.largetype?
                .contains("%P  Source folder") == true
        )
    }

    @Test
    func configurationNamespaceFiltersAndOpensTemplateEditor() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])

        let root = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/photo.png"],
                mediaKinds: [.image]
            ),
            query: ":",
            environment: environment
        )
        #expect(Array(root.items.map(\.title).prefix(2)) == [
            "Output Template",
            "Workflow Settings"
        ])
        #expect(root.items[0].autocomplete == ":template ")
        #expect(root.items[1].autocomplete == ":settings")
        #expect(
            root.variables?[ActionMenu.inputJSONVariable] != nil
        )

        let filtered = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/photo.png"],
                mediaKinds: [.image]
            ),
            query: ":outp",
            environment: environment
        )
        #expect(filtered.items.map(\.title) == ["Output Template"])

        let exactSettings = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/photo.png"],
                mediaKinds: [.image]
            ),
            query: ":settings",
            environment: environment
        )
        #expect(exactSettings.items.map(\.title) == ["Workflow Settings"])

        let editor = ActionMenu.response(
            for: InputSelection(
                inputs: ["/tmp/photo.png"],
                mediaKinds: [.image]
            ),
            query: ":template optimized",
            environment: environment
        )
        #expect(editor.items.map(\.title) == [
            "Photo.png → Original folder/Photo-optimized.png",
            "Photo.png → Original folder/optimized-Photo.png"
        ])
        #expect(
            editor.items.allSatisfy {
                $0.subtitle.contains("⌘↩ Apply and close")
                    && $0.mods?.command?
                        .variables?[ActionMenu.requestKindVariable]
                        == WorkflowRequestKind.configurationMutation.rawValue
            }
        )
        #expect(
            editor.items.allSatisfy {
                $0.variables?[ActionMenu.requestKindVariable]
                    == WorkflowRequestKind.parameterStep.rawValue
            }
        )
    }

    @Test
    func configurationOffersDiagnosticReportCopyAndPreview() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path,
            "alfred_workflow_version": "9.9.9"
        ])

        let menu = ConfigurationMenu.namespaceResponse(
            query: ":",
            environment: environment,
            pipelineProvider: SettingsPipelineStub(count: 3)
        )
        let item = try #require(menu.items.first {
            $0.title == "Diagnostics"
        })

        #expect(item.subtitle == "Copy support details · ⌘L Preview")
        #expect(item.autocomplete == ":diagnostics")
        #expect(item.valid)
        #expect(item.icon == nil)
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.diagnosticReportCopy.rawValue
        )
        #expect(item.text?.copy == item.text?.largetype)
        #expect(item.text?.largetype?.contains("- Version: 9.9.9") == true)
        #expect(item.text?.largetype?.contains("- Saved pipelines: 3") == true)
        #expect(item.text?.largetype?.contains("Expected Command Families") == true)

        let exact = ConfigurationMenu.namespaceResponse(
            query: ":diagnostics",
            environment: environment,
            pipelineProvider: SettingsPipelineStub(count: 3)
        )
        #expect(exact.items.map(\.title) == ["Diagnostics"])
    }

    @Test
    func presetsNamespaceShowsCategoriesAndShortcutReference() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let store = try PresetStore(environment: environment)
        _ = try store.save(.crop(CropActionPreset(size: try #require(
            CropSizeParser.parse("128x0")
        ))))
        _ = try store.save(.downscale(DownscaleActionPreset(factor: 0.5)))
        _ = try store.save(.conversion(ConversionActionPreset(
            choice: ConversionChoice(
                media: .image,
                format: "webp",
                setting: .compression(80)
            )
        )))

        let response = ConfigurationMenu.namespaceResponse(
            query: ":presets",
            environment: environment
        )

        #expect(response.items.map(\.title).contains("Crop / Resize Presets"))
        #expect(response.items.map(\.title).contains("Downscale Presets"))
        #expect(response.items.map(\.title).contains("Convert Image Presets"))
        #expect(response.items.map(\.title).contains("Remove all action presets"))
        #expect(response.items.first {
            $0.title == "Remove all action presets"
        }?.icon == WorkflowIcon.destructive)
        let image = try #require(response.items.first {
            $0.title == "Convert Image Presets"
        })
        #expect(image.autocomplete == ":presets convert image ")
        #expect(
            image.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.parameterStepQuery.rawValue
        )
        #expect(image.variables?[ActionMenu.menuStateVariable] == "")
        #expect(image.text?.largetype?.contains("PRESET FILTER SHORTCUTS") == true)
        #expect(image.text?.largetype?.contains("img") == true)
    }

    @Test
    func presetsNamespaceSearchesAllPresetsOrRoutesToCategory() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let store = try PresetStore(environment: environment)
        _ = try store.save(.crop(CropActionPreset(size: try #require(
            CropSizeParser.parse("1200x630")
        ))))
        _ = try store.save(.cropPDF(CropPDFActionPreset(request: CropPDFRequest(
            target: .aspectRatio("4:3")
        ))))
        _ = try store.save(.downscale(DownscaleActionPreset(factor: 0.5)))

        let global = ConfigurationMenu.namespaceResponse(
            query: ":presets 1200",
            environment: environment
        )
        #expect(global.items.contains {
            $0.title.contains("1200x630")
                && $0.subtitle.contains("Return to review removal")
                && $0.icon == WorkflowIcon.preset
        })
        #expect(!global.items.contains {
            $0.title == "Downscale Presets"
        })

        let crop = ConfigurationMenu.namespaceResponse(
            query: ":presets crop",
            environment: environment
        )
        #expect(crop.items.contains { $0.title.contains("1200x630") })
        #expect(!crop.items.contains { $0.title == "Crop PDF Presets" })
        #expect(!crop.items.contains { $0.title == "Convert Image Presets" })
        #expect(!crop.items.contains { $0.title.contains("4:3") })

        let pdf = ConfigurationMenu.namespaceResponse(
            query: ":presets pdf",
            environment: environment
        )
        #expect(pdf.items.contains { $0.title.contains("4:3") })
        #expect(!pdf.items.contains { $0.title.contains("1200x630") })

        let removal = ConfigurationMenu.namespaceResponse(
            query: ":presets remo",
            environment: environment
        )
        #expect(removal.items.first?.title == "Remove all action presets")
        #expect(removal.items.first?.icon == WorkflowIcon.destructive)
        #expect(!removal.items.contains { $0.title == "Optimize Presets" })

        let exactRemoval = ConfigurationMenu.namespaceResponse(
            query: ":presets remove all",
            environment: environment
        )
        #expect(exactRemoval.items.map(\.title) == ["Remove all action presets"])
        #expect(exactRemoval.items.first?.icon == WorkflowIcon.destructive)
    }

    @Test
    func presetManagementCanCancelOrRemoveIndividualPreset() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let store = try PresetStore(environment: environment)
        let crop = ActionPreset.crop(CropActionPreset(size: try #require(
            CropSizeParser.parse("1200x630")
        )))
        let downscale = ActionPreset.downscale(DownscaleActionPreset(factor: 0.5))
        _ = try store.save(crop)
        _ = try store.save(downscale)

        let root = ConfigurationMenu.namespaceResponse(
            query: ":presets",
            environment: environment
        )
        let cropCategory = try #require(root.items.first {
            $0.title == "Crop / Resize Presets"
        })
        #expect(cropCategory.arg == ":presets crop ")
        #expect(cropCategory.autocomplete == ":presets crop ")
        let cropList = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(mode: .configurationPresets),
                prettyPrinted: false
            ),
            query: "crop",
            environment: environment
        )
        let cropPreset = try #require(cropList.items.first {
            $0.title.contains("1200x630")
        })
        #expect(cropPreset.icon == WorkflowIcon.preset)
        let confirmation = ConfigurationMenu.response(
            stateJSON: try #require(
                cropPreset.variables?[ActionMenu.menuStateVariable]
            ),
            query: "",
            environment: environment
        )

        #expect(confirmation.items.map(\.title).contains("Cancel"))
        #expect(confirmation.items.first?.icon == WorkflowIcon.destructive)
        #expect(
            confirmation.items.first?.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.parameterStep.rawValue
        )
        #expect(
            confirmation.items.first?.mods?.command?
                .variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.configurationMutation.rawValue
        )

        let cancel = try #require(confirmation.items.first {
            $0.title == "Cancel"
        })
        let cancelled = ConfigurationMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.configuration(mode: .configurationPresets),
                prettyPrinted: false
            ),
            query: "crop",
            environment: environment
        )
        #expect(cancel.arg == ":presets crop ")
        #expect(cancelled.items.contains { $0.title.contains("1200x630") })
        #expect(try store.load().presets.count == 2)
        #expect(
            ConfigurationMenu.mutationReturnQuery(
                stateJSON: try #require(confirmation.items.first?.arg)
            ) == ":presets crop "
        )

        let removed = ConfigurationMenu.response(
            stateJSON: try #require(confirmation.items.first?.arg),
            query: "",
            environment: environment
        )
        #expect(!removed.items.contains { $0.title.contains("1200x630") })
        #expect(try store.load().presets == [downscale])
    }

    @Test
    func deletingConfigurationNamespaceRestoresProcessingActions() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let selection = InputSelection(
            inputs: ["/tmp/photo.png"],
            mediaKinds: [.image]
        )

        let configuration = ActionMenu.response(
            for: selection,
            query: ":",
            environment: environment
        )
        let actions = ActionMenu.response(
            for: selection,
            query: "",
            environment: environment
        )

        #expect(configuration.items.first?.title == "Output Template")
        #expect(actions.items.contains { $0.title == "Optimize" })
        #expect(!actions.items.contains { $0.title == "Workflow Settings" })
    }

    @Test
    func configurationRowsExposeSettingsFileForQuickLookAndAlfredActions() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let store = try PresetStore(environment: environment)
        try store.save(.crop(CropActionPreset(size: try #require(
            CropSizeParser.parse("w128")
        ))))
        try store.updateOutputTemplate("%P/%f-processed")

        let response = ConfigurationMenu.namespaceResponse(
            query: ":",
            environment: environment
        )
        let filePath = directory.appendingPathComponent("settings.json").path

        #expect(response.items.map(\.title).contains("Reset output template"))
        #expect(response.items.map(\.title).contains("Manage action presets"))
        #expect(response.items.allSatisfy {
            $0.quickLookURL == filePath
                && $0.action?.file == .single(filePath)
        })
        #expect(response.items.filter {
            $0.title != "Diagnostics"
        }.allSatisfy {
            $0.text?.largetype?.contains("OUTPUT TEMPLATE\n%P/%f-processed") == true
        })
        #expect(response.items.first {
            $0.title == "Reset output template"
        }?.autocomplete == ":reset output")
        #expect(response.items.first {
            $0.title == "Manage action presets"
        }?.autocomplete == ":presets ")
    }

    @Test
    func configurationNamespaceOverridesMissingInputErrors() throws {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])

        let response = ActionMenu.response(
            paths: ["/tmp/alfred-clop-definitely-missing.png"],
            query: ":",
            environment: environment
        )

        #expect(response.items.first?.title == "Output Template")
        #expect(response.items.contains { $0.title == "Workflow Settings" })
    }

    @Test
    func invalidSettingsErrorCanRevealRecoveryLocation() throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent("settings.json")
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])

        let response = AlfredClopCommand.settingsRecoveryResponse(
            error: PresetStoreError.invalidFile,
            environment: environment
        )
        let item = try #require(response.items.first)

        #expect(item.title == "Unable to initialize settings")
        #expect(item.subtitle.contains("Return reveals Settings folder"))
        #expect(item.arg == directory.path)
        #expect(item.valid)
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.revealFolder.rawValue
        )
        #expect(item.quickLookURL == fileURL.path)
        #expect(item.action?.file == .single(fileURL.path))
        #expect(item.text?.largetype?.contains(fileURL.path) == true)
        #expect(item.text?.largetype?.contains("Edit or delete settings.json") == true)
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

        let menu = ConfigurationMenu.namespaceResponse(
            query: ":",
            environment: Environment(values: [
                PresetStore.workflowDataEnvironmentKey: directory.path
            ]),
            cache: cache
        )
        let cleanup = try #require(menu.items.first {
            $0.title == "Clear cached clipboard images"
        })

        #expect(cache.summary() == ClipboardImageCacheSummary(
            fileCount: 2,
            byteCount: 30
        ))
        #expect(cleanup.subtitle.contains("⌘↩ Reveal Cache Folder"))
        #expect(cleanup.mods?.command?.arg == directory.path)
        #expect(
            cleanup.mods?.command?
                .variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.revealFolder.rawValue
        )
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

private struct SettingsPipelineStub: ClopPipelineProviding {
    var count: Int

    func listPipelines() throws -> [SavedPipeline] {
        (0..<count).map {
            SavedPipeline(name: "Settings Pipeline \($0)", rawText: "optimise")
        }
    }

    func pipelinePrompt(task: String) throws -> String {
        ""
    }

    func addPipeline(_ request: PipelineAddRequest) throws {}

    func deletePipeline(named name: String) throws {}
}
