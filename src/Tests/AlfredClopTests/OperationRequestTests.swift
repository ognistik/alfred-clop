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
    func mediaSpecificOptimizeRequestRoundTrips() throws {
        let request = OperationRequest(
            inputs: ["/tmp/video.mp4"],
            action: .optimiseMedia(OptimizeRequest(
                media: .video,
                controls: .video(VideoOptimizeControls(
                    compression: .automatic,
                    encoder: .software,
                    removeAudio: true,
                    playbackSpeed: 1.5
                ))
            )),
            execution: makeExecutionOptions()
        )

        #expect(try roundTrip(request) == request)
    }

    @Test
    func convertRequestRoundTrips() throws {
        let request = OperationRequest(
            inputs: ["/tmp/image.png"],
            action: .convert(ConversionChoice(
                media: .image,
                format: "webp",
                setting: .compression(75)
            )),
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
    func parameterStepAndMenuStateRoundTrip() throws {
        let request = ParameterStepRequest(
            action: .crop,
            inputs: ["/tmp/image.png", "/tmp/movie.mp4"],
            inputContext: .arguments
        )

        #expect(try roundTrip(request) == request)
        #expect(try roundTrip(MenuState.crop(request)) == .crop(request))
        #expect(try roundTrip(MenuState.actions) == .actions)
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
