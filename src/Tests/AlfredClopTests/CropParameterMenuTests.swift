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
        ("0x720", "0x720", false, CropSizeKind.fixedHeight(720))
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
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: ""
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Type crop or resize parameters")
        #expect(response.items[0].subtitle == "Examples: 1200x630, 16:9, 1920, w128, h720")
        #expect(response.items[0].valid == false)
    }

    @Test(arguments: [
        (ActionInputContext.selected, "Selected files"),
        (ActionInputContext.clipboard, "Copied files"),
        (ActionInputContext.arguments, "Passed files")
    ])
    func queryRerunsPreservePathsAndContext(
        context: ActionInputContext,
        subtitlePrefix: String
    ) throws {
        let stateJSON = try cropStateJSON(context: context)
        let response = CropParameterMenu.response(
            stateJSON: stateJSON,
            query: "w128"
        )
        let request = try operationRequest(from: response.items[0])

        #expect(response.items.count == 1)
        #expect(response.items[0].subtitle.hasPrefix("\(subtitlePrefix):"))
        #expect(request.inputs == ["/tmp/first image.png", "/tmp/second.pdf"])
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
        ("1200x630", "exact dimensions 1200x630"),
        ("16:9", "aspect ratio 16:9"),
        ("1920", "long edge to 1920"),
        ("w128", "fixed width 128 with calculated height"),
        ("h720", "fixed height 720 with calculated width"),
        ("128x0", "fixed width 128 with calculated height"),
        ("0x720", "fixed height 720 with calculated width")
    ])
    func acceptedSyntaxProducesOneExplanatoryResult(
        input: String,
        explanation: String
    ) throws {
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .arguments),
            query: input
        )
        let item = try #require(response.items.first)
        let request = try operationRequest(from: item)

        #expect(response.items.count == 1)
        #expect(item.subtitle.contains(explanation))
        #expect(request.inputs == ["/tmp/first image.png", "/tmp/second.pdf"])
        #expect(item.subtitle.hasPrefix("Passed files:"))
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
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == expectedTitle)
        #expect(!response.items[0].title.contains("x0"))
        #expect(!response.items[0].title.contains("0x"))
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
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )
        let request = try operationRequest(from: response.items[0])

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
        "0", "0x0", "16:", "16:0", "-1", "1.5", "1200xx630",
        "16:9:1", "q128", "128x720x1"
    ])
    func invalidAndIncompleteInputReturnsOneVisibleFeedbackItem(
        input: String
    ) throws {
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: input
        )

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Invalid crop or resize value")
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

    private func cropStateJSON(
        context: ActionInputContext
    ) throws -> String {
        try JSONOutput.string(
            for: MenuState.crop(ParameterStepRequest(
                action: .crop,
                inputs: ["/tmp/first image.png", "/tmp/second.pdf"],
                inputContext: context
            )),
            prettyPrinted: false
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
