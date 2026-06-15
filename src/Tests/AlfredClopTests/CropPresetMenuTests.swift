import Foundation
import Testing
@testable import AlfredClop

struct CropPresetMenuTests {
    @Test
    func instructionStaysFirstAndPresetsUseNaturalDisplayOrder() throws {
        let fixture = try Fixture()
        try fixture.save("w128")
        try fixture.save("h720")
        try fixture.save("1920")
        try fixture.save("16:9")

        let first = fixture.response(query: "")
        let second = fixture.response(query: "")

        #expect(first.items[0].title == "Type crop or resize parameters")
        #expect(
            first.items.dropFirst().map(\.title)
                == ["16:9", "1920", "h720", "w128"]
        )
        #expect(first.items.dropFirst().allSatisfy { $0.uid != nil })
        #expect(first.items.map(\.uid) == second.items.map(\.uid))
        #expect(first.skipKnowledge == true)
    }

    @Test
    func arbitraryTypedValueRemainsAvailableWithPresets() throws {
        let fixture = try Fixture()
        try fixture.save("w128")

        let response = fixture.response(query: "1200x630")
        let operation = try operationRequest(
            from: try #require(response.items.first(where: {
                $0.title == "Use 1200x630"
            }))
        )

        #expect(response.items[0].title == "Use 1200x630")
        #expect(!response.items.contains { $0.title == "w128" })
        #expect(operation.action == .crop(
            size: "1200x630",
            smartCrop: false,
            longEdge: false
        ))
    }

    @Test
    func matchingTypedValueCombinesWithSavedPreset() throws {
        let fixture = try Fixture()
        try fixture.save("w128")

        let response = fixture.response(query: "128x0")
        let matchingItems = response.items.filter {
            $0.uid == "crop.preset.size.128x0"
        }

        #expect(matchingItems.count == 1)
        #expect(matchingItems[0].title == "Width 128, auto height")
        #expect(matchingItems[0].subtitle.contains("Saved preset"))
        #expect(matchingItems[0].autocomplete == "w128")
        #expect(response.items.count == 1)
        #expect(!response.items.contains {
            $0.title == "Type crop or resize parameters"
        })
    }

    @Test
    func typedQueryPrefersMatchingPresetOverFreeFormAction() throws {
        let fixture = try Fixture()
        try fixture.save("16:9")
        try fixture.save("1920")
        try fixture.save("w128")
        try fixture.save("h720")

        let response = fixture.response(query: "128")

        #expect(
            response.items.map(\.title)
                == ["w128"]
        )
        #expect(response.items.allSatisfy {
            $0.title != "Type crop or resize parameters"
        })
    }

    @Test
    func numericPresetPrefixIsImmediatelySelected() throws {
        let fixture = try Fixture()
        try fixture.save("2:3")
        try fixture.save("1920")

        let response = fixture.response(query: "19")
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)

        #expect(response.items.map(\.title) == ["1920"])
        #expect(item.autocomplete == "1920")
        #expect(operation.action == .crop(
            size: "1920",
            smartCrop: false,
            longEdge: true
        ))
    }

    @Test
    func freeFormActionReturnsAfterQueryLeavesPresetPrefix() throws {
        let fixture = try Fixture()
        try fixture.save("1920")

        let response = fixture.response(query: "193")

        #expect(response.items.map(\.title) == ["Use long edge 193"])
    }

    @Test
    func incompleteQueryShowsMatchingPresetsWithoutInvalidFeedback() throws {
        let fixture = try Fixture()
        try fixture.save("w128")
        try fixture.save("w1920")
        try fixture.save("h720")

        let response = fixture.response(query: "w")

        #expect(response.items.map(\.title) == ["w128", "w1920"])
        #expect(response.items.allSatisfy { $0.valid })
    }

    @Test
    func nonMatchingTypedQueryDoesNotReturnUnrelatedPresets() throws {
        let fixture = try Fixture()
        try fixture.save("w128")
        try fixture.save("h720")

        let response = fixture.response(query: "1200x630")

        #expect(response.items.map(\.title) == ["Use 1200x630"])
    }

    @Test
    func controlReturnSavesTypedValueAndPreservesInputsAndContext() throws {
        let fixture = try Fixture(context: .arguments)
        let initial = fixture.response(query: "w128")
        let typedItem = try #require(initial.items.first(where: { $0.valid }))
        let control = try #require(typedItem.mods?.control)
        let saveStateJSON = try #require(
            control.variables?[ActionMenu.menuStateVariable]
        )
        let saveState = try decodeState(saveStateJSON)

        #expect(saveState.parameterRequest?.inputs == fixture.inputs)
        #expect(saveState.parameterRequest?.inputContext == .arguments)
        #expect(
            control.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.arguments.rawValue
        )

        let saved = fixture.response(stateJSON: saveStateJSON, query: "")
        let combined = try #require(saved.items.first(where: {
            $0.uid == "crop.preset.size.128x0"
        }))
        let operation = try operationRequest(from: combined)

        #expect(saved.items[0].title == "Type crop or resize parameters")
        #expect(combined.subtitle.contains("Saved preset"))
        #expect(operation.inputs == fixture.inputs)
        #expect(try fixture.store.load().presets.count == 1)
    }

    @Test
    func controlReturnOnPresetRequiresConfirmationThenReturnsToMenu() throws {
        let fixture = try Fixture()
        try fixture.save("w128")
        try fixture.save("h720")
        let menu = fixture.response(query: "")
        let preset = try #require(menu.items.first {
            $0.uid == "crop.preset.size.128x0"
        })
        let confirmStateJSON = try #require(
            preset.mods?.control?.variables?[ActionMenu.menuStateVariable]
        )

        #expect(try decodeState(confirmStateJSON).mode == .cropPresetRemoval)
        #expect(try fixture.store.load().presets.count == 2)

        let confirmation = fixture.response(
            stateJSON: confirmStateJSON,
            query: ""
        )
        #expect(confirmation.items.count == 1)
        #expect(confirmation.items[0].title == "Remove saved preset w128?")
        #expect(try fixture.store.load().presets.count == 2)

        let removeStateJSON = try #require(
            confirmation.items[0].variables?[ActionMenu.menuStateVariable]
        )
        let returnedMenu = fixture.response(
            stateJSON: removeStateJSON,
            query: ""
        )

        #expect(returnedMenu.items[0].title == "Type crop or resize parameters")
        #expect(!returnedMenu.items.contains { $0.title == "w128" })
        #expect(returnedMenu.items.contains { $0.title == "h720" })
        #expect(try fixture.store.load().presets.count == 1)
    }

    @Test
    func malformedPresetFileProducesVisibleNonDestructiveError() throws {
        let fixture = try Fixture()
        let original = #"{"version":99,"presets":[]}"#
        try FileManager.default.createDirectory(
            at: fixture.directory,
            withIntermediateDirectories: true
        )
        try Data(original.utf8).write(to: fixture.store.fileURL)

        let response = fixture.response(query: "w128")

        #expect(response.items[0].title == "Type crop or resize parameters")
        #expect(response.items[1].title == "Unable to read saved presets")
        #expect(response.items[1].valid == false)
        #expect(
            try String(contentsOf: fixture.store.fileURL, encoding: .utf8)
                == original
        )
    }

    private func decodeState(_ json: String) throws -> MenuState {
        try JSONDecoder().decode(MenuState.self, from: Data(json.utf8))
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

private struct Fixture {
    let directory: URL
    let environment: Environment
    let store: PresetStore
    let stateJSON: String
    let inputs = [
        "/tmp/First Image With Spaces.png",
        "/tmp/Second Document.pdf"
    ]

    init(context: ActionInputContext = .selected) throws {
        directory = try makeTemporaryDirectory()
            .appendingPathComponent("Preset Data With Spaces")
        environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        store = try PresetStore(environment: environment)
        stateJSON = try JSONOutput.string(
            for: MenuState.crop(ParameterStepRequest(
                action: .crop,
                inputs: inputs,
                inputContext: context
            )),
            prettyPrinted: false
        )
    }

    func save(_ value: String) throws {
        let size = try #require(CropSizeParser.parse(value))
        _ = try store.save(.crop(CropActionPreset(size: size)))
    }

    func response(
        stateJSON: String? = nil,
        query: String
    ) -> ScriptFilterResponse {
        CropParameterMenu.response(
            stateJSON: stateJSON ?? self.stateJSON,
            query: query,
            environment: environment
        )
    }
}
