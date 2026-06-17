import Foundation
import Testing

@testable import AlfredClop

struct OptimizeParameterMenuTests {
    @Test
    func homogeneousInputShowsDefaultOptimizeAndControlsEntry() throws {
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/photo.png"],
            mediaKinds: [.image],
            itemKinds: [.localFile]
        )
        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: ""
        )
        let item = try #require(response.items.first)
        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((try #require(item.arg)).utf8)
        )

        #expect(item.title == "Optimize Image with Defaults")
        #expect(item.subtitle.contains("⇥ Controls"))
        #expect(item.subtitle.contains("Use compression 5-100 / ad"))
        #expect(item.subtitle.contains("⏎ Run Defaults"))
        #expect(item.autocomplete == "controls: ")
        #expect(item.mods?.control?.arg == "controls: ")
        #expect(
            item.mods?.control?.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.parameterStepQuery.rawValue
        )
        #expect(operation.action == .optimise(aggressive: false))
        #expect(
            item.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.operation.rawValue
        )
    }

    @Test
    func mixedInputShowsMediaControlPrefixesWithoutPresets() throws {
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/photo.png", "/tmp/movie.mp4"],
            mediaKinds: [.image, .video],
            itemKinds: [.localFile, .localFile]
        )
        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: ""
        )

        #expect(response.items.map(\.title) == [
            "Optimize All with Defaults",
            "Image Optimize Controls",
            "Video Optimize Controls"
        ])
        #expect(response.items[1].autocomplete == "image controls: ")
        #expect(response.items[2].autocomplete == "video controls: ")
    }

    @Test
    func mediaControlPrefixShowsFocusedLargeTypeReference() throws {
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/photo.png", "/tmp/movie.mp4"],
            mediaKinds: [.image, .video],
            itemKinds: [.localFile, .localFile]
        )
        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "video controls: "
        )
        let item = try #require(response.items.first)

        #expect(item.title == "Type video controls")
        #expect(item.subtitle.contains(
            "Use 5-100 / au + encoder + m + 2x"
        ))
        #expect(item.text?.largetype?.contains("Video Optimize controls") == true)
        #expect(item.text?.largetype?.contains("spaces or commas") == true)
    }

    @Test
    func validMediaControlsBuildTypedOptimizeRequest() throws {
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/movie with spaces.mp4"],
            mediaKinds: [.video],
            itemKinds: [.localFile]
        )
        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "70, ad, m, 1.5x"
        )
        let item = try #require(response.items.first)
        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((try #require(item.arg)).utf8)
        )

        #expect(item.title == "Optimize Video · Compression 70 · Encoder adaptive · Mute · 1.5x speed")
        #expect(operation.action == .optimiseMedia(OptimizeRequest(
            media: .video,
            controls: .video(VideoOptimizeControls(
                compression: .value(70),
                encoder: .adaptive,
                removeAudio: true,
                playbackSpeed: 1.5
            ))
        )))
        #expect(item.mods?.control?.subtitle?.contains("Save Preset") == true)
        #expect(!item.subtitle.contains("Use 5-100 / au"))
    }

    @Test
    func ambiguousMediaControlsPreserveTheFullInputBatch() throws {
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: [
                "https://example.com/photo.jpg",
                "https://example.com/download"
            ],
            mediaKinds: [.image],
            itemKinds: [.remoteURL, .remoteURL],
            ambiguousKinds: [.remoteURL]
        )
        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "video controls: m"
        )
        let item = try #require(response.items.first)
        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((try #require(item.arg)).utf8)
        )

        #expect(item.title == "Optimize Video · Mute")
        #expect(operation.inputs == request.inputs)
        #expect(operation.action == .optimiseMedia(OptimizeRequest(
            media: .video,
            controls: .video(VideoOptimizeControls(removeAudio: true))
        )))
    }

    @Test
    func homogeneousOptimizeTreatsTypedQueryAsControls() throws {
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/movie.mp4"],
            mediaKinds: [.video],
            itemKinds: [.localFile]
        )

        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "70 sw m"
        )
        let item = try #require(response.items.first)
        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((try #require(item.arg)).utf8)
        )

        #expect(item.title == "Optimize Video · Compression 70 · Encoder software · Mute")
        #expect(operation.action == .optimiseMedia(OptimizeRequest(
            media: .video,
            controls: .video(VideoOptimizeControls(
                compression: .value(70),
                encoder: .software,
                removeAudio: true
            ))
        )))
    }

    @Test
    func homogeneousVideoControlsStayFirstBeforeMatchingPresets() throws {
        let fixture = try OptimizePresetFixture()
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(compression: .value(55)))
            )
        )))
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(
                    compression: .value(55),
                    removeAudio: true
                ))
            )
        )))
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(compression: .value(100)))
            )
        )))
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/movie.mp4"],
            mediaKinds: [.video],
            itemKinds: [.localFile]
        )

        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "5",
            environment: fixture.environment
        )

        #expect(response.items.first?.title == "Optimize Video · Compression 5")
        #expect(response.items.first?.subtitle == "Selected file · ⌃↩ Save Preset")
        #expect(response.items.dropFirst().map(\.title).contains(
            "Video · Compression 55"
        ))

        let partial = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "1",
            environment: fixture.environment
        )

        #expect(partial.items.first?.title == "Type video controls")
        #expect(partial.items.first?.subtitle.contains(
            "Use 5-100 / au + encoder + m + 2x"
        ) == true)
        #expect(partial.items.dropFirst().map(\.title).contains(
            "Video · Compression 100"
        ))
    }

    @Test
    func invalidAndConflictingControlsShowGuidance() throws {
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/audio.wav"],
            mediaKinds: [.audio],
            itemKinds: [.localFile]
        )
        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "controls: 70 b128"
        )

        #expect(response.items.first?.title == "Invalid Optimize controls")
        #expect(response.items.first?.subtitle == "Selected file · Use compression 5-100 / bitrate (e.g. b128) · ⌘L Reference")
    }

    @Test
    func emptyControlsShowsGuidanceRowAndScopedPresets() throws {
        let fixture = try OptimizePresetFixture()
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .image,
                controls: .image(ImageOptimizeControls(compression: .adaptive))
            )
        )))
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(encoder: .software))
            )
        )))
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/photo.png"],
            mediaKinds: [.image],
            itemKinds: [.localFile]
        )

        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "controls: ",
            environment: fixture.environment
        )

        #expect(response.items[0].title == "Type a number from 5 to 100")
        #expect(response.items[0].subtitle.contains(
            "Use compression 5-100 / ad"
        ))
        #expect(response.items[0].valid == false)
        #expect(response.items.map(\.title).contains("Image · Adaptive"))
        #expect(!response.items.map(\.title).contains("Video · Encoder software"))
    }

    @Test
    func rootMenuShowsAndFiltersScopedPresetsWithoutControlsQuery() throws {
        let fixture = try OptimizePresetFixture()
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .image,
                controls: .image(ImageOptimizeControls(compression: .adaptive))
            )
        )))
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(encoder: .software))
            )
        )))
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/photo.png"],
            mediaKinds: [.image],
            itemKinds: [.localFile]
        )

        let response = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "",
            environment: fixture.environment
        )

        #expect(response.items.map(\.title).contains("Optimize Image with Defaults"))
        let imagePreset = try #require(response.items.first {
            $0.title == "Image · Adaptive"
        })
        #expect(imagePreset.autocomplete == "image controls: ad")
        #expect(!response.items.map(\.title).contains("Video · Encoder software"))

        let filtered = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "adaptive",
            environment: fixture.environment
        )

        #expect(filtered.items.map(\.title) == ["Optimize Image · Adaptive"])
        #expect(filtered.items.first?.subtitle.contains("Saved Preset") == true)
    }

    @Test
    func controlsFilterSavedPresetsAndMarkExactMatches() throws {
        let fixture = try OptimizePresetFixture()
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .image,
                controls: .image(ImageOptimizeControls(compression: .adaptive))
            )
        )))
        _ = try fixture.store.save(.optimize(OptimizeActionPreset(
            request: OptimizeRequest(
                media: .image,
                controls: .image(ImageOptimizeControls(compression: .value(70)))
            )
        )))
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/photo.png"],
            mediaKinds: [.image],
            itemKinds: [.localFile]
        )

        let invalidMatchingPreset = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "controls: image adaptive",
            environment: fixture.environment
        )
        #expect(invalidMatchingPreset.items.map(\.title) == ["Image · Adaptive"])

        let exact = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "controls: ad",
            environment: fixture.environment
        )
        #expect(exact.items.first?.title == "Optimize Image · Adaptive")
        #expect(
            exact.items.first?.subtitle
                == "Selected file · Saved Preset · ⌃↩ Remove Preset"
        )
        #expect(
            exact.items.first?.mods?.control?.subtitle
                == "Remove Preset Image · Adaptive"
        )
    }

    @Test
    func presetCanBeSavedExecutedAndRemoved() throws {
        let fixture = try OptimizePresetFixture()
        let request = ParameterStepRequest(
            action: .optimise,
            inputs: ["/tmp/document.pdf"],
            mediaKinds: [.pdf],
            itemKinds: [.localFile]
        )
        let typed = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "controls: 150",
            environment: fixture.environment
        )
        let saveState = try #require(
            typed.items.first?.mods?.control?.arg
        )

        let afterSave = OptimizeParameterMenu.response(
            stateJSON: saveState,
            query: "controls: 150",
            environment: fixture.environment
        )
        #expect(afterSave.items.map(\.title).contains("Optimize PDF with Defaults"))
        #expect(afterSave.items.map(\.title).contains("PDF · 150 DPI"))
        #expect(!afterSave.items.map(\.title).contains("Type a DPI value"))
        let cleanStateAfterSave = try #require(
            afterSave.variables?[ActionMenu.menuStateVariable]
        )
        let controlsAfterSave = OptimizeParameterMenu.response(
            stateJSON: cleanStateAfterSave,
            query: "controls: ",
            environment: fixture.environment
        )
        #expect(controlsAfterSave.items.first?.title == "Type a DPI value")
        #expect(try fixture.store.load().presets == [
            .optimize(OptimizeActionPreset(request: OptimizeRequest(
                media: .pdf,
                controls: .pdf(PDFOptimizeControls(dpi: .value(150)))
            )))
        ])

        let saved = OptimizeParameterMenu.response(
            stateJSON: try stateJSON(for: request),
            query: "",
            environment: fixture.environment
        )
        let preset = try #require(saved.items.first {
            $0.uid == "optimize.preset.pdf.dpi.150"
        })
        let operation = try JSONDecoder().decode(
            OperationRequest.self,
            from: Data((try #require(preset.arg)).utf8)
        )
        #expect(operation.action == .optimiseMedia(OptimizeRequest(
            media: .pdf,
            controls: .pdf(PDFOptimizeControls(dpi: .value(150)))
        )))

        let confirmState = try #require(preset.mods?.control?.arg)
        let confirmation = OptimizeParameterMenu.response(
            stateJSON: confirmState,
            query: "",
            environment: fixture.environment
        )
        #expect(confirmation.items.map(\.title) == [
            "Remove Preset PDF · 150 DPI?",
            "Cancel"
        ])
        let cancelState = try #require(
            confirmation.items[1].variables?[ActionMenu.menuStateVariable]
        )
        let cancelled = OptimizeParameterMenu.response(
            stateJSON: cancelState,
            query: "",
            environment: fixture.environment
        )
        #expect(cancelled.items.map(\.title).contains("PDF · 150 DPI"))
        #expect(try fixture.store.load().presets.count == 1)

        let removeState = try #require(confirmation.items.first?.arg)
        let afterRemove = OptimizeParameterMenu.response(
            stateJSON: removeState,
            query: "",
            environment: fixture.environment
        )
        let cleanStateAfterRemove = try #require(
            afterRemove.variables?[ActionMenu.menuStateVariable]
        )
        let controlsAfterRemove = OptimizeParameterMenu.response(
            stateJSON: cleanStateAfterRemove,
            query: "controls: ",
            environment: fixture.environment
        )
        #expect(controlsAfterRemove.items.first?.title == "Type a DPI value")
        #expect(try fixture.store.load().presets.isEmpty)
    }

    private func stateJSON(for request: ParameterStepRequest) throws -> String {
        try JSONOutput.string(
            for: MenuState.optimise(request),
            prettyPrinted: false
        )
    }
}

private struct OptimizePresetFixture {
    let directory: URL
    let environment: Environment
    let store: PresetStore

    init() throws {
        directory = try makeTemporaryDirectory()
            .appendingPathComponent("Optimize Preset Data", isDirectory: true)
        environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        store = try PresetStore(environment: environment)
    }
}
