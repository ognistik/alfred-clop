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
                == [
                    "Crop to 16:9",
                    "Long edge 1920",
                    "Height 720, auto width",
                    "Width 128, auto height"
                ]
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
                $0.title == "Crop to 1200x630"
            }))
        )

        #expect(response.items[0].title == "Crop to 1200x630")
        #expect(!response.items.contains {
            $0.title == "Width 128, auto height"
        })
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
        #expect(matchingItems[0].subtitle.contains("Saved Preset"))
        #expect(matchingItems[0].autocomplete == "w128")
        #expect(response.items.count == 1)
        #expect(!response.items.contains {
            $0.title == "Type crop or resize parameters"
        })
    }

    @Test
    func matchingTypedControlsCombineWithSavedPreset() throws {
        let fixture = try Fixture()
        try fixture.save("1200x630 sc ad m")

        let response = fixture.response(query: "1200x630 smart crop adaptive mute")
        let matchingItems = response.items.filter {
            $0.uid == "crop.preset.size.1200x630.smart-crop.enabled.mute"
        }
        let operation = try operationRequest(
            from: try #require(matchingItems.first)
        )

        #expect(matchingItems.count == 1)
        #expect(matchingItems[0].title == "Crop to 1200x630 · Smart Crop · Adaptive · Mute Video")
        #expect(!matchingItems[0].subtitle.contains("Smart Crop"))
        #expect(!matchingItems[0].subtitle.contains("Adaptive"))
        #expect(!matchingItems[0].subtitle.contains("Mute"))
        #expect(matchingItems[0].subtitle.contains("Saved Preset"))
        #expect(operation.action == .crop(
            size: "1200x630",
            smartCrop: true,
            longEdge: false,
            adaptiveOptimisation: .enabled,
            removeAudio: true
        ))
    }

    @Test
    func validTypedQueryStaysFirstBeforeMatchingPresets() throws {
        let fixture = try Fixture()
        try fixture.save("16:9")
        try fixture.save("1920")
        try fixture.save("w128")
        try fixture.save("h720")

        let response = fixture.response(query: "128")

        #expect(
            response.items.map(\.title)
                == ["Long edge 128", "Width 128, auto height"]
        )
        #expect(response.items.allSatisfy {
            $0.title != "Type crop or resize parameters"
        })
        #expect(
            response.items[0].mods?.control?.subtitle
                == "Save Preset Long edge 128"
        )
        #expect(
            response.items[1].mods?.control?.subtitle
                == "Remove Preset Width 128, auto height"
        )
    }

    @Test
    func validTypedControlsStayFirstBeforeMatchingPresets() throws {
        let fixture = try Fixture()
        try fixture.save("1200x630 ad m")
        try fixture.save("1200x630 no-ad m")

        let response = fixture.response(query: "1200x630 m")
        let operation = try operationRequest(
            from: try #require(response.items.first)
        )

        #expect(response.items.map(\.title) == [
            "Crop to 1200x630 · Mute Video",
            "Crop to 1200x630 · Adaptive · Mute Video",
            "Crop to 1200x630 · No Adaptive · Mute Video"
        ])
        #expect(operation.action == .crop(
            size: "1200x630",
            smartCrop: false,
            longEdge: false,
            adaptiveOptimisation: nil,
            removeAudio: true
        ))
    }

    @Test
    func smartCropPresetCanBeSavedAndExecuted() throws {
        let fixture = try Fixture(context: .arguments)
        let initial = fixture.response(query: "16:9 sc")
        let typedItem = try #require(initial.items.first(where: { $0.valid }))
        let control = try #require(typedItem.mods?.control)
        let saveStateJSON = try #require(
            control.variables?[ActionMenu.menuStateVariable]
        )

        let saved = fixture.response(stateJSON: saveStateJSON, query: "")
        let combined = try #require(saved.items.first(where: {
            $0.uid == "crop.preset.size.16:9.smart-crop"
        }))
        let operation = try operationRequest(from: combined)

        #expect(combined.title == "Crop to 16:9 · Smart Crop")
        #expect(combined.autocomplete == "16:9 sc")
        #expect(operation.action == .crop(
            size: "16:9",
            smartCrop: true,
            longEdge: false
        ))
    }

    @Test
    func mutePresetsAreHiddenForClearNonVideoInput() throws {
        let fixture = try Fixture(mediaKinds: [.image, .pdf])
        try fixture.save("w128")
        try fixture.save("w128 m")
        try fixture.save("h720 mute")

        let root = fixture.response(query: "")
        let filtered = fixture.response(query: "128")

        #expect(root.items.map(\.title) == [
            "Type crop or resize parameters",
            "Width 128, auto height"
        ])
        #expect(filtered.items.map(\.title) == [
            "Long edge 128",
            "Width 128, auto height"
        ])
        #expect(!root.items.contains { $0.title.contains("Mute Video") })
        #expect(!filtered.items.contains { $0.title.contains("Mute Video") })
    }

    @Test
    func mutePresetsRemainVisibleForVideoAndAmbiguousInput() throws {
        let videoFixture = try Fixture(mediaKinds: [.video])
        let ambiguousFixture = try Fixture(
            mediaKinds: [],
            itemKinds: [.remoteURL],
            ambiguousKinds: [.remoteURL]
        )
        try videoFixture.save("w128 m")
        try ambiguousFixture.save("w128 m")

        #expect(videoFixture.response(query: "").items.contains {
            $0.title == "Width 128, auto height · Mute Video"
        })
        #expect(ambiguousFixture.response(query: "").items.contains {
            $0.title == "Width 128, auto height · Mute Video"
        })
    }

    @Test
    func numericPresetPrefixKeepsTypedValueAvailableFirst() throws {
        let fixture = try Fixture()
        try fixture.save("2:3")
        try fixture.save("1920")

        let response = fixture.response(query: "19")
        let typedItem = try #require(response.items.first)
        let operation = try operationRequest(from: typedItem)

        #expect(response.items.map(\.title) == [
            "Long edge 19",
            "Long edge 1920"
        ])
        #expect(typedItem.autocomplete == "19")
        #expect(operation.action == .crop(
            size: "19",
            smartCrop: false,
            longEdge: true
        ))
        #expect(
            typedItem.mods?.control?.subtitle
                == "Save Preset Long edge 19"
        )
    }

    @Test
    func freeFormActionReturnsAfterQueryLeavesPresetPrefix() throws {
        let fixture = try Fixture()
        try fixture.save("1920")

        let response = fixture.response(query: "193")

        #expect(response.items.map(\.title) == ["Long edge 193"])
    }

    @Test
    func incompleteQueryShowsMatchingPresetsWithoutInvalidFeedback() throws {
        let fixture = try Fixture()
        try fixture.save("w128")
        try fixture.save("w1920")
        try fixture.save("h720")

        let response = fixture.response(query: "w")

        #expect(response.items.map(\.title) == [
            "Width 128, auto height",
            "Width 1920, auto height"
        ])
        #expect(response.items.allSatisfy { $0.valid })
    }

    @Test
    func nonMatchingTypedQueryDoesNotReturnUnrelatedPresets() throws {
        let fixture = try Fixture()
        try fixture.save("w128")
        try fixture.save("h720")

        let response = fixture.response(query: "1200x630")

        #expect(response.items.map(\.title) == ["Crop to 1200x630"])
    }

    @Test
    func controlReturnSavesTypedValueAndPreservesInputsAndContext() throws {
        let fixture = try Fixture(context: .arguments)
        let initial = fixture.response(query: "w128 no-ad m")
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
            $0.uid == "crop.preset.size.128x0.disabled.mute"
        }))
        let operation = try operationRequest(from: combined)

        #expect(saved.items[0].title == "Type crop or resize parameters")
        #expect(combined.subtitle.contains("Saved Preset"))
        #expect(
            combined.title
                == "Width 128, auto height · No Adaptive · Mute Video"
        )
        #expect(operation.inputs == fixture.inputs)
        #expect(operation.action == .crop(
            size: "128x0",
            smartCrop: false,
            longEdge: false,
            adaptiveOptimisation: .disabled,
            removeAudio: true
        ))
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
        #expect(confirmation.items.count == 2)
        #expect(
            confirmation.items[0].title
                == "Remove Preset Width 128, auto height?"
        )
        #expect(confirmation.items[1].title == "Cancel")
        #expect(confirmation.items[1].subtitle == "Return keeps preset")
        #expect(try fixture.store.load().presets.count == 2)

        let cancelStateJSON = try #require(
            confirmation.items[1].variables?[ActionMenu.menuStateVariable]
        )
        let cancelled = fixture.response(stateJSON: cancelStateJSON, query: "")
        #expect(cancelled.items.contains {
            $0.title == "Width 128, auto height"
        })
        #expect(cancelled.items.contains {
            $0.title == "Height 720, auto width"
        })
        #expect(try fixture.store.load().presets.count == 2)

        let removeStateJSON = try #require(
            confirmation.items[0].variables?[ActionMenu.menuStateVariable]
        )
        let returnedMenu = fixture.response(
            stateJSON: removeStateJSON,
            query: ""
        )

        #expect(returnedMenu.items[0].title == "Type crop or resize parameters")
        #expect(!returnedMenu.items.contains {
            $0.title == "Width 128, auto height"
        })
        #expect(returnedMenu.items.contains {
            $0.title == "Height 720, auto width"
        })
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

    init(
        context: ActionInputContext = .selected,
        mediaKinds: [MediaKind]? = nil,
        itemKinds: [InputItemKind]? = nil,
        ambiguousKinds: [AmbiguousInputKind]? = nil
    ) throws {
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
                inputContext: context,
                mediaKinds: mediaKinds,
                itemKinds: itemKinds,
                ambiguousKinds: ambiguousKinds
            )),
            prettyPrinted: false
        )
    }

    func save(_ value: String) throws {
        let controls = try #require(CropControlParser.parse(value))
        _ = try store.save(.crop(CropActionPreset(controls: controls)))
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
