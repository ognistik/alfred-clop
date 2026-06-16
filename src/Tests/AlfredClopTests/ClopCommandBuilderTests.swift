import Foundation
import Testing
@testable import AlfredClop

struct ClopCommandBuilderTests {
    @Test
    func standardOptimiseBuildsJSONCommandWithSeparatePaths() throws {
        let builder = makeBuilder()
        let request = OperationRequest(
            inputs: ["/tmp/first image.png", "/tmp/second.png"],
            action: .optimise(aggressive: false),
            execution: makeExecutionOptions()
        )

        let command = try builder.command(for: request)

        #expect(command.executableURL.path == "/tmp/Clop CLI")
        #expect(command.arguments == [
            "optimise",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--gui",
            "/tmp/first image.png",
            "/tmp/second.png"
        ])
        #expect(command.expectsJSON)
    }

    @Test
    func aggressiveOptimiseAddsSupportedExecutionOptions() throws {
        let builder = makeBuilder()
        var execution = makeExecutionOptions(
            output: .sameFolder(template: "%P/%f-small")
        )
        execution.copyResult = true
        execution.adaptiveOptimisation = "disabled"
        execution.pdfDPI = "150"
        let request = OperationRequest(
            inputs: ["/tmp/document.pdf"],
            action: .optimise(aggressive: true),
            execution: execution
        )

        let command = try builder.command(for: request)

        #expect(command.arguments == [
            "optimise",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--gui",
            "--copy",
            "--aggressive",
            "--pdf-dpi",
            "150",
            "--no-adaptive-optimisation",
            "--output",
            "%P/%f-small",
            "/tmp/document.pdf"
        ])
    }

    @Test
    func mediaSpecificOptimizeBuildsTypedSubcommandControls() throws {
        let command = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/movie with spaces.mp4"],
            action: .optimiseMedia(OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(
                    compression: .value(70),
                    encoder: .adaptive,
                    removeAudio: true,
                    playbackSpeed: 2
                ))
            )),
            execution: makeExecutionOptions()
        ))

        #expect(command.arguments == [
            "optimise",
            "video",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--compression",
            "70",
            "--encoder",
            "adaptive",
            "--remove-audio",
            "--playback-speed-factor",
            "2",
            "--gui",
            "/tmp/movie with spaces.mp4"
        ])
    }

    @Test
    func mediaSpecificOptimizeUsesDPIAndBitrateFlags() throws {
        let pdf = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/document.pdf"],
            action: .optimiseMedia(OptimizeRequest(
                media: .pdf,
                controls: .pdf(PDFOptimizeControls(dpi: .adaptive))
            )),
            execution: makeExecutionOptions()
        ))
        let audio = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/audio.wav"],
            action: .optimiseMedia(OptimizeRequest(
                media: .audio,
                controls: .audio(AudioOptimizeControls(
                    compression: nil,
                    bitrate: 128
                ))
            )),
            execution: makeExecutionOptions()
        ))

        #expect(pdf.arguments.contains("--dpi"))
        #expect(pdf.arguments.contains("adaptive"))
        #expect(audio.arguments.contains("--bitrate"))
        #expect(audio.arguments.contains("128"))
    }

    @Test
    func existingPreservedOutputUsesNextNumericSuffix() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try Data().write(to: source)
        try Data().write(
            to: directory.appendingPathComponent("photo-clop.png")
        )
        var execution = makeExecutionOptions(
            output: .sameFolder(template: "%P/%f-clop")
        )
        execution.showClopUI = false

        let command = try makeBuilder().command(for: OperationRequest(
            inputs: [source.path],
            action: .optimise(aggressive: false),
            execution: execution
        ))

        #expect(command.arguments == [
            "optimise",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--output",
            "%P/%f-clop-2",
            source.path
        ])
    }

    @Test
    func homeRelativeOutputExpandsBeforeLaunchingClop() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try Data().write(to: source)
        var execution = makeExecutionOptions(
            output: .sameFolder(template: "~/Clop Output/%f")
        )
        execution.showClopUI = false

        let command = try makeBuilder().command(for: OperationRequest(
            inputs: [source.path],
            action: .optimise(aggressive: false),
            execution: execution
        ))

        #expect(command.arguments.contains(
            "\(NSHomeDirectory())/Clop Output/%f"
        ))
    }

    @Test
    func uncropPDFDoesNotRequestJSON() throws {
        let command = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/book one.pdf", "/tmp/book two.pdf"],
            action: .uncropPDF,
            execution: makeExecutionOptions()
        ))

        #expect(command.arguments == [
            "uncrop-pdf",
            "/tmp/book one.pdf",
            "/tmp/book two.pdf"
        ])
        #expect(!command.expectsJSON)
    }

    @Test
    func stripMetadataUsesStripExifWithoutJSON() throws {
        let command = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/photo.jpg", "/tmp/movie.mp4"],
            action: .stripMetadata,
            execution: makeExecutionOptions()
        ))

        #expect(command.arguments == [
            "strip-exif",
            "/tmp/photo.jpg",
            "/tmp/movie.mp4"
        ])
        #expect(!command.expectsJSON)
    }

    @Test
    func cropBuildsJSONCommandWithSeparatePaths() throws {
        let command = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/first image.png", "/tmp/second.pdf"],
            action: .crop(
                size: "1200x630",
                smartCrop: false,
                longEdge: false
            ),
            execution: makeExecutionOptions()
        ))

        #expect(command.arguments == [
            "crop",
            "--size",
            "1200x630",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--gui",
            "/tmp/first image.png",
            "/tmp/second.pdf"
        ])
        #expect(command.expectsJSON)
    }

    @Test
    func cropAddsOnlyExplicitOptionalFlags() throws {
        var execution = makeExecutionOptions(
            output: .sameFolder(template: "%P/%f-cropped")
        )
        execution.copyResult = true
        let command = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/movie.mp4"],
            action: .crop(
                size: "1920",
                smartCrop: true,
                longEdge: true
            ),
            execution: execution
        ))

        #expect(command.arguments == [
            "crop",
            "--size",
            "1920",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--long-edge",
            "--smart-crop",
            "--gui",
            "--copy",
            "--output",
            "%P/%f-cropped",
            "/tmp/movie.mp4"
        ])
    }

    @Test
    func recursiveFolderSettingIsAppliedToSupportedCommands() throws {
        var execution = makeExecutionOptions()
        execution.recursiveFolders = true

        let optimise = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/media folder"],
            action: .optimise(aggressive: false),
            execution: execution
        ))
        let downscale = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/media folder"],
            action: .downscale(factor: 0.5),
            execution: execution
        ))
        let uncrop = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/pdf folder"],
            action: .uncropPDF,
            execution: execution
        ))
        let metadata = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/media folder"],
            action: .stripMetadata,
            execution: execution
        ))

        #expect(optimise.arguments.contains("--recursive"))
        #expect(downscale.arguments.contains("--recursive"))
        #expect(uncrop.arguments == [
            "uncrop-pdf", "--recursive", "/tmp/pdf folder"
        ])
        #expect(metadata.arguments == [
            "strip-exif", "--recursive", "/tmp/media folder"
        ])
    }

    @Test
    func cropRejectsInvalidOrInconsistentTypedSize() {
        #expect(throws: ClopCommandBuilderError.invalidCropSize) {
            try makeBuilder().command(for: OperationRequest(
                inputs: ["/tmp/photo.jpg"],
                action: .crop(
                    size: "0x0",
                    smartCrop: false,
                    longEdge: false
                ),
                execution: makeExecutionOptions()
            ))
        }
        #expect(throws: ClopCommandBuilderError.invalidCropSize) {
            try makeBuilder().command(for: OperationRequest(
                inputs: ["/tmp/photo.jpg"],
                action: .crop(
                    size: "1920",
                    smartCrop: false,
                    longEdge: false
                ),
                execution: makeExecutionOptions()
            ))
        }
    }

    @Test
    func missingCLIReturnsDiscoveryErrors() {
        let builder = ClopCommandBuilder(discovery: StubDiscovery(
            diagnostics: ClopDiagnostics(
                found: false,
                path: nil,
                source: nil,
                errors: ["Clop is missing"]
            )
        ))

        #expect(throws: ClopCommandBuilderError.missingCLI(["Clop is missing"])) {
            try builder.command(for: OperationRequest(
                inputs: ["/tmp/photo.jpg"],
                action: .stripMetadata,
                execution: makeExecutionOptions()
            ))
        }
    }

    @Test
    func downscaleBuildsJSONCommandWithSeparatePaths() throws {
        var execution = makeExecutionOptions(
            output: .sameFolder(template: "%P/%f-small")
        )
        execution.copyResult = true

        let command = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/first image.png", "/tmp/second audio.m4a"],
            action: .downscale(factor: 0.75),
            execution: execution
        ))

        #expect(command.arguments == [
            "downscale",
            "--factor",
            "0.75",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--gui",
            "--copy",
            "--output",
            "%P/%f-small",
            "/tmp/first image.png",
            "/tmp/second audio.m4a"
        ])
        #expect(command.expectsJSON)
    }

    @Test(arguments: [0, 1, 1.2])
    func downscaleRejectsUnsupportedFactors(factor: Double) {
        #expect(throws: ClopCommandBuilderError.invalidDownscaleFactor) {
            try makeBuilder().command(for: OperationRequest(
                inputs: ["/tmp/photo.jpg"],
                action: .downscale(factor: factor),
                execution: makeExecutionOptions()
            ))
        }
    }

    @Test
    func conversionBuildsTypedAppBackedCommand() throws {
        let command = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/photo.jpg"],
            action: .convert(ConversionChoice(
                media: .image,
                format: "webp",
                setting: .compression(75)
            )),
            execution: makeExecutionOptions()
        ))

        #expect(command.arguments == [
            "convert",
            "image",
            "--to",
            "webp",
            "--json",
            "--no-progress",
            "--skip-errors",
            "--compression",
            "75",
            "--gui",
            "/tmp/photo.jpg"
        ])
        #expect(command.expectsJSON)
    }

    @Test
    func videoAndAudioConversionControlsUseTheirTypedFlags() throws {
        let video = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/video.mov"],
            action: .convert(ConversionChoice(
                media: .video,
                format: "mp4",
                setting: .automaticCompression
            )),
            execution: makeExecutionOptions()
        ))
        let audio = try makeBuilder().command(for: OperationRequest(
            inputs: ["/tmp/audio.wav"],
            action: .convert(ConversionChoice(
                media: .audio,
                format: "mp3",
                setting: .bitrate(128)
            )),
            execution: makeExecutionOptions()
        ))

        #expect(video.arguments.contains("--compression"))
        #expect(video.arguments.contains("auto"))
        #expect(audio.arguments.contains("--bitrate"))
        #expect(audio.arguments.contains("128"))
    }

    @Test
    func conversionRejectsControlsUnsupportedByTheTarget() {
        #expect(throws: ClopCommandBuilderError.invalidConversion) {
            try makeBuilder().command(for: OperationRequest(
                inputs: ["/tmp/video.mov"],
                action: .convert(ConversionChoice(
                    media: .video,
                    format: "gif",
                    setting: .compression(70)
                )),
                execution: makeExecutionOptions()
            ))
        }
    }

    private func makeBuilder() -> ClopCommandBuilder {
        ClopCommandBuilder(discovery: StubDiscovery(
            diagnostics: ClopDiagnostics(
                found: true,
                path: "/tmp/Clop CLI",
                source: "test",
                errors: []
            )
        ))
    }
}

struct StubDiscovery: ClopCLIDiscovering {
    var diagnostics: ClopDiagnostics

    func discover() -> ClopDiagnostics {
        diagnostics
    }
}
