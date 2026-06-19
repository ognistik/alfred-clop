import Foundation
import Testing
@testable import AlfredClop

struct ConversionParameterMenuTests {
    @Test
    func rootFormatsExecuteImmediatelyAndExposeShallowControls() throws {
        let fixture = try fixture(
            action: .convertImage,
            input: "/tmp/photo.png"
        )

        let response = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "",
            environment: fixture.environment
        )
        let webp = try #require(response.items.first {
            $0.title == "Convert to WebP"
        })
        let decoded = try decodedOperation(webp.arg)

        #expect(decoded.action == .convert(ConversionChoice(
            media: .image,
            format: "webp"
        )))
        #expect(webp.autocomplete == "webp ")
        #expect(webp.subtitle.contains("⇥ Controls"))
        #expect(
            webp.mods?.control?.subtitle
                == "Controls"
        )
        #expect(webp.mods?.shift != nil)
    }

    @Test
    func tabStyleQueryAcceptsDirectCompressionInput() throws {
        let fixture = try fixture(
            action: .convertImage,
            input: "/tmp/photo.png"
        )

        let empty = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "webp ",
            environment: fixture.environment
        )
        let typed = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "webp 70",
            environment: fixture.environment
        )

        #expect(
            empty.items.first?.title
                == "Convert to WebP"
        )
        #expect(empty.items.first?.subtitle.contains("Use compression 5-100") == true)
        #expect(empty.items.first?.subtitle.contains("⏎ Run Defaults") == true)
        #expect(typed.items.first?.title == "Convert to WebP · Compression 70")
        #expect(try decodedOperation(typed.items.first?.arg).action == .convert(
            ConversionChoice(
                media: .image,
                format: "webp",
                setting: .compression(70)
            )
        ))
        #expect(
            typed.items.first?.mods?.control?.subtitle
                == "Save Preset WebP · Compression 70"
        )
    }

    @Test
    func imageBranchDistinguishesPartialAndInvalidCompression() throws {
        let fixture = try fixture(
            action: .convertImage,
            input: "/tmp/photo.png"
        )

        let partial = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "webp 1",
            environment: fixture.environment
        )
        let invalid = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "webp 500",
            environment: fixture.environment
        )

        #expect(partial.items.first?.title == "Type compression value")
        #expect(invalid.items.first?.title == "Invalid conversion control")
    }

    @Test
    func controlEntryUsesSameVisibleQueryAsTab() throws {
        let fixture = try fixture(
            action: .convertImage,
            input: "/tmp/photo.png"
        )
        let root = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "",
            environment: fixture.environment
        )
        let webp = try #require(root.items.first {
            $0.title == "Convert to WebP"
        })
        let control = try #require(webp.mods?.control)
        let controlState = try #require(
            webp.mods?.control?.variables?[ActionMenu.menuStateVariable]
        )

        let controls = ConversionParameterMenu.response(
            stateJSON: controlState,
            query: try #require(control.arg),
            environment: fixture.environment
        )

        #expect(control.arg == "webp ")
        #expect(
            control.variables?[ActionMenu.requestKindVariable]
                == WorkflowRequestKind.parameterStepQuery.rawValue
        )
        #expect(
            controls.items.first?.title
                == "Convert to WebP"
        )
        #expect(!controls.items.contains {
            $0.title == "Back to conversion formats"
        })
    }

    @Test
    func audioControlsRequireExplicitCompressionOrBitratePrefix() throws {
        let fixture = try fixture(
            action: .convertAudio,
            input: "/tmp/audio.wav"
        )

        let ambiguous = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "mp3 128",
            environment: fixture.environment
        )
        let compression = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "mp3 c70",
            environment: fixture.environment
        )
        let bitrate = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "mp3 b128",
            environment: fixture.environment
        )

        #expect(ambiguous.items.first?.title == "Invalid conversion control")
        #expect(ambiguous.items.first?.subtitle.contains(
            "Use compression (e.g. c70) / bitrate (e.g. b128)"
        ) == true)
        #expect(try decodedOperation(compression.items.first?.arg).action == .convert(
            ConversionChoice(
                media: .audio,
                format: "mp3",
                setting: .compression(70)
            )
        ))
        #expect(try decodedOperation(bitrate.items.first?.arg).action == .convert(
            ConversionChoice(
                media: .audio,
                format: "mp3",
                setting: .bitrate(128)
            )
        ))
    }

    @Test
    func onlyMP4OffersVideoCompressionControls() throws {
        let fixture = try fixture(
            action: .convertVideo,
            input: "/tmp/video.mov"
        )
        let response = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "",
            environment: fixture.environment
        )
        let mp4 = try #require(response.items.first {
            $0.title == "Convert to MP4 / H.264"
        })
        let gif = try #require(response.items.first {
            $0.title == "Convert to GIF"
        })

        #expect(mp4.autocomplete == "mp4 ")
        #expect(mp4.mods?.control != nil)
        #expect(gif.autocomplete == "gif")
        #expect(gif.mods?.control == nil)
    }

    @Test
    func presetCanBeSavedExecutedAndRemoved() throws {
        let fixture = try fixture(
            action: .convertImage,
            input: "/tmp/photo.png"
        )
        let typed = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "webp 70",
            environment: fixture.environment
        )
        let saveState = try #require(
            typed.items.first?.mods?.control?
                .variables?[ActionMenu.menuStateVariable]
        )

        let saved = ConversionParameterMenu.response(
            stateJSON: saveState,
            query: "",
            environment: fixture.environment
        )
        #expect(saved.items.contains {
            $0.title == "Convert to WebP"
        })
        let preset = try #require(saved.items.first {
            $0.title == "WebP · Compression 70"
        })
        #expect(preset.autocomplete == "webp 70")
        let exact = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "webp 70",
            environment: fixture.environment
        )
        #expect(
            exact.items.first?.subtitle
                == "Passed file · Saved Preset · ⌃↩ Remove Preset · ⌘L Reference"
        )
        let confirmationState = try #require(
            preset.mods?.control?
                .variables?[ActionMenu.menuStateVariable]
        )
        let confirmation = ConversionParameterMenu.response(
            stateJSON: confirmationState,
            query: "",
            environment: fixture.environment
        )
        #expect(confirmation.items.map(\.title) == [
            "Remove Preset WebP · Compression 70?",
            "Cancel"
        ])

        let cancelState = try #require(
            confirmation.items[1]
                .variables?[ActionMenu.menuStateVariable]
        )
        let cancelled = ConversionParameterMenu.response(
            stateJSON: cancelState,
            query: "",
            environment: fixture.environment
        )
        #expect(cancelled.items.contains {
            $0.title == "WebP · Compression 70"
        })
        #expect(try fixture.store.load().presets.count == 1)

        let removalState = try #require(
            confirmation.items.first?
                .variables?[ActionMenu.menuStateVariable]
        )
        let removed = ConversionParameterMenu.response(
            stateJSON: removalState,
            query: "",
            environment: fixture.environment
        )

        #expect(try fixture.store.load().presets.isEmpty)
        #expect(removed.items.contains {
            $0.title == "Convert to WebP"
        })
    }

    @Test
    func formatBranchKeepsGuidanceBeforeMatchingPresets() throws {
        let fixture = try fixture(
            action: .convertAudio,
            input: "/tmp/audio.wav"
        )
        _ = try fixture.store.save(.conversion(ConversionActionPreset(
            choice: ConversionChoice(
                media: .audio,
                format: "mp3",
                setting: .bitrate(128)
            )
        )))

        let response = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "mp3 b",
            environment: fixture.environment
        )

        #expect(response.items.map(\.title) == [
            "Type audio conversion control",
            "MP3 · 128 kbps"
        ])
        #expect(response.items.first?.subtitle.contains(
            "Use compression (e.g. c70) / bitrate (e.g. b128)"
        ) == true)
        #expect(response.items[1].autocomplete == "mp3 b128")
    }

    @Test
    func largeTypeUsesConsistentInputHeadingSpacing() throws {
        let fixture = try fixture(
            action: .convertImage,
            input: "/tmp/photo.png"
        )

        let response = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "webp ",
            environment: fixture.environment
        )
        let largeType = try #require(response.items.first?.text?.largetype)

        #expect(largeType.contains("\n\nInputs\n/tmp/photo.png"))
        #expect(!largeType.contains("\n\nInputs\n\n/tmp/photo.png"))
    }

    @Test
    func matchingImageFormatIsHiddenButSavedRecompressionRemains() throws {
        let fixture = try fixture(
            action: .convertImage,
            input: "/tmp/photo.jpg"
        )
        _ = try fixture.store.save(.conversion(ConversionActionPreset(
            choice: ConversionChoice(
                media: .image,
                format: "jpeg",
                setting: .compression(80)
            )
        )))

        let response = ConversionParameterMenu.response(
            stateJSON: fixture.stateJSON,
            query: "",
            environment: fixture.environment
        )

        #expect(!response.items.contains {
            $0.title == "Convert to JPEG"
        })
        #expect(response.items.contains {
            $0.title == "JPEG · Compression 80"
        })
    }

    @Test
    func mixedExtensionsAndFoldersKeepAllFormatsVisible() throws {
        let mixed = try fixture(
            action: .convertImage,
            inputs: ["/tmp/photo.png", "/tmp/photo.jpg"],
            itemKinds: [.localFile, .localFile]
        )
        let folder = try fixture(
            action: .convertImage,
            inputs: ["/tmp/Images"],
            itemKinds: [.folder]
        )

        for fixture in [mixed, folder] {
            let response = ConversionParameterMenu.response(
                stateJSON: fixture.stateJSON,
                query: "",
                environment: fixture.environment
            )
            #expect(response.items.contains { $0.title == "Convert to PNG" })
            #expect(response.items.contains { $0.title == "Convert to JPEG" })
        }
    }

    private func fixture(
        action: ClopAction,
        input: String
    ) throws -> ConversionMenuFixture {
        try fixture(
            action: action,
            inputs: [input],
            itemKinds: [.localFile]
        )
    }

    private func fixture(
        action: ClopAction,
        inputs: [String],
        itemKinds: [InputItemKind]
    ) throws -> ConversionMenuFixture {
        let directory = try makeTemporaryDirectory()
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: directory.path
        ])
        let request = ParameterStepRequest(
            action: action,
            inputs: inputs,
            inputContext: .arguments,
            itemKinds: itemKinds
        )
        return ConversionMenuFixture(
            environment: environment,
            store: try PresetStore(environment: environment),
            stateJSON: try JSONOutput.string(
                for: MenuState.conversion(request),
                prettyPrinted: false
            )
        )
    }

    private func decodedOperation(_ value: String?) throws -> OperationRequest {
        try JSONDecoder().decode(
            OperationRequest.self,
            from: Data(try #require(value).utf8)
        )
    }
}

private struct ConversionMenuFixture {
    var environment: Environment
    var store: PresetStore
    var stateJSON: String
}
