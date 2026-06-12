import Foundation
import Testing
@testable import AlfredClop

struct CropParameterMenuTests {
    @Test(arguments: [
        ("1200x630", CropSize(value: "1200x630", longEdge: false)),
        ("16:9", CropSize(value: "16:9", longEdge: false)),
        ("1920", CropSize(value: "1920", longEdge: true)),
        ("128x0", CropSize(value: "128x0", longEdge: false)),
        ("0x720", CropSize(value: "0x720", longEdge: false))
    ])
    func parsesVerifiedSizeForms(input: String, expected: CropSize) {
        #expect(CropSizeParser.parse(input) == expected)
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
        "1920px"
    ])
    func rejectsUnsupportedSizeForms(input: String) {
        #expect(CropSizeParser.parse(input) == nil)
    }

    @Test
    func emptyQueryShowsUsefulPresets() throws {
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: ""
        )

        #expect(response.items.contains(where: { $0.title == "1200 x 630" }))
        #expect(response.items.contains(where: { $0.title == "16:9" }))
        #expect(response.items.contains(where: { $0.title == "Long edge 1920" }))
        #expect(response.items.contains(where: { $0.title == "Width 128, auto height" }))
    }

    @Test
    func searchablePresetPreservesCopiedContext() throws {
        let stateJSON = try cropStateJSON(context: .clipboard)
        let response = CropParameterMenu.response(
            stateJSON: stateJSON,
            query: "widescreen"
        )

        #expect(response.items.contains(where: { $0.title == "16:9" }))
        #expect(response.items[0].subtitle.hasPrefix("Copied files:"))
        #expect(
            response.variables?[ActionMenu.menuStateVariable]
                == stateJSON
        )
        #expect(
            response.variables?[ActionMenu.inputContextVariable]
                == ActionInputContext.clipboard.rawValue
        )
    }

    @Test
    func customLongEdgeBuildsOperationRequest() throws {
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .arguments),
            query: "2048"
        )
        let item = try #require(
            response.items.first(where: { $0.title == "Use 2048" })
        )
        let request = try operationRequest(from: item)

        #expect(request.inputs == ["/tmp/first image.png", "/tmp/second.pdf"])
        #expect(
            request.action
                == .crop(size: "2048", smartCrop: false, longEdge: true)
        )
        #expect(item.subtitle.hasPrefix("Passed files:"))
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == "operation"
        )
    }

    @Test
    func exactPresetValueRanksBeforePartialMatches() throws {
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: "1920"
        )
        let request = try operationRequest(from: response.items[0])

        #expect(response.items[0].title == "Long edge 1920")
        #expect(
            request.action
                == .crop(size: "1920", smartCrop: false, longEdge: true)
        )
    }

    @Test(arguments: ["1200x630", "16:9", "128x0", "0x720"])
    func customNonLongEdgeValuesKeepSmartCropDisabled(value: String) throws {
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: value
        )
        let requests = try response.items
            .filter(\.valid)
            .map(operationRequest(from:))
        let request = try #require(requests.first(where: {
            $0.action == .crop(
                size: value,
                smartCrop: false,
                longEdge: false
            )
        }))

        #expect(
            request.action
                == .crop(size: value, smartCrop: false, longEdge: false)
        )
    }

    @Test
    func invalidCustomInputIsVisibleAndNonExecutable() throws {
        let response = CropParameterMenu.response(
            stateJSON: try cropStateJSON(context: .selected),
            query: "0x0"
        )

        #expect(response.items[0].title == "Invalid crop or resize value")
        #expect(response.items[0].valid == false)
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
