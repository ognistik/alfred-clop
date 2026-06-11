import Foundation
import Testing
@testable import AlfredClop

struct ProbeModeTests {
    @Test
    func probeOutputIsValidJSON() throws {
        let discovery = ClopCLIDiscovery(
            environment: [:],
            applicationPaths: []
        )
        let response = ProbeMode.response(discovery: discovery)
        let data = try JSONOutput.data(for: response)
        let decoded = try JSONDecoder().decode(ClopDiagnostics.self, from: data)

        #expect(!decoded.found)
        #expect(decoded.path == nil)
        #expect(!decoded.errors.isEmpty)
    }
}
