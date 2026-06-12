import Foundation

struct ClopCommand: Equatable {
    var executableURL: URL
    var arguments: [String]
    var expectsJSON: Bool
}

protocol ClopCLIDiscovering {
    func discover() -> ClopDiagnostics
}

extension ClopCLIDiscovery: ClopCLIDiscovering {}

enum ClopCommandBuilderError: Error, Equatable {
    case missingCLI([String])
    case missingInputs
    case invalidCropSize
    case unsupportedAction
    case unsupportedBackupBehavior
}

struct ClopCommandBuilder {
    private let discovery: any ClopCLIDiscovering

    init(discovery: any ClopCLIDiscovering = ClopCLIDiscovery()) {
        self.discovery = discovery
    }

    func command(for request: OperationRequest) throws -> ClopCommand {
        guard !request.inputs.isEmpty else {
            throw ClopCommandBuilderError.missingInputs
        }

        guard request.execution.backup == .trustClop else {
            throw ClopCommandBuilderError.unsupportedBackupBehavior
        }

        let diagnostics = discovery.discover()
        guard let executablePath = diagnostics.path, diagnostics.found else {
            throw ClopCommandBuilderError.missingCLI(diagnostics.errors)
        }

        let arguments: [String]
        let expectsJSON: Bool

        switch request.action {
        case let .optimise(aggressive):
            arguments = optimiseArguments(
                for: request,
                aggressive: aggressive
            )
            expectsJSON = true
        case let .crop(size, smartCrop, longEdge):
            guard let parsedSize = CropSizeParser.parse(size),
                  parsedSize.longEdge == longEdge else {
                throw ClopCommandBuilderError.invalidCropSize
            }
            arguments = cropArguments(
                for: request,
                size: size,
                smartCrop: smartCrop,
                longEdge: longEdge
            )
            expectsJSON = true
        case .uncropPDF:
            arguments = ["uncrop-pdf"]
                + outputArguments(for: request.execution.output)
                + request.inputs
            expectsJSON = false
        case .stripMetadata:
            arguments = ["strip-exif"] + request.inputs
            expectsJSON = false
        case .downscale, .convert, .cropPDF:
            throw ClopCommandBuilderError.unsupportedAction
        }

        return ClopCommand(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: arguments,
            expectsJSON: expectsJSON
        )
    }

    private func cropArguments(
        for request: OperationRequest,
        size: String,
        smartCrop: Bool,
        longEdge: Bool
    ) -> [String] {
        var arguments = ["crop", "--size", size, "--json", "--no-progress"]

        if longEdge {
            arguments.append("--long-edge")
        }
        if smartCrop {
            arguments.append("--smart-crop")
        }
        if request.execution.showClopUI {
            arguments.append("--gui")
        }
        if request.execution.copyResult {
            arguments.append("--copy")
        }

        return arguments
            + outputArguments(for: request.execution.output)
            + request.inputs
    }

    private func optimiseArguments(
        for request: OperationRequest,
        aggressive: Bool
    ) -> [String] {
        var arguments = ["optimise", "--json", "--no-progress"]

        if request.execution.showClopUI {
            arguments.append("--gui")
        }
        if request.execution.copyResult {
            arguments.append("--copy")
        }
        if aggressive {
            arguments.append("--aggressive")
        }
        if let pdfDPI = request.execution.pdfDPI {
            arguments += ["--pdf-dpi", pdfDPI]
        }
        switch request.execution.adaptiveOptimisation {
        case "enabled":
            arguments.append("--adaptive-optimisation")
        case "disabled":
            arguments.append("--no-adaptive-optimisation")
        default:
            break
        }

        return arguments
            + outputArguments(for: request.execution.output)
            + request.inputs
    }

    private func outputArguments(for output: OutputBehavior) -> [String] {
        switch output {
        case .inPlace:
            return []
        case let .sameFolder(template):
            return ["--output", template]
        case let .specificFolder(folder, template):
            let outputPath = URL(fileURLWithPath: folder, isDirectory: true)
                .appendingPathComponent(template)
                .path
            return ["--output", outputPath]
        }
    }
}
