import Foundation

enum ClopPipelineError: Error, LocalizedError, Equatable {
    case missingCLI([String])
    case commandFailed(String)
    case invalidListJSON

    var errorDescription: String? {
        switch self {
        case .missingCLI(let errors):
            return errors.last ?? "Install Clop or configure its CLI path."
        case .commandFailed(let message):
            return message
        case .invalidListJSON:
            return "Clop returned an unreadable pipeline list."
        }
    }
}

protocol ClopPipelineProviding {
    func listPipelines() throws -> [SavedPipeline]
    func addPipeline(_ request: PipelineAddRequest) throws
    func deletePipeline(named name: String) throws
}

struct ClopPipelineProvider: ClopPipelineProviding {
    private let discovery: any ClopCLIDiscovering
    private let runner: any ClopProcessRunning

    init(
        discovery: any ClopCLIDiscovering = ClopCLIDiscovery(),
        runner: any ClopProcessRunning = FoundationClopProcessRunner()
    ) {
        self.discovery = discovery
        self.runner = runner
    }

    func listPipelines() throws -> [SavedPipeline] {
        let result = try runner.run(command(arguments: [
            "pipeline",
            "list",
            "--json"
        ]))
        try ensureSuccess(result)
        guard let list = try? JSONDecoder().decode(
            PipelineListResponse.self,
            from: result.standardOutput
        ) else {
            throw ClopPipelineError.invalidListJSON
        }
        return list.saved
    }

    func addPipeline(_ request: PipelineAddRequest) throws {
        var arguments = ["pipeline", "add"]
        if let fileType = request.fileType {
            arguments += ["--file-type", fileType.rawValue]
        }
        if request.skipOptimisation {
            arguments.append("--skip-optimisation")
        }
        if request.hideResult {
            arguments.append("--hide-result")
        }
        if request.replace {
            arguments.append("--force")
        }
        arguments += [request.name, request.steps]
        try ensureSuccess(try runner.run(command(arguments: arguments)))
    }

    func deletePipeline(named name: String) throws {
        try ensureSuccess(try runner.run(command(arguments: [
            "pipeline",
            "delete",
            name
        ])))
    }

    private func command(arguments: [String]) throws -> ClopCommand {
        let diagnostics = discovery.discover()
        guard let path = diagnostics.path, diagnostics.found else {
            throw ClopPipelineError.missingCLI(diagnostics.errors)
        }
        return ClopCommand(
            executableURL: URL(fileURLWithPath: path),
            arguments: arguments,
            expectsJSON: arguments.contains("--json")
        )
    }

    private func ensureSuccess(_ result: ClopProcessResult) throws {
        guard result.terminationStatus != 0 else { return }
        let stderr = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw ClopPipelineError.commandFailed(
            stderr.isEmpty ? stdout : stderr
        )
    }
}

private struct PipelineListResponse: Codable {
    var saved: [SavedPipeline]
}
