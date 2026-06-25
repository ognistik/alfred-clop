import Foundation
import Testing
@testable import AlfredClop

struct PublicRequestParserTests {
    @Test
    func barePathsOpenMainMenuAsExactItems() throws {
        let request = try PublicRequestParser.parse("""
        /tmp/first image.jpg
        https://example.com/second image.jpg?size=large
        """)

        #expect(request == ClopRequest(
            input: .explicit(
                items: [
                    "/tmp/first image.jpg",
                    "https://example.com/second image.jpg?size=large"
                ],
                extractText: false
            ),
            route: .menu(action: nil)
        ))
    }

    @Test
    func explicitInputLinesPreserveSignificantSpaces() throws {
        let request = try PublicRequestParser.parse(
            "/tmp/ leading.jpg\n/tmp/trailing.jpg "
        )

        #expect(request.input == .explicit(
            items: ["/tmp/ leading.jpg", "/tmp/trailing.jpg "],
            extractText: false
        ))
    }

    @Test(arguments: [
        ("finder", ClopInputRequest.finderSelection),
        ("clipboard", ClopInputRequest.clipboard)
    ])
    func bareNamedSourcesOpenMainMenu(
        value: String,
        input: ClopInputRequest
    ) throws {
        #expect(try PublicRequestParser.parse(value) == ClopRequest(
            input: input,
            route: .menu(action: nil)
        ))
    }

    @Test(arguments: [
        ("optimize:", ClopAction.optimise),
        ("crop:", ClopAction.crop),
        ("downscale:", ClopAction.downscale),
        ("convert image:", ClopAction.convertImage),
        ("convert video:", ClopAction.convertVideo),
        ("convert audio:", ClopAction.convertAudio),
        ("crop pdf:", ClopAction.cropPDF),
        ("uncrop pdf:", ClopAction.uncropPDF),
        ("strip metadata:", ClopAction.stripMetadata)
    ])
    func workflowShortcutsOpenActionMenus(
        directive: String,
        action: ClopAction
    ) throws {
        let request = try PublicRequestParser.parse("""
        \(directive)

        finder
        """)

        #expect(request == ClopRequest(
            input: .finderSelection,
            route: .menu(action: action)
        ))
    }

    @Test
    func visibleWorkflowTitleOpensCropMenuCaseInsensitively() throws {
        let request = try PublicRequestParser.parse("""
        menu: cRoP / ReSiZe

        clipboard
        """)

        #expect(request == ClopRequest(
            input: .clipboard,
            route: .menu(action: .crop)
        ))
    }

    @Test
    func configurationDirectiveOpensConfigurationNamespace() throws {
        let request = try PublicRequestParser.parse("""
        menu: Configuration

        clipboard
        """)

        #expect(request == ClopRequest(
            input: .clipboard,
            route: .configuration
        ))
    }

    @Test
    func optimizeExecutionDefaultsAggressiveToFalse() throws {
        let request = try PublicRequestParser.parse("""
        execute: Optimize

        /tmp/image.jpg
        """)

        #expect(request == ClopRequest(
            input: .explicit(items: ["/tmp/image.jpg"], extractText: false),
            route: .execute(action: .optimise(aggressive: false))
        ))
    }

    @Test
    func optimizeExecutionAcceptsReadableBooleanValues() throws {
        let request = try PublicRequestParser.parse("""
        execute: Optimize
        aggressive: yes

        clipboard
        """)

        #expect(request == ClopRequest(
            input: .clipboard,
            route: .execute(action: .optimise(aggressive: true))
        ))
    }

    @Test
    func optimizeExecutionAcceptsMediaControls() throws {
        let request = try PublicRequestParser.parse("""
        execute: Optimize
        media: video
        controls: 70, sw, m
        playback speed: 2

        /tmp/movie.mp4
        """)

        #expect(request.route == .execute(action: .optimiseMedia(
            OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(
                    compression: .value(70),
                    encoder: .software,
                    removeAudio: true,
                    playbackSpeed: 2
                ))
            )
        )))
    }

    @Test
    func optimizeExecutionRejectsConflictingControlsAndPresets() {
        #expect(throws: PublicRequestError.invalidParameter(
            "Optimize controls",
            "70 b128"
        )) {
            try PublicRequestParser.parse("""
            execute: Optimize
            media: audio
            controls: 70 b128

            /tmp/audio.wav
            """)
        }
        #expect(throws: PublicRequestError.unexpectedParameter("preset")) {
            try PublicRequestParser.parse("""
            execute: Optimize
            media: image
            preset: ad

            /tmp/image.png
            """)
        }
    }

    @Test
    func cropExecutionNormalizesSizeAndDefaultsSmartCropToFalse() throws {
        let request = try PublicRequestParser.parse("""
        execute: Crop / Resize
        size: 32:18

        /tmp/first image.jpg
        /tmp/second image.jpg
        """)

        #expect(request == ClopRequest(
            input: .explicit(
                items: [
                    "/tmp/first image.jpg",
                    "/tmp/second image.jpg"
                ],
                extractText: false
            ),
            route: .execute(action: .crop(
                size: "16:9",
                smartCrop: false,
                longEdge: false
            ))
        ))
    }

    @Test
    func cropExecutionAcceptsSmartCropControlForCropShapes() throws {
        let request = try PublicRequestParser.parse("""
        execute: Crop / Resize
        size: 16:9
        controls: sc

        finder
        """)

        #expect(request == ClopRequest(
            input: .finderSelection,
            route: .execute(action: .crop(
                size: "16:9",
                smartCrop: true,
                longEdge: false
            ))
        ))
    }

    @Test
    func cropExecutionAcceptsSmartAdaptiveAndMuteControls() throws {
        let compact = try PublicRequestParser.parse("""
        execute: Crop / Resize
        size: 16:9
        controls: sc, no-ad, m

        /tmp/movie.mp4
        """)
        let explicit = try PublicRequestParser.parse("""
        execute: Crop / Resize
        size: w128
        adaptive: true
        remove audio: yes

        /tmp/movie.mp4
        """)

        #expect(compact.route == .execute(action: .crop(
            size: "16:9",
            smartCrop: true,
            longEdge: false,
            adaptiveOptimisation: .disabled,
            removeAudio: true
        )))
        #expect(explicit.route == .execute(action: .crop(
            size: "128x0",
            smartCrop: false,
            longEdge: false,
            adaptiveOptimisation: .enabled,
            removeAudio: true
        )))
    }

    @Test
    func cropExecutionRejectsConflictingControls() {
        #expect(throws: PublicRequestError.invalidParameter(
            "crop controls",
            "16:9 adaptive no-adaptive"
        )) {
            try PublicRequestParser.parse("""
            execute: Crop / Resize
            size: 16:9
            controls: adaptive no-adaptive

            /tmp/movie.mp4
            """)
        }
        #expect(throws: PublicRequestError.invalidParameter(
            "crop controls",
            "1920"
        )) {
            try PublicRequestParser.parse("""
            execute: Crop / Resize
            size: 1920
            controls: sc

            /tmp/movie.mp4
            """)
        }
        #expect(throws: PublicRequestError.unexpectedParameter("smart crop")) {
            try PublicRequestParser.parse("""
            execute: Crop / Resize
            size: 16:9
            smart crop: true

            /tmp/movie.mp4
            """)
        }
    }

    @Test(arguments: [
        ("50", 0.5),
        ("50%", 0.5),
        ("0.5", 0.5)
    ])
    func downscaleExecutionAcceptsMenuFactorGrammar(
        value: String,
        factor: Double
    ) throws {
        let request = try PublicRequestParser.parse("""
        execute: Downscale
        factor: \(value)

        /tmp/first image.jpg
        /tmp/second audio.m4a
        """)

        #expect(request == ClopRequest(
            input: .explicit(
                items: [
                    "/tmp/first image.jpg",
                    "/tmp/second audio.m4a"
                ],
                extractText: false
            ),
            route: .execute(action: .downscale(factor: factor))
        ))
    }

    @Test
    func downscaleExecutionAcceptsControls() throws {
        let request = try PublicRequestParser.parse("""
        execute: Downscale
        factor: 50%
        controls: adaptive mute

        /tmp/movie.mp4
        """)

        #expect(request.route == .execute(action: .downscale(
            factor: 0.5,
            adaptiveOptimisation: .enabled,
            removeAudio: true
        )))
    }

    @Test
    func downscaleExecutionRejectsConflictingControls() {
        #expect(throws: PublicRequestError.invalidParameter(
            "downscale controls",
            "50% adaptive no-adaptive"
        )) {
            try PublicRequestParser.parse("""
            execute: Downscale
            factor: 50%
            controls: adaptive no-adaptive

            /tmp/movie.mp4
            """)
        }
    }

    @Test
    func conversionExecutionAcceptsDefaultsCompressionAndBitrate() throws {
        let image = try PublicRequestParser.parse("""
        execute: Convert Image
        format: jpg
        compression: 75

        /tmp/image.png
        """)
        let audio = try PublicRequestParser.parse("""
        execute: Convert Audio
        format: mp3
        bitrate: 128

        /tmp/audio.wav
        """)

        #expect(image.route == .execute(action: .convert(ConversionChoice(
            media: .image,
            format: "jpeg",
            setting: .compression(75)
        ))))
        #expect(audio.route == .execute(action: .convert(ConversionChoice(
            media: .audio,
            format: "mp3",
            setting: .bitrate(128)
        ))))
    }

    @Test
    func genericConversionExecutionInfersMediaFromFormat() throws {
        let request = try PublicRequestParser.parse("""
        execute: Convert
        format: webm

        /tmp/video.mov
        """)

        #expect(request.route == .execute(action: .convert(ConversionChoice(
            media: .video,
            format: "webm"
        ))))
    }

    @Test
    func executeOutputOverridesAreParsedSeparatelyFromActionParameters() throws {
        let configuredTemplate = try PublicRequestParser.parse("""
        execute: Optimize
        output: template

        /tmp/image.png
        """)
        let customTemplate = try PublicRequestParser.parse("""
        execute: Convert
        format: mp3
        output template: %P/%f-podcast

        /tmp/audio.wav
        """)
        let disabled = try PublicRequestParser.parse("""
        execute: Downscale
        factor: 50%
        output: false

        /tmp/image.png
        """)

        #expect(configuredTemplate.route == .execute(
            action: .optimise(aggressive: false),
            overrides: ExecutionOverrides(output: .template)
        ))
        #expect(customTemplate.route == .execute(
            action: .convert(ConversionChoice(media: .audio, format: "mp3")),
            overrides: ExecutionOverrides(
                output: .customTemplate("%P/%f-podcast")
            )
        ))
        #expect(disabled.route == .execute(
            action: .downscale(factor: 0.5),
            overrides: ExecutionOverrides(output: .disabled)
        ))
    }

    @Test(arguments: [
        "execute: Uncrop PDF",
        "execute: Strip Metadata"
    ])
    func immediateActionsExecuteWithoutParameters(_ directive: String) throws {
        let request = try PublicRequestParser.parse("""
        \(directive)

        /tmp/file.pdf
        """)

        if directive.contains("Uncrop") {
            #expect(request.route == .execute(action: .uncropPDF))
        } else {
            #expect(request.route == .execute(action: .stripMetadata))
        }
    }

    @Test
    func pipelineExecutionAcceptsSavedNamesAndInlineOptions() throws {
        let saved = try PublicRequestParser.parse("""
        execute: Pipeline
        pipeline: To WebP
        hide: true

        /tmp/image.png
        """)
        let inline = try PublicRequestParser.parse("""
        execute: Pipeline
        pipeline: crop(width: 1600) -> optimize -> convert(to: webp)
        opt: true
        hide: true

        /tmp/image.png
        """)
        let legacyName = try PublicRequestParser.parse("""
        execute: Pipeline
        name: To WebP

        /tmp/image.png
        """)
        let newerStep = try PublicRequestParser.parse("""
        execute: Pipeline
        pipeline: fork

        /tmp/image.png
        """)

        #expect(saved.route == .execute(action: .pipeline(PipelineRunRequest(
            pipeline: "To WebP",
            hideResult: true
        ))))
        #expect(inline.route == .execute(action: .pipeline(PipelineRunRequest(
            pipeline: "crop(width: 1600) -> optimise -> convert(to: webp)",
            isInline: true,
            optimizeFirst: true,
            hideResult: true
        ))))
        #expect(legacyName.route == .execute(action: .pipeline(
            PipelineRunRequest(pipeline: "To WebP")
        )))
        #expect(newerStep.route == .execute(action: .pipeline(
            PipelineRunRequest(pipeline: "fork", isInline: true)
        )))
    }

    @Test
    func cropPDFExecutionAcceptsAllTargetKindsAndControls() throws {
        let ratio = try PublicRequestParser.parse("""
        execute: Crop PDF
        ratio: 32:18
        controls: landscape extend

        /tmp/book one.pdf
        /tmp/book two.pdf
        """)
        let device = try PublicRequestParser.parse("""
        execute: Crop PDF
        device: iPad mini 6 & 7
        page layout: portrait

        /tmp/book.pdf
        """)
        let paper = try PublicRequestParser.parse("""
        execute: Crop PDF
        paper size: A4
        extend: true

        /tmp/book.pdf
        """)

        #expect(ratio.route == .execute(action: .cropPDF(CropPDFRequest(
            target: .aspectRatio("16:9"),
            pageLayout: .landscape,
            extend: true
        ))))
        #expect(device.route == .execute(action: .cropPDF(CropPDFRequest(
            target: .device("iPad mini 6 & 7"),
            pageLayout: .portrait,
            extend: false
        ))))
        #expect(paper.route == .execute(action: .cropPDF(CropPDFRequest(
            target: .paperSize("A4"),
            pageLayout: nil,
            extend: true
        ))))
    }

    @Test
    func typedJSONRemainsCompatible() throws {
        let expected = ClopRequest(
            version: 1,
            input: .clipboard,
            route: .menu(action: .crop)
        )
        let json = try JSONOutput.string(for: expected, prettyPrinted: false)

        #expect(try PublicRequestParser.parse(json) == expected)
    }

    @Test(arguments: [
        ("crop:\n/tmp/image.jpg", PublicRequestError.missingSeparator),
        (
            "execute: Crop / Resize\n\n/tmp/image.jpg",
            PublicRequestError.missingParameter("size")
        ),
        (
            "execute: Optimize\naggressive: maybe\n\nclipboard",
            PublicRequestError.invalidParameter("aggressive", "maybe")
        ),
        (
            "execute: Downscale\n\n/tmp/image.jpg",
            PublicRequestError.missingParameter("factor")
        ),
        (
            "execute: Downscale\nfactor: 100%\n\n/tmp/image.jpg",
            PublicRequestError.invalidParameter("factor", "100%")
        ),
        (
            "execute: Convert Image\ncompression: 70\n\n/tmp/image.jpg",
            PublicRequestError.missingParameter("format")
        ),
        (
            "menu: Optimize\noutput: false\n\n/tmp/image.jpg",
            PublicRequestError.executeOnlyParameter("output")
        ),
        (
            "execute: Optimize\noutput template:\n\n/tmp/image.jpg",
            PublicRequestError.missingParameter("output template")
        ),
        (
            "execute: Pipeline\npipeline: To WebP\nopt: true\n\n/tmp/image.jpg",
            PublicRequestError.invalidParameter(
                "opt",
                "only works with inline pipeline steps"
            )
        ),
        (
            "execute: Pipeline\npipeline: convertt(to: webp)\n\n/tmp/image.jpg",
            PublicRequestError.invalidParameter(
                "pipeline",
                "Unknown pipeline step convertt"
            )
        ),
        (
            "menu: Crop / Resize\n\nfinder\n/tmp/image.jpg",
            PublicRequestError.mixedInputSources
        )
    ])
    func invalidShorthandIsRejected(
        value: String,
        expected: PublicRequestError
    ) {
        #expect(throws: expected) {
            try PublicRequestParser.parse(value)
        }
    }
}
