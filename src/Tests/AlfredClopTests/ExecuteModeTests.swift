import Foundation
import Testing
@testable import AlfredClop

struct ExecuteModeTests {
    @Test
    func validOptimiseRequestReturnsSuccess() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .optimise(aggressive: false)),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data(#"{"results":[]}"#.utf8),
                standardError: Data()
            ))
        )

        #expect(response.items[0].title == "Optimization complete")
        #expect(response.items[0].subtitle == "Clop processed 2 files.")
    }

    @Test
    func textOnlyActionDoesNotRequireJSON() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .uncropPDF),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data(),
                standardError: Data()
            ))
        )

        #expect(response.items[0].title == "PDF uncrop complete")
    }

    @Test
    func cropRequiresJSONAndStaysQuietOnSuccess() throws {
        let json = try requestJSON(action: .crop(
            size: "1920",
            smartCrop: false,
            longEdge: true
        ))
        let runner = StubProcessRunner(result: ClopProcessResult(
            terminationStatus: 0,
            standardOutput: Data(#"{"results":[]}"#.utf8),
            standardError: Data()
        ))

        let response = ExecuteMode.response(
            requestJSON: json,
            builder: builder(),
            runner: runner
        )
        let quiet = ExecuteMode.quietFeedback(
            requestJSON: json,
            builder: builder(),
            runner: runner
        )

        #expect(response.items[0].title == "Crop / resize complete")
        #expect(quiet == nil)
    }

    @Test
    func cropRejectsInvalidJSONResult() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .crop(
                size: "16:9",
                smartCrop: false,
                longEdge: false
            )),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data("not json".utf8),
                standardError: Data()
            ))
        )

        #expect(response.items[0].title == "Unable to read Clop result")
    }

    @Test
    func invalidRequestReturnsVisibleFeedback() {
        let response = ExecuteMode.response(
            requestJSON: "{not-json}",
            builder: builder(),
            runner: StubProcessRunner()
        )

        #expect(response.items[0].title == "Invalid Clop request")
        #expect(response.items[0].valid == false)
    }

    @Test
    func parameterStepReturnsNonExecutableFeedback() throws {
        let json = try JSONOutput.string(
            for: ParameterStepRequest(
                action: .crop,
                inputs: ["/tmp/photo.jpg"]
            ),
            prettyPrinted: false
        )

        let response = ExecuteMode.response(
            requestJSON: json,
            builder: builder(),
            runner: StubProcessRunner()
        )

        #expect(response.items[0].title == "This action needs more information")
        #expect(response.items[0].subtitle.contains("not available yet"))
    }

    @Test
    func missingCLIReturnsVisibleFeedback() throws {
        let missingBuilder = ClopCommandBuilder(discovery: StubDiscovery(
            diagnostics: ClopDiagnostics(
                found: false,
                path: nil,
                source: nil,
                errors: ["Install Clop first."]
            )
        ))

        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .stripMetadata),
            builder: missingBuilder,
            runner: StubProcessRunner()
        )

        #expect(response.items[0].title == "Clop CLI not found")
        #expect(response.items[0].subtitle == "Install Clop first.")
    }

    @Test
    func launchFailureReturnsVisibleFeedback() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .stripMetadata),
            builder: builder(),
            runner: StubProcessRunner(error: StubProcessError.launchFailed)
        )

        #expect(response.items[0].title == "Unable to launch Clop")
    }

    @Test
    func nonzeroExitUsesStandardError() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .stripMetadata),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 2,
                standardOutput: Data(),
                standardError: Data("PDF files are not supported".utf8)
            ))
        )

        #expect(response.items[0].title == "Clop operation failed")
        #expect(response.items[0].subtitle == "PDF files are not supported")
    }

    @Test
    func optimiseRequiresValidJSONResult() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .optimise(aggressive: true)),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data("not json".utf8),
                standardError: Data()
            ))
        )

        #expect(response.items[0].title == "Unable to read Clop result")
    }

    @Test
    func quietExecutionReturnsNoTextOnSuccess() throws {
        let feedback = ExecuteMode.quietFeedback(
            requestJSON: try requestJSON(action: .stripMetadata),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data(),
                standardError: Data()
            ))
        )

        #expect(feedback == nil)
    }

    @Test
    func quietExecutionReturnsConciseTextOnFailure() throws {
        let feedback = ExecuteMode.quietFeedback(
            requestJSON: try requestJSON(action: .stripMetadata),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 2,
                standardOutput: Data(),
                standardError: Data("Processing failed".utf8)
            ))
        )

        #expect(feedback == "Clop operation failed: Processing failed")
    }

    private func builder() -> ClopCommandBuilder {
        ClopCommandBuilder(discovery: StubDiscovery(
            diagnostics: ClopDiagnostics(
                found: true,
                path: "/tmp/ClopCLI",
                source: "test",
                errors: []
            )
        ))
    }

    private func requestJSON(action: ActionRequest) throws -> String {
        try JSONOutput.string(
            for: OperationRequest(
                inputs: ["/tmp/first file.jpg", "/tmp/second file.jpg"],
                action: action,
                execution: makeExecutionOptions()
            ),
            prettyPrinted: false
        )
    }
}

private enum StubProcessError: Error {
    case launchFailed
}

private struct StubProcessRunner: ClopProcessRunning {
    var result = ClopProcessResult(
        terminationStatus: 0,
        standardOutput: Data(),
        standardError: Data()
    )
    var error: Error?

    func run(_ command: ClopCommand) throws -> ClopProcessResult {
        if let error {
            throw error
        }
        return result
    }
}
