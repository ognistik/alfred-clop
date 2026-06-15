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
    func cropExecutionDerivesLongEdgeAndAcceptsSmartCrop() throws {
        let request = try PublicRequestParser.parse("""
        execute: Crop / Resize
        size: 1920
        smart crop: on

        finder
        """)

        #expect(request == ClopRequest(
            input: .finderSelection,
            route: .execute(action: .crop(
                size: "1920",
                smartCrop: true,
                longEdge: true
            ))
        ))
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
