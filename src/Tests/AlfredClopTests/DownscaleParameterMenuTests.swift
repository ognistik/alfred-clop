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

    @Test
    func emptyQueryShowsOneInstructionalItem() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .selected),
            query: ""
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Type a downscale factor")
        #expect(response.items[0].subtitle == "Examples: 50, 50%, 0.5, 75%, 0.75 · ⌃↩ Save Preset")
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
        #expect(operation.action == .downscale(factor: 0.5))
        #expect(response.variables?[ActionMenu.menuStateVariable] == stateJSON)
        #expect(response.variables?[ActionMenu.inputContextVariable] == context.rawValue)
    }

    @Test(arguments: [
        ("50", 0.5, "Use 50%"),
        ("50%", 0.5, "Use 50%"),
        ("0.5", 0.5, "Use 50%"),
        ("75", 0.75, "Use 75%")
    ])
    func acceptedSyntaxProducesOneExplanatoryResult(
        input: String,
        factor: Double,
        title: String
    ) throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: input
        )
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)

        #expect(response.items.count == 1)
        #expect(item.title == title)
        #expect(item.subtitle.contains("Factor \(DownscaleFactorParser.factorValue(for: factor))"))
        #expect(operation.action == .downscale(factor: factor))
    }

    @Test
    func invalidTypedQueryShowsOneClearError() throws {
        let response = try downscaleResponse(
            stateJSON: try downscaleStateJSON(context: .arguments),
            query: "100%"
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Invalid downscale factor")
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
        #expect(response.items[0].title == "Use 50%")
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

        #expect(response.items.map(\.title) == ["Use 7%", "75%"])
        #expect(operation.action == .downscale(factor: 0.07))
        #expect(typedItem.mods?.control?.subtitle == "Save Preset 7%")
        #expect(
            response.items[1].mods?.control?.subtitle
                == "Remove Preset 75%"
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
            "75%"
        ])
        #expect(try fixture.store.load().presets == [
            .downscale(DownscaleActionPreset(factor: 0.75))
        ])
    }

    private func downscaleStateJSON(
        context: ActionInputContext
    ) throws -> String {
        try JSONOutput.string(
            for: MenuState.downscale(ParameterStepRequest(
                action: .downscale,
                inputs: ["/tmp/first image.png", "/tmp/second audio.m4a"],
                inputContext: context
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
