import Foundation
import Testing
@testable import AlfredClop

struct CropPDFParameterMenuTests {
    @Test
    func rootShowsThreeShallowBranches() throws {
        let response = try cropPDFResponse(query: "")

        #expect(response.items.map(\.title).prefix(3) == [
            "Custom Ratio / Resolution",
            "Apple Device",
            "Paper Size"
        ])
        #expect(response.items[0].autocomplete == "ratio: ")
        #expect(response.items[1].autocomplete == "device: ")
        #expect(response.items[2].autocomplete == "paper: ")
    }

    @Test
    func deviceBranchShowsAndFiltersClopList() throws {
        let response = try cropPDFResponse(query: "device: mini")
        let titles = response.items.map(\.title)

        #expect(titles.contains("iPad mini 6 & 7"))
        #expect(!titles.contains("iPhone 17 Pro Max & 16 Pro Max"))
        #expect(response.items.first?.subtitle.contains("Device") == true)
        #expect(response.items.first?.match?.contains("iPad mini 7") == true)
    }

    @Test
    func rootTypingRoutesToMatchingDeviceList() throws {
        let response = try cropPDFResponse(query: "mini")
        let titles = response.items.map(\.title)

        #expect(titles == ["iPad mini 6 & 7"])
    }

    @Test
    func paperBranchShowsAndFiltersClopList() throws {
        let response = try cropPDFResponse(query: "paper: letter")
        let titles = response.items.map(\.title)

        #expect(titles.contains("Letter & ANSI A/C/E (17:22)"))
        #expect(response.items.first?.match?.contains("ANSI A") == true)
    }

    @Test
    func rootTypingRoutesToMatchingPaperList() throws {
        let response = try cropPDFResponse(query: "letter")

        #expect(response.items.map(\.title) == [
            "Letter & ANSI A/C/E (17:22)"
        ])
    }

    @Test
    func emptyDeviceBranchShowsGuidanceInsteadOfFullList() throws {
        let response = try cropPDFResponse(query: "device: ")

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Type to search Apple devices")
        #expect(response.items[0].subtitle.contains("⌘L Reference"))
        #expect(response.items[0].text?.largetype?.contains("iPad") == true)
    }

    @Test
    func emptyRatioBranchShowsGuidanceThenRatioPresets() throws {
        let response = try cropPDFResponse(
            query: "ratio: ",
            presets: [
                .cropPDF(CropPDFActionPreset(request: CropPDFRequest(
                    target: .aspectRatio("2:3"),
                    pageLayout: .portrait
                ))),
                .cropPDF(CropPDFActionPreset(request: CropPDFRequest(
                    target: .paperSize("A4")
                )))
            ]
        )

        #expect(response.items.map(\.title) == [
            "Type a ratio or resolution",
            "2:3 · Portrait"
        ])
        #expect(response.items[0].valid == false)
        #expect(response.items[1].valid == true)
    }

    @Test
    func emptyListBranchesShowGuidanceThenScopedPresets() throws {
        let deviceResponse = try cropPDFResponse(
            query: "device: ",
            presets: [
                .cropPDF(CropPDFActionPreset(request: CropPDFRequest(
                    target: .device("iPad mini 6 & 7")
                )))
            ]
        )
        let paperResponse = try cropPDFResponse(
            query: "paper: ",
            presets: [
                .cropPDF(CropPDFActionPreset(request: CropPDFRequest(
                    target: .paperSize("A4")
                )))
            ]
        )

        #expect(deviceResponse.items.map(\.title) == [
            "Type to search Apple devices",
            "iPad mini 6 & 7"
        ])
        #expect(paperResponse.items.map(\.title) == [
            "Type to search paper sizes",
            "A4"
        ])
    }

    @Test
    func ratioQueryBuildsCropPDFOperation() throws {
        let response = try cropPDFResponse(query: "ratio: 32:18 landscape extend")
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)

        #expect(item.title == "16:9 · Landscape · Extend")
        #expect(operation.inputs == [
            "/tmp/first file.pdf",
            "/tmp/second file.pdf"
        ])
        #expect(operation.action == .cropPDF(CropPDFRequest(
            target: .aspectRatio("16:9"),
            pageLayout: .landscape,
            extend: true
        )))
        #expect(item.subtitle.hasPrefix("Passed 2 files ·"))
    }

    @Test
    func rootTypingRoutesRatioLikeInputToRatioBranch() throws {
        let response = try cropPDFResponse(query: "16:9 l e")
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)

        #expect(item.title == "16:9 · Landscape · Extend")
        #expect(operation.action == .cropPDF(CropPDFRequest(
            target: .aspectRatio("16:9"),
            pageLayout: .landscape,
            extend: true
        )))
    }

    @Test
    func listedTargetSupportsControlsEditor() throws {
        let response = try cropPDFResponse(
            query: "paper: A4 controls: portrait"
        )
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)

        #expect(item.title == "A4 · Portrait")
        #expect(operation.action == .cropPDF(CropPDFRequest(
            target: .paperSize("A4"),
            pageLayout: .portrait,
            extend: false
        )))
    }

    @Test
    func invalidRatioShowsOneVisibleError() throws {
        let response = try cropPDFResponse(query: "ratio: 1920")

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Invalid PDF crop ratio")
        #expect(response.items[0].valid == false)
    }

    @Test
    func invalidRatioStillShowsMatchingRatioPresets() throws {
        let response = try cropPDFResponse(
            query: "2",
            presets: [
                .cropPDF(CropPDFActionPreset(request: CropPDFRequest(
                    target: .aspectRatio("2:3"),
                    pageLayout: .portrait
                ))),
                .cropPDF(CropPDFActionPreset(request: CropPDFRequest(
                    target: .aspectRatio("1200x630")
                ))),
                .cropPDF(CropPDFActionPreset(request: CropPDFRequest(
                    target: .paperSize("A4")
                )))
            ]
        )

        #expect(response.items.map(\.title) == [
            "Invalid PDF crop ratio",
            "2:3 · Portrait",
            "1200x630"
        ])
    }

    @Test
    func listParserPreservesGroupsAndAliases() {
        let values = CropPDFTargetListParser.parse("""
        Devices, grouped by screen aspect ratio.
        iPhone:
          iPhone 17 Pro Max & 16 Pro Max
              "iPhone 17 Pro Max", "iPhone 16 Pro Max"
          iPhone Air

        iPad:
          iPad mini 6 & 7
              "iPad mini 7", "iPad mini 6"
        """)

        #expect(values == [
            CropPDFTargetValue(
                value: "iPhone 17 Pro Max & 16 Pro Max",
                category: "iPhone",
                aliases: ["iPhone 17 Pro Max", "iPhone 16 Pro Max"]
            ),
            CropPDFTargetValue(
                value: "iPhone Air",
                category: "iPhone",
                aliases: []
            ),
            CropPDFTargetValue(
                value: "iPad mini 6 & 7",
                category: "iPad",
                aliases: ["iPad mini 7", "iPad mini 6"]
            )
        ])
    }

    private func cropPDFResponse(
        query: String,
        presets: [ActionPreset] = []
    ) throws -> ScriptFilterResponse {
        let dataDirectory = try makeTemporaryDirectory()
        let store = PresetStore(
            fileURL: dataDirectory.appendingPathComponent("settings.json")
        )
        for preset in presets {
            _ = try store.save(preset)
        }
        return CropPDFParameterMenu.response(
            stateJSON: try JSONOutput.string(
                for: MenuState.cropPDF(parameterRequest()),
                prettyPrinted: false
            ),
            query: query,
            environment: Environment(values: [
                "alfred_workflow_data": dataDirectory.path
            ]),
            targetProvider: StubCropPDFTargetProvider()
        )
    }

    private func parameterRequest() -> ParameterStepRequest {
        ParameterStepRequest(
            action: .cropPDF,
            inputs: ["/tmp/first file.pdf", "/tmp/second file.pdf"],
            inputContext: .arguments,
            mediaKinds: [.pdf],
            itemKinds: [.localFile, .localFile]
        )
    }

    private func operationRequest(from item: ScriptFilterItem) throws -> OperationRequest {
        try JSONDecoder().decode(
            OperationRequest.self,
            from: Data(try #require(item.arg).utf8)
        )
    }
}

private struct StubCropPDFTargetProvider: CropPDFTargetProviding {
    func devices() throws -> [CropPDFTargetValue] {
        [
            CropPDFTargetValue(
                value: "iPhone 17 Pro Max & 16 Pro Max",
                category: "iPhone",
                aliases: ["iPhone 17 Pro Max", "iPhone 16 Pro Max"]
            ),
            CropPDFTargetValue(
                value: "iPad mini 6 & 7",
                category: "iPad",
                aliases: ["iPad mini 7", "iPad mini 6"]
            )
        ]
    }

    func paperSizes() throws -> [CropPDFTargetValue] {
        [
            CropPDFTargetValue(
                value: "A4",
                category: "ISO",
                aliases: []
            ),
            CropPDFTargetValue(
                value: "Letter & ANSI A/C/E (17:22)",
                category: "US",
                aliases: ["Letter", "ANSI A", "ANSI C", "ANSI E"]
            )
        ]
    }
}
