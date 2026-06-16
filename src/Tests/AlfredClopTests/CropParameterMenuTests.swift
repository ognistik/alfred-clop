import Foundation
import Testing
@testable import AlfredClop

struct CropParameterMenuTests {
    @Test(arguments: [
        ("1200x630", "1200x630", false, CropSizeKind.exactDimensions(width: 1200, height: 630)),
        ("16:9", "16:9", false, CropSizeKind.aspectRatio(width: 16, height: 9)),
        ("1920", "1920", true, CropSizeKind.longEdge(1920)),
        ("w128", "128x0", false, CropSizeKind.fixedWidth(128)),
        ("h720", "0x720", false, CropSizeKind.fixedHeight(720)),
        ("128x0", "128x0", false, CropSizeKind.fixedWidth(128)),
        ("0x720", "0x720", false, CropSizeKind.fixedHeight(720)),
        ("001280x000", "1280x0", false, CropSizeKind.fixedWidth(1280)),
        ("32:18", "16:9", false, CropSizeKind.aspectRatio(width: 16, height: 9))
    ])
    func parsesAndNormalizesVerifiedSizeForms(
        input: String,
        value: String,
        longEdge: Bool,
        kind: CropSizeKind
    ) throws {
        let parsed = try #require(CropSizeParser.parse(input))
        #expect(parsed.value == value)
        #expect(parsed.longEdge == longEdge)
        #expect(parsed.kind == kind)
    }

    @Test(arguments: [
        "",
        "0",
        "0x0",
        "16:0",
        "0:9",
        "-1200x630",
        "1200.5x630",
        "1200xx630",
        "16:9:1",
        "1920px",
        "w",
        "h",
        "w0",
        "h0",
        "W128",
        "height720",
        "128x",
        "x720",
        "128/720"
    ])
    func rejectsUnsupportedSizeForms(input: String) {
        #expect(CropSizeParser.parse(input) == nil)
    }

