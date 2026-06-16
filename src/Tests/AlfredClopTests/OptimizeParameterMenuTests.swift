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

        #expect(item.title == "Optimize Images with Defaults")
        #expect(item.subtitle.contains("⏎ Run • ⇥ Controls • ⌃⏎ Custom Presets"))
        #expect(item.autocomplete == "controls: ")
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

        #expect(item.title == "Type optimization controls")
        #expect(item.subtitle == "Examples: c70, auto, software, mute, 2x")
        #expect(item.text?.largetype?.contains("Video Optimize controls") == true)
    }

    private func stateJSON(for request: ParameterStepRequest) throws -> String {
        try JSONOutput.string(
            for: MenuState.optimise(request),
            prettyPrinted: false
        )
    }
}
