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
        #expect(response.items[0].subtitle.contains("Use ratio: for 16:9 or 1200x630") == true)
        #expect(response.items[1].subtitle.contains("Search Clop's device list") == true)
        #expect(response.items[2].subtitle.contains("Search Clop's paper list") == true)
        #expect(response.items[0].autocomplete == "ratio: ")
        #expect(response.items[1].autocomplete == "device: ")
        #expect(response.items[2].autocomplete == "paper: ")
    }

    @Test
    func deviceBranchShowsAndFiltersClopList() throws {
        let response = try cropPDFResponse(query: "device: mini")
        let titles = response.items.map(\.title)

        #expect(titles.contains("Device iPad mini 6 & 7"))
        #expect(!titles.contains("Device iPhone 17 Pro Max & 16 Pro Max"))
        #expect(response.items.first?.subtitle.contains("Device") == false)
        #expect(response.items.first?.subtitle.contains("⇥ Controls · ⌃↩ Save Preset") == true)
        #expect(response.items.first?.match?.contains("iPad mini 7") == true)
    }

    @Test
    func rootTypingRoutesToMatchingDeviceList() throws {
        let response = try cropPDFResponse(query: "mini")
        let titles = response.items.map(\.title)

        #expect(titles == ["Device iPad mini 6 & 7"])
    }

    @Test
    func paperBranchShowsAndFiltersClopList() throws {
        let response = try cropPDFResponse(query: "paper: letter")
        let titles = response.items.map(\.title)

        #expect(titles.contains("Paper Letter"))
        let operation = try operationRequest(from: try #require(response.items.first))
        #expect(operation.action == .cropPDF(CropPDFRequest(
            target: .paperSize("Letter")
        )))
    }

    @Test
    func rootTypingRoutesToMatchingPaperList() throws {
        let response = try cropPDFResponse(query: "letter")

        #expect(response.items.map(\.title) == ["Paper Letter"])
    }

    @Test
    func paperAliasesAreFirstClassTargets() throws {
        let a5Response = try cropPDFResponse(query: "A5")
        let b11Response = try cropPDFResponse(query: "paper: B11")
        let halfLetterResponse = try cropPDFResponse(query: "Half Letter portrait")

        #expect(a5Response.items.first?.title == "Paper A5")

        let b11Operation = try operationRequest(
            from: try #require(b11Response.items.first)
        )
        let halfLetterOperation = try operationRequest(
            from: try #require(halfLetterResponse.items.first)
        )

        #expect(b11Operation.action == .cropPDF(CropPDFRequest(
            target: .paperSize("B11")
        )))
        #expect(halfLetterOperation.action == .cropPDF(CropPDFRequest(
            target: .paperSize("Half Letter"),
            pageLayout: .portrait
        )))
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
            "Ratio 2:3 · Portrait"
        ])
        #expect(response.items[0].valid == false)
        #expect(response.items[0].subtitle.contains("Use 16:9 / 1200x630") == true)
        #expect(response.items[1].valid == true)
        #expect(response.items[1].subtitle == "Passed 2 files · Saved Preset · ⌃↩ Remove Preset")
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
            "Device iPad mini 6 & 7"
        ])
        #expect(paperResponse.items.map(\.title) == [
            "Type to search paper sizes",
            "Paper A4"
        ])
    }

    @Test
    func ratioQueryBuildsCropPDFOperation() throws {
        let response = try cropPDFResponse(query: "ratio: 32:18 landscape extend")
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)

        #expect(item.title == "Ratio 16:9 · Landscape · Extend")
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
    func executableRowsExposeShiftOutputTemplateToggle() throws {
        let response = try cropPDFResponse(query: "ratio: 16:9")
        let item = try #require(response.items.first)
        let shift = try #require(item.mods?.shift)
        let operation = try operationRequest(from: shift)

        #expect(shift.subtitle == "Passed 2 files · Output Template")
        #expect(shift.variables?[ActionMenu.requestKindVariable]
            == WorkflowRequestKind.operation.rawValue)
        #expect(operation.action == .cropPDF(CropPDFRequest(
            target: .aspectRatio("16:9")
        )))
        #expect(operation.execution.output == .sameFolder(template: "%P/%f-clop"))
    }

    @Test
    func shiftOutputToggleCanReplaceOriginalsWhenPreserveIsConfigured() throws {
        let response = try cropPDFResponse(
            query: "ratio: 16:9",
            preserveOriginal: true
        )
        let shift = try #require(response.items.first?.mods?.shift)
        let operation = try operationRequest(from: shift)

        #expect(shift.subtitle == "Passed 2 files · Replace Originals")
        #expect(operation.execution.output == .inPlace)
    }

    @Test
    func rootTypingRoutesRatioLikeInputToRatioBranch() throws {
        let response = try cropPDFResponse(query: "16:9 l e")
        let item = try #require(response.items.first)
        let operation = try operationRequest(from: item)

        #expect(item.title == "Ratio 16:9 · Landscape · Extend")
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

        #expect(item.title == "Paper A4 · Portrait")
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
        #expect(response.items[0].subtitle.contains("Use 16:9 / 1200x630") == true)
        #expect(response.items[0].subtitle.contains("optional controls") == false)
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
            "Ratio 2:3 · Portrait",
            "Resolution 1200x630"
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

    @Test
    func listParserCanExpandPaperAliasesIntoTargets() {
        let values = CropPDFTargetListParser.parse("""
        Paper sizes, grouped by aspect ratio.
        Both group names and paper size names are accepted.
        ISO:
          A & B series (1:√2)
              "A4", "A5", "B11"

        US:
          Tabloid & Ledger & ANSI B/D (11:17)
              "Tabloid", "Ledger", "Half Letter", "ANSI B", "ANSI D"
        """, expandsAliases: true)

        #expect(values.contains(CropPDFTargetValue(
            value: "A & B series (1:√2)",
            category: "ISO",
            aliases: []
        )))
        #expect(values.contains(CropPDFTargetValue(
            value: "A5",
            category: "ISO",
            aliases: ["A & B series (1:√2)"]
        )))
        #expect(values.contains(CropPDFTargetValue(
            value: "B11",
            category: "ISO",
            aliases: ["A & B series (1:√2)"]
        )))
        #expect(values.contains(CropPDFTargetValue(
            value: "Half Letter",
            category: "US",
            aliases: ["Tabloid & Ledger & ANSI B/D (11:17)"]
        )))
    }

    private func cropPDFResponse(
        query: String,
        presets: [ActionPreset] = [],
        preserveOriginal: Bool = false
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
                "alfred_workflow_data": dataDirectory.path,
                "preserveOriginal": preserveOriginal ? "true" : "false"
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

    private func operationRequest(from modifier: ScriptFilterModifier) throws -> OperationRequest {
        try JSONDecoder().decode(
            OperationRequest.self,
            from: Data(try #require(modifier.arg).utf8)
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
                value: "A5",
                category: "ISO",
                aliases: ["A & B series (1:√2)"]
            ),
            CropPDFTargetValue(
                value: "B11",
                category: "ISO",
                aliases: ["A & B series (1:√2)"]
            ),
            CropPDFTargetValue(
                value: "Letter & ANSI A/C/E (17:22)",
                category: "US",
                aliases: []
            ),
            CropPDFTargetValue(
                value: "Letter",
                category: "US",
                aliases: ["Letter & ANSI A/C/E (17:22)", "ANSI A"]
            ),
            CropPDFTargetValue(
                value: "Half Letter",
                category: "US",
                aliases: ["Tabloid & Ledger & ANSI B/D (11:17)"]
            )
        ]
    }
}
