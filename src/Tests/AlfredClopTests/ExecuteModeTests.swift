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
    func cropReportsWhenClopSkipsEveryFileAtStatusZero() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .crop(
                size: "1920",
                smartCrop: false,
                longEdge: true
            )),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data(
                    #"""
                    {
                      "done": [],
                      "failed": [{
                        "error": "Image is already at the correct size or smaller: /tmp/first file.jpg",
                        "forURL": "file:///tmp/first%20file.jpg"
                      }]
                    }
                    """#.utf8
                ),
                standardError: Data()
            ))
        )

        #expect(response.items[0].title == "Crop / resize not performed")
        #expect(
            response.items[0].subtitle
                == "The file was not processed. first file.jpg is already at the requested size or smaller."
        )
    }

    @Test
    func cropReportsPartialBatchResultsAtStatusZero() throws {
        let json = try requestJSON(action: .crop(
            size: "1200x630",
            smartCrop: false,
            longEdge: false
        ))
        let runner = StubProcessRunner(result: ClopProcessResult(
            terminationStatus: 0,
            standardOutput: Data(
                #"""
                {
                  "done": [{}],
                  "failed": [{
                    "error": "Image is already at the correct size or smaller: /tmp/second file.jpg",
                    "forURL": "file:///tmp/second%20file.jpg"
                  }]
                }
                """#.utf8
            ),
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

        #expect(response.items[0].title == "Crop / resize partly complete")
        #expect(
            response.items[0].subtitle
                == "Processed 1 of 2 files. second file.jpg is already at the requested size or smaller."
        )
        #expect(
            quiet
                == "Crop / resize partly complete: Processed 1 of 2 files. second file.jpg is already at the requested size or smaller."
        )
    }

    @Test
    func nestedSubstackURLFalseFailureRemainsQuiet() throws {
        let url = "https://substackcdn.com/image/fetch/$s_!QUQr!,w_1456,c_limit,f_webp,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fc60d83b6-d1ce-40c5-a340-8954fa6406a3_1672x941.jpeg"
        let json = try JSONOutput.string(
            for: OperationRequest(
                inputs: [url],
                action: .optimise(aggressive: false),
                execution: makeExecutionOptions()
            ),
            prettyPrinted: false
        )
        let runner = StubProcessRunner(result: ClopProcessResult(
            terminationStatus: 0,
            standardOutput: Data(
                """
                {"done":[],"failed":[{"error":"The file could not be opened because URL type https isn’t supported.","forURL":"\(url)"}]}
                """.utf8
            ),
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

        #expect(response.items[0].title == "Optimization complete")
        #expect(quiet == nil)
    }

    @Test
    func remoteURLFalseFailureDoesNotHideOtherBatchFailures() throws {
        let url = "https://example.com/nested/image.jpeg"
        let json = try JSONOutput.string(
            for: OperationRequest(
                inputs: [url, "/tmp/local.jpg"],
                action: .optimise(aggressive: false),
                execution: makeExecutionOptions()
            ),
            prettyPrinted: false
        )
        let output = """
        {
          "done": [],
          "failed": [
            {"error": "URL type https isn’t supported.", "forURL": "\(url)"},
            {"error": "Local processing failed.", "forURL": "file:///tmp/local.jpg"}
          ]
        }
        """

        let response = ExecuteMode.response(
            requestJSON: json,
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data(output.utf8),
                standardError: Data()
            ))
        )

        #expect(response.items[0].title == "Optimization not performed")
        #expect(response.items[0].subtitle.contains("Local processing failed"))
    }

    @Test
    func cropOmitsFilenameWhenMultipleFilesAreAlreadySmallEnough() throws {
        let response = ExecuteMode.response(
            requestJSON: try requestJSON(action: .crop(
                size: "1920",
                smartCrop: false,
                longEdge: true
            )),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data(
                    #"""
                    {
                      "done": [],
                      "failed": [
                        {
                          "error": "Image is already at the correct size or smaller: /tmp/first file.jpg",
                          "forURL": "file:///tmp/first%20file.jpg"
                        },
                        {
                          "error": "Image is already at the correct size or smaller: /tmp/second file.jpg",
                          "forURL": "file:///tmp/second%20file.jpg"
                        }
                      ]
                    }
                    """#.utf8
                ),
                standardError: Data()
            ))
        )

        #expect(response.items[0].title == "Crop / resize not performed")
        #expect(
            response.items[0].subtitle
                == "2 files were not processed. They are already at the requested size or smaller."
        )
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
    func successfulBackgroundExecutionUsesDefaultCompletionNotification() throws {
        var execution = makeExecutionOptions()
        execution.showClopUI = false
        let json = try JSONOutput.string(
            for: OperationRequest(
                inputs: ["/tmp/photo.png"],
                action: .stripMetadata,
                execution: execution
            ),
            prettyPrinted: false
        )

        let feedback = ExecuteMode.quietFeedback(
            requestJSON: json,
            environment: Environment(values: [:]),
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 0,
                standardOutput: Data(),
                standardError: Data()
            ))
        )

        #expect(feedback == "Metadata removed: Clop processed 1 file.")
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

    @Test
    func previousCustomOutputWarnsOnlyAfterSuccessfulPreservedExecution() throws {
        let root = try makeTemporaryDirectory()
        let previous = root.appendingPathComponent("Previous")
        let configured = root.appendingPathComponent("Configured")
        let previousFile = previous.appendingPathComponent("settings.json")
        try PresetStore(fileURL: previousFile).persist(SettingsDocument(
            outputTemplate: "%P/%f-previous"
        ))
        let environment = Environment(values: [
            PresetStore.workflowDataEnvironmentKey: previous.path,
            PresetStore.configuredPathEnvironmentKey: configured.path,
            "errorNotifications": "true",
            "completionNotifications": "false"
        ])
        _ = PresetMigrationCoordinator(environment: environment).status()
        var execution = try environment.resolvedExecutionOptions(
            preserveOriginal: true
        )
        execution.showClopUI = true
        let preservedJSON = try JSONOutput.string(
            for: OperationRequest(
                inputs: ["/tmp/photo.png"],
                action: .optimise(aggressive: false),
                execution: execution
            ),
            prettyPrinted: false
        )
        let success = StubProcessRunner(result: ClopProcessResult(
            terminationStatus: 0,
            standardOutput: Data(#"{"done":[],"failed":[]}"#.utf8),
            standardError: Data()
        ))

        #expect(ExecuteMode.quietFeedback(
            requestJSON: preservedJSON,
            environment: environment,
            builder: builder(),
            runner: success
        ) == "Using previous output settings: Open Configuration to move settings or start fresh")

        execution.output = .inPlace
        let inPlaceJSON = try JSONOutput.string(
            for: OperationRequest(
                inputs: ["/tmp/photo.png"],
                action: .optimise(aggressive: false),
                execution: execution
            ),
            prettyPrinted: false
        )
        #expect(ExecuteMode.quietFeedback(
            requestJSON: inPlaceJSON,
            environment: environment,
            builder: builder(),
            runner: success
        ) == nil)
        #expect(ExecuteMode.quietFeedback(
            requestJSON: preservedJSON,
            environment: environment,
            builder: builder(),
            runner: StubProcessRunner(result: ClopProcessResult(
                terminationStatus: 2,
                standardOutput: Data(),
                standardError: Data("Failed".utf8)
            ))
        ) == "Clop operation failed: Failed")

        var disabledValues = environment.values
        disabledValues["errorNotifications"] = "false"
        #expect(ExecuteMode.quietFeedback(
            requestJSON: preservedJSON,
            environment: Environment(values: disabledValues),
            builder: builder(),
            runner: success
        ) == nil)

        try PresetMigrationCoordinator(environment: environment).startFresh()
        #expect(ExecuteMode.quietFeedback(
            requestJSON: preservedJSON,
            environment: environment,
            builder: builder(),
            runner: success
        ) == nil)
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