    @Test
    func emptyQueryShowsOneInstructionalItem() throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: ""
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Type crop or resize parameters")
        #expect(response.items[0].subtitle == "Examples: 1200x630, 16:9, 1920, w128, h720 · ⇥ Controls, ⌃↩ Save Preset")
        #expect(response.items[0].autocomplete == "controls: ")
        #expect(response.items[0].mods?.control?.arg == "controls: ")
        #expect(response.items[0].mods?.control?.subtitle == "Save Preset")
        #expect(response.items[0].text?.largetype?.contains("no-ad or no-adaptive") != true)
        #expect(response.items[0].valid == false)
    }

    @Test
    func controlsEditorShowsReferenceAndVideoAwareGuidance() throws {
        let imageResponse = try cropResponse(
            stateJSON: try cropStateJSON(
                context: .selected,
                mediaKinds: [.image]
            ),
            query: "controls: "
        )
        let videoResponse = try cropResponse(
            stateJSON: try cropStateJSON(
                context: .clipboard,
                mediaKinds: [.video]
            ),
            query: "controls: "
        )

        #expect(imageResponse.items[0].title == "Type crop controls")
        #expect(imageResponse.items[0].subtitle == "Selected 2 files · Size, then ad for adaptive · ⌘L Reference")
        #expect(imageResponse.items[0].text?.largetype?.contains("no-ad or no-adaptive") == true)
        #expect(videoResponse.items[0].subtitle == "Copied 2 files · Size, then ad for adaptive, m for mute · ⌘L Reference")
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
        let stateJSON = try cropStateJSON(context: context)
        let response = try cropResponse(
            stateJSON: stateJSON,
            query: "w128"
        )
        let item = try #require(response.items.first(where: { $0.valid }))
        let operation = try operationRequest(from: item)

        #expect(response.items.count == 1)
        #expect(item.subtitle.hasPrefix("\(subtitlePrefix) ·"))
        #expect(operation.inputs == ["/tmp/first image.png", "/tmp/second.pdf"])
        #expect(
            response.variables?[ActionMenu.menuStateVariable]
                == stateJSON
        )
        #expect(
            response.variables?[ActionMenu.inputContextVariable]
                == context.rawValue
        )
        let inputJSON = try #require(
            response.variables?[ActionMenu.inputJSONVariable]
        )
        let input = try JSONDecoder().decode(
            MenuInput.self,
            from: Data(inputJSON.utf8)
        )
        #expect(input.paths == ["/tmp/first image.png", "/tmp/second.pdf"])
    }

    @Test(arguments: [
        ("1200x630", "Use 1200x630", "Crop to 1200x630"),
        ("16:9", "Use 16:9", "Crop to 16:9"),
        ("1920", "Long edge 1920", "Long edge 1920"),
        ("w128", "Width 128, auto height", "Fixed width 128"),
        ("h720", "Height 720, auto width", "Fixed height 720"),
        ("128x0", "Width 128, auto height", "Fixed width 128"),
        ("0x720", "Height 720, auto width", "Fixed height 720")
    ])
    func acceptedSyntaxProducesOneExplanatoryResult(
        input: String,
        title: String,
        explanation: String
    ) throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .arguments),
            query: input
        )
        let item = try #require(response.items.first(where: { $0.valid }))
        let request = try operationRequest(from: item)

        #expect(response.items.count == 1)
        #expect(item.title == title)
        #expect(!item.subtitle.contains(explanation))
        #expect(item.subtitle.contains(
            "1200x630/16:9/1920/w128/h720 · ⌘L Reference"
        ))
        #expect(item.text?.largetype?.contains("Crop / Resize controls") == true)
        #expect(item.text?.largetype?.contains("/tmp/first image.png") == true)
        #expect(request.inputs == ["/tmp/first image.png", "/tmp/second.pdf"])
        #expect(item.subtitle.hasPrefix("Passed 2 files ·"))
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == "operation"
        )
    }

    @Test(arguments: [
        ("w128", "Width 128, auto height"),
        ("h1200", "Height 1200, auto width"),
        ("128x0", "Width 128, auto height"),
        ("0x1200", "Height 1200, auto width")
    ])
    func fixedDimensionTitlesHideNativeZeroForms(
        input: String,
        expectedTitle: String
    ) throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )

        let item = try #require(response.items.first(where: { $0.valid }))
        #expect(response.items.count == 1)
        #expect(item.title == expectedTitle)
        #expect(!item.title.contains("x0"))
        #expect(!item.title.contains("0x"))
    }

    @Test(arguments: [
        ("1200x630", "1200x630", false),
        ("16:9", "16:9", false),
        ("1920", "1920", true),
        ("w128", "128x0", false),
        ("h720", "0x720", false),
        ("128x0", "128x0", false),
        ("0x720", "0x720", false)
    ])
    func validInputBuildsTypedOperationRequest(
        input: String,
        normalizedValue: String,
        longEdge: Bool
    ) throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )
        let item = try #require(response.items.first(where: { $0.valid }))
        let request = try operationRequest(from: item)

        #expect(
            request.action
                == .crop(
                    size: normalizedValue,
                    smartCrop: false,
                    longEdge: longEdge
                )
        )
    }

    @Test(arguments: [
        ("1200x630 ad", "1200x630", false, CropAdaptiveOptimisation.enabled, false),
        ("16:9 no-ad m", "16:9", false, CropAdaptiveOptimisation.disabled, true),
        ("w128, adaptive, mute", "128x0", false, CropAdaptiveOptimisation.enabled, true),
        ("h720 no adaptive", "0x720", false, CropAdaptiveOptimisation.disabled, false)
    ])
    func typedControlsBuildCropRequest(
        input: String,
        normalizedValue: String,
        longEdge: Bool,
        adaptive: CropAdaptiveOptimisation?,
        removeAudio: Bool
    ) throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )
        let item = try #require(response.items.first(where: { $0.valid }))
        let request = try operationRequest(from: item)

        #expect(request.action == .crop(
            size: normalizedValue,
            smartCrop: false,
            longEdge: longEdge,
            adaptiveOptimisation: adaptive,
            removeAudio: removeAudio
        ))
        #expect(item.subtitle.contains("Selected 2 files ·"))
        #expect(!item.subtitle.contains("Adaptive"))
        #expect(!item.subtitle.contains("Mute"))
    }

    @Test(arguments: [
        ("122 na", "Long edge 122 · No Adaptive"),
        ("122 ad", "Long edge 122 · Adaptive"),
        ("122 m", "Long edge 122 · Mute Video"),
        ("122 ad m", "Long edge 122 · Adaptive · Mute Video"),
        ("w128 no-ad mute", "Width 128, auto height · No Adaptive · Mute Video")
    ])
    func typedControlTitlesDescribeCompleteAction(
        input: String,
        title: String
    ) throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )
        let item = try #require(response.items.first(where: { $0.valid }))

        #expect(item.title == title)
        #expect(item.subtitle.contains("1200x630/16:9/1920/w128/h720"))
        #expect(!item.subtitle.contains("No Adaptive"))
        #expect(!item.subtitle.contains("Adaptive"))
        #expect(!item.subtitle.contains("Mute"))
    }

    @Test
    func muteControlIsRejectedForClearNonVideoInput() throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(
                context: .selected,
                mediaKinds: [.image, .pdf]
            ),
            query: "122 m"
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Mute only applies to video")
        #expect(response.items[0].subtitle == "Size, then ad for adaptive · ⌘L Reference")
        #expect(response.items[0].valid == false)
    }

    @Test
    func muteControlStaysValidForVideoOrAmbiguousInput() throws {
        let videoResponse = try cropResponse(
            stateJSON: try cropStateJSON(
                context: .selected,
                mediaKinds: [.video]
            ),
            query: "122 m"
        )
        let ambiguousStateJSON = try JSONOutput.string(
            for: MenuState.crop(ParameterStepRequest(
                action: .crop,
                inputs: ["https://example.com/media"],
                inputContext: .arguments,
                mediaKinds: [],
                itemKinds: [.remoteURL],
                ambiguousKinds: [.remoteURL]
            )),
            prettyPrinted: false
        )
        let ambiguousResponse = try cropResponse(
            stateJSON: ambiguousStateJSON,
            query: "122 m"
        )

        #expect(videoResponse.items[0].title == "Long edge 122 · Mute Video")
        #expect(ambiguousResponse.items[0].title == "Long edge 122 · Mute Video")
    }

    @Test(arguments: [
        "1200x630 ad no-ad",
        "16:9 adaptive adaptive",
        "w128 m mute",
        "h720 banana"
    ])
    func conflictingControlsReturnOneVisibleFeedbackItem(input: String) throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Invalid crop or resize value")
        #expect(response.items[0].valid == false)
        #expect(response.items[0].text?.largetype?.contains("Crop / Resize controls") == true)
    }

    @Test
    func plausibleControlPrefixDoesNotFallThroughToPresetOnlyFeedback() throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: "1200x630 no-"
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Keep typing crop controls")
        #expect(response.items[0].valid == false)
    }

    @Test(arguments: [
        "0", "0x0", "16:", "16:0", "-1", "1.5", "1200xx630",
        "16:9:1", "q128", "128x720x1"
    ])
    func invalidAndIncompleteInputReturnsOneVisibleFeedbackItem(
        input: String
    ) throws {
        let response = try cropResponse(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Invalid crop or resize value")
        #expect(
            response.items[0].subtitle
                == "Use 1200x630, 16:9, 1920, w128, or h720. ⌘L Reference"
        )
        #expect(response.items[0].valid == false)
        #expect(response.items[0].arg == "")
    }

    @Test
    func invalidTypedStateIsVisibleAndNonExecutable() {
        let response = CropParameterMenu.response(
            stateJSON: #"{"mode":"crop"}"#,
            query: ""
        )

        #expect(response.items[0].title == "Unable to open Crop / Resize")
        #expect(response.items[0].valid == false)
    }

    @Test
    func parameterMenuRowsExposeOriginalInputsToQuickLookAndAlfredActions() throws {
        let stateJSON = try JSONOutput.string(
            for: MenuState.crop(ParameterStepRequest(
                action: .crop,
                inputs: [
                    "/tmp/first image.png",
                    "/tmp/Media Folder",
                    "https://example.com/photo.png"
                ],
                inputContext: .arguments,
                itemKinds: [.localFile, .folder, .remoteURL]
            )),
            prettyPrinted: false
        )

        let response = try cropResponse(stateJSON: stateJSON, query: "w128")
        let item = try #require(response.items.first)

        #expect(item.quickLookURL == "/tmp/first image.png")
        #expect(item.action?.file == .multiple([
            "/tmp/first image.png",
            "/tmp/Media Folder"
        ]))
        #expect(item.action?.url == .single("https://example.com/photo.png"))
        #expect(item.text?.largetype?.contains("Crop / Resize controls") == true)
        #expect(item.text?.largetype?.contains("Inputs") == true)
        #expect(item.text?.largetype?.contains("/tmp/first image.png") == true)
        #expect(item.text?.largetype?.contains("/tmp/Media Folder") == true)
        #expect(item.text?.largetype?.contains("https://example.com/photo.png") == true)
    }

    private func cropStateJSON(
        context: ActionInputContext,
        mediaKinds: [MediaKind]? = nil
    ) throws -> String {
        try JSONOutput.string(
            for: MenuState.crop(ParameterStepRequest(
                action: .crop,
                inputs: ["/tmp/first image.png", "/tmp/second.pdf"],
                inputContext: context,
                mediaKinds: mediaKinds
            )),
            prettyPrinted: false
        )
    }

    private func cropResponse(
        stateJSON: String,
        query: String
    ) throws -> ScriptFilterResponse {
        let directory = try makeTemporaryDirectory()
        return CropParameterMenu.response(
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
