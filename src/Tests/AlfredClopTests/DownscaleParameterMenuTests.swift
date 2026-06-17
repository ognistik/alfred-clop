import Foundation
import Testing
@testable import AlfredClop

struct DownscaleParameterMenuTests {
    @Test(arguments: [
        ("50", 0.5, "50%", "0.5"),
        ("50%", 0.5, "50%", "0.5"),
        ("0.5", 0.5, "50%", "0.5"),
        (".5", 0.5, "50%", "0.5"),
        ("75", 0.75, "75%", "0.75"),
        ("12.5%", 0.125, "12.5%", "0.125")
    ])
    func parsesAndNormalizesFactors(
        input: String,
        factor: Double,
        displayValue: String,
        factorValue: String
    ) throws {
        let parsed = try #require(DownscaleFactorParser.parse(input))
        #expect(parsed.factor == factor)
        #expect(parsed.displayValue == displayValue)
        #expect(parsed.factorValue == factorValue)
    }

    @Test(arguments: [
        "",
        "0",
        "0%",
        "1",
        "1.0",
        "100",
        "100%",
        "120",
        "120%",
        "-50",
        "50.5",
        "half"
    ])
    func rejectsUnsupportedFactors(input: String) {
        #expect(DownscaleFactorParser.parse(input) == nil)
    }

    @Test(arguments: [
        ("50 ad", 0.5, CropAdaptiveOptimisation.enabled, false),
        ("50%, mute", 0.5, nil, true),
        ("0.5 no adaptive", 0.5, CropAdaptiveOptimisation.disabled, false),
        ("75% ad m", 0.75, CropAdaptiveOptimisation.enabled, true)
    ])
    func parsesDownscaleControls(
        input: String,
        factor: Double,
        adaptive: CropAdaptiveOptimisation?,
        removeAudio: Bool
    ) throws {
        let controls = try #require(DownscaleControlParser.parse(input))

        #expect(controls.factor.factor == factor)
        #expect(controls.adaptiveOptimisation == adaptive)
        #expect(controls.removeAudio == removeAudio)
    }

    @Test(arguments: [
        "ad",
        "50 ad no-ad",
        "50 m mute",
        "50 75",
        "50 unknown"
    ])
    func rejectsInvalidDownscaleControls(input: String) {
        #expect(DownscaleControlParser.parse(input) == nil)
    }

