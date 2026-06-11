import Testing
@testable import AlfredClop

struct OperationRequestTests {
    @Test
    func optimiseRequestRoundTrips() throws {
        let request = OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .optimise(aggressive: true),
            execution: makeExecutionOptions()
        )

        #expect(try roundTrip(request) == request)
    }

    @Test
    func convertRequestRoundTrips() throws {
        let request = OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .convert(format: "webp", quality: 75),
            execution: makeExecutionOptions(
                output: .sameFolder(template: "%P/%f-converted")
            )
        )

        #expect(try roundTrip(request) == request)
    }

    @Test
    func cropRequestRoundTrips() throws {
        let request = OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .crop(size: "1200x630", smartCrop: true, longEdge: false),
            execution: makeExecutionOptions()
        )

        #expect(try roundTrip(request) == request)
    }

    @Test
    func outputAndBackupBehaviorsRemainSeparate() throws {
        let execution = makeExecutionOptions(
            output: .specificFolder(folder: "/tmp/output", template: "%f.%e"),
            backup: .workflowCopy(folder: "/tmp/backups")
        )
        let decoded = try roundTrip(execution)

        #expect(decoded.output == .specificFolder(folder: "/tmp/output", template: "%f.%e"))
        #expect(decoded.backup == .workflowCopy(folder: "/tmp/backups"))
    }
}
