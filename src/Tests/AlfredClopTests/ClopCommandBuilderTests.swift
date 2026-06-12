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
            output: .sameFolder(template: "%P/%f-small.%e")
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
            "--gui",
            "--copy",
            "--aggressive",
            "--pdf-dpi",
            "150",
            "--no-adaptive-optimisation",
            "--output",
            "%P/%f-small.%e",
            "/tmp/document.pdf"
        ])
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
            "--gui",
            "/tmp/first image.png",
            "/tmp/second.pdf"
        ])
        #expect(command.expectsJSON)
    }

    @Test
    func cropAddsOnlyExplicitOptionalFlags() throws {
        var execution = makeExecutionOptions(
            output: .sameFolder(template: "%P/%f-cropped.%e")
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
            "--long-edge",
            "--smart-crop",
            "--gui",
            "--copy",
            "--output",
            "%P/%f-cropped.%e",
            "/tmp/movie.mp4"
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
    func parameterActionIsNotExecutableYet() {
        #expect(throws: ClopCommandBuilderError.unsupportedAction) {
            try makeBuilder().command(for: OperationRequest(
                inputs: ["/tmp/photo.jpg"],
                action: .downscale(factor: 0.5),
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