    @Test
    func emptyQueryShowsOneInstructionalItem() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .selected),
            query: ""
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Type a downscale factor")
        #expect(response.items[0].subtitle == "Examples: 50 / 50% / 0.5 / 75% / 0.75 · ⇥ Controls · ⌃↩ Save Preset")
        #expect(response.items[0].autocomplete == "controls: ")
        #expect(response.items[0].valid == false)
    }

    @Test(arguments: [
        (ActionInputContext.selected, "Selected 2 files"),
        (ActionInputContext.clipboard, "Copied 2 files"),
        (ActionInputContext.arguments, "Passed 2 files")
    ])
    func queryRerunsPreservePathsAndContext(
        context: ActionInputContext,
        subtitlePrefix: String
    ) throws {
        let stateJSON = try downscaleStateJSON(context: context)
        let response = try downscaleResponse(
            stateJSON: stateJSON,
            query: "50"
        )
        let item = try #require(response.items.first(where: { $0.valid }))
        let operation = try operationRequest(from: item)

        #expect(response.items.count == 1)
        #expect(item.subtitle.hasPrefix("\(subtitlePrefix) ·"))
        #expect(operation.inputs == ["/tmp/first image.png", "/tmp/second audio.m4a"])
        #expect(downscaleComponents(operation.action)?.factor == 0.5)
        #expect(response.variables?[ActionMenu.menuStateVariable] == stateJSON)
        #expect(response.variables?[ActionMenu.inputContextVariable] == context.rawValue)
    }

    @Test
    func acceptedSyntaxProducesOneExplanatoryResult() throws {
        let cases: [(input: String, factor: Double, title: String)] = [
            ("50", 0.5, "Downscale to 50%"),
            ("50%", 0.5, "Downscale to 50%"),
            ("0.5", 0.5, "Downscale to 50%"),
            ("75", 0.75, "Downscale to 75%")
        ]

        for testCase in cases {
            let response = try downscaleResponse(
                stateJSON: try downscaleStateJSON(context: .arguments),
                query: testCase.input
            )
            let item = try #require(response.items.first)
            let operation = try operationRequest(from: item)
            let components = try #require(downscaleComponents(operation.action))

            #expect(response.items.count == 1)
            #expect(item.title == testCase.title)
            #expect(!item.subtitle.contains(
                "Factor \(DownscaleFactorParser.factorValue(for: testCase.factor))"
            ))
            #expect(item.subtitle == "Passed 2 files · ⌃↩ Save Preset")
            #expect(components.factor == testCase.factor)
        }
    }

    @Test
    func validControlsBuildTypedRequest() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(
                context: .selected,
                mediaKinds: [.video],
                itemKinds: [.localFile, .localFile]
            ),
            query: "controls: 50 ad m"
        )
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)
        let components = try #require(downscaleComponents(operation.action))

        #expect(item.title == "Downscale to 50% · Adaptive · Mute Video")
        #expect(item.subtitle == "Selected 2 files · ⌃↩ Save Preset")
        #expect(!item.subtitle.contains("Use factor"))
        #expect(item.autocomplete == "controls: 50% ad m")
        #expect(components == (
            factor: 0.5,
            adaptiveOptimisation: .enabled,
            removeAudio: true
        ))
    }

    @Test
    func rootAcceptsFactorPlusControls() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(
                context: .selected,
                mediaKinds: [.video],
                itemKinds: [.localFile, .localFile]
            ),
            query: "75 mute"
        )
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)
        let components = try #require(downscaleComponents(operation.action))

        #expect(item.title == "Downscale to 75% · Mute Video")
        #expect(components == (
            factor: 0.75,
            adaptiveOptimisation: nil,
            removeAudio: true
        ))
    }

    @Test
    func controlsBranchGuidanceUsesLargeTypeReference() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "controls: "
        )
        let item = try #require(response.items.first)

        #expect(item.title == "Type downscale controls")
        #expect(item.subtitle == "Passed 2 files · Use factor + ad + m · ⌘L Reference")
        #expect(item.text?.largetype?.contains("Downscale controls") == true)
        #expect(item.text?.largetype?.contains("Inputs\n2 inputs") == true)
    }

    @Test
    func partialControlsShowGuidanceBeforeInvalidFeedback() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "controls: 50 a"
        )

        #expect(response.items.first?.title == "Type downscale controls")
        #expect(response.items.first?.subtitle == "Passed 2 files · Use factor + ad + m · ⌘L Reference")
    }

    @Test
    func invalidControlsShowGuidance() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "controls: 50 banana"
        )

        #expect(response.items.first?.title == "Invalid downscale controls")
        #expect(response.items.first?.subtitle == "Passed 2 files · Use factor + ad + m · ⌘L Reference")
    }

    @Test
    func muteControlIsRejectedForClearNonVideoInput() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(
                context: .selected,
                mediaKinds: [.image],
                itemKinds: [.localFile, .localFile]
            ),
            query: "controls: 50 m"
        )

        #expect(response.items.first?.title == "Mute only applies to video")
        #expect(response.items.first?.subtitle == "Selected 2 files · Use factor + ad · ⌘L Reference")
    }

    @Test
    func invalidTypedQueryShowsOneClearError() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "100%"
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Invalid downscale factor")
        #expect(response.items[0].subtitle == "Passed 2 files · Use 50 / 50% / 0.5 · ⌘L Reference")
        #expect(response.items[0].text?.largetype?.contains("Inputs\n2 inputs") == true)
        #expect(response.items[0].valid == false)
    }

    @Test
    func savedPresetCombinesWithEquivalentTypedValues() throws {
        let fixture = try DownscalePresetFixture()
        _ = try fixture.store.save(.downscale(DownscaleActionPreset(
            factor: 0.5
        )))

        let response = DownscaleParameterMenu.response(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "50",
            environment: fixture.environment
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Downscale to 50%")
        #expect(response.items[0].subtitle.contains("Saved Preset"))
        #expect(response.items[0].uid == "downscale.preset.factor.0.5")
    }

    @Test
    func validTypedFactorStaysFirstBeforeMatchingPreset() throws {
        let fixture = try DownscalePresetFixture()
        _ = try fixture.store.save(.downscale(DownscaleActionPreset(
            factor: 0.75
        )))

        let response = DownscaleParameterMenu.response(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "7",
            environment: fixture.environment
        )
        let typedItem = try #require(response.items.first)
        let operation = try operationRequest(from: typedItem)

        #expect(response.items.map(\.title) == [
            "Downscale to 7%",
            "Downscale to 75%"
        ])
        #expect(downscaleComponents(operation.action)?.factor == 0.07)
        #expect(
            typedItem.mods?.control?.subtitle
                == "Save Preset Downscale to 7%"
        )
        #expect(
            response.items[1].mods?.control?.subtitle
                == "Remove Preset Downscale to 75%"
        )
    }

    @Test
    func controlReturnOnTypedValueSavesPreset() throws {
        let fixture = try DownscalePresetFixture()
        let response = DownscaleParameterMenu.response(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "75",
            environment: fixture.environment
        )
        let stateJSON = try #require(response.items[0].mods?.control?.arg)

        let saved = DownscaleParameterMenu.response(
            stateJSON: stateJSON,
            query: "",
            environment: fixture.environment
        )

        #expect(saved.items.map(\.title) == [
            "Type a downscale factor",
            "Downscale to 75%"
        ])
        #expect(try fixture.store.load().presets == [
            .downscale(DownscaleActionPreset(factor: 0.75))
        ])
    }

    @Test
    func controlsPresetCanBeSavedAndRemoved() throws {
        let fixture = try DownscalePresetFixture()
        let response = DownscaleParameterMenu.response(
            stateJSON: try downscaleStateJSON(
                context: .arguments,
                mediaKinds: [.video],
                itemKinds: [.localFile, .localFile]
            ),
            query: "controls: 75 ad m",
            environment: fixture.environment
        )
        let stateJSON = try #require(response.items[0].mods?.control?.arg)

        let saved = DownscaleParameterMenu.response(
            stateJSON: stateJSON,
            query: "",
            environment: fixture.environment
        )

        #expect(saved.items.map(\.title) == [
            "Type a downscale factor",
            "Downscale to 75% · Adaptive · Mute Video"
        ])
        #expect(saved.items[1].subtitle == "Passed 2 files · Saved Preset · ⌃↩ Remove Preset")
        #expect(saved.items[1].autocomplete == "75% ad m")
        #expect(try fixture.store.load().presets == [
            .downscale(DownscaleActionPreset(
                factor: 0.75,
                adaptiveOptimisation: .enabled,
                removeAudio: true
            ))
        ])
    }

    @Test
    func controlReturnOnPresetCanBeCancelled() throws {
        let fixture = try DownscalePresetFixture()
        _ = try fixture.store.save(.downscale(DownscaleActionPreset(
            factor: 0.75
        )))
        let response = DownscaleParameterMenu.response(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "",
            environment: fixture.environment
        )
        let preset = try #require(response.items.first {
            $0.title == "Downscale to 75%"
        })
        let confirmationState = try #require(
            preset.mods?.control?.variables?[ActionMenu.menuStateVariable]
        )
        let confirmation = DownscaleParameterMenu.response(
            stateJSON: confirmationState,
            query: "",
            environment: fixture.environment
        )

        #expect(confirmation.items.map(\.title) == [
            "Remove Preset 75%?",
            "Cancel"
        ])

        let cancelState = try #require(
            confirmation.items[1].variables?[ActionMenu.menuStateVariable]
        )
        let cancelled = DownscaleParameterMenu.response(
            stateJSON: cancelState,
            query: "",
            environment: fixture.environment
        )

        #expect(cancelled.items.map(\.title) == [
            "Type a downscale factor",
            "Downscale to 75%"
        ])
        #expect(try fixture.store.load().presets == [
            .downscale(DownscaleActionPreset(factor: 0.75))
        ])
    }

    private func downscaleStateJSON(
        context: ActionInputContext,
        mediaKinds: [MediaKind]? = nil,
        itemKinds: [InputItemKind]? = nil
    ) throws -> String {
        try JSONOutput.string(
            for: MenuState.downscale(ParameterStepRequest(
                action: .downscale,
                inputs: ["/tmp/first image.png", "/tmp/second audio.m4a"],
                inputContext: context,
                mediaKinds: mediaKinds,
                itemKinds: itemKinds
            )),
            prettyPrinted: false
        )
    }

    private func downscaleResponse(
        stateJSON: String,
        query: String
    ) throws -> ScriptFilterResponse {
        let directory = try makeTemporaryDirectory()
        return DownscaleParameterMenu.response(
            stateJSON: stateJSON,
            query: query,
            environment: Environment(values: [
                PresetStore.workflowDataEnvironmentKey: directory.path
            ])
        )
    }

    private func operationRequest(
        from item: ScriptFilterItem
    ) throws -> OperationRequest {
        try JSONDecoder().decode(
            OperationRequest.self,
            from: Data(try #require(item.arg).utf8)
        )
    }

    private func downscaleComponents(
        _ action: ActionRequest
    ) -> (
        factor: Double,
        adaptiveOptimisation: CropAdaptiveOptimisation?,
        removeAudio: Bool
    )? {
        guard case let .downscale(
            factor,
            adaptiveOptimisation,
            removeAudio
        ) = action else {
            return nil
        }
        return (factor, adaptiveOptimisation, removeAudio)
    }
}

private struct DownscalePresetFixture {
    let environment: Environment
    let store: PresetStore

    init() throws {
        let directory = try makeTemporaryDirectory()
        environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        store = try PresetStore(environment: environment)
    }
}
