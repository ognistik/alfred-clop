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
    case invalidOutputTemplate(OutputTemplateError)
}

struct ClopCommandBuilder {
    private let discovery: any ClopCLIDiscovering
    private let fileManager: FileManager

    init(
        discovery: any ClopCLIDiscovering = ClopCLIDiscovery(),
        fileManager: FileManager = .default
    ) {
        self.discovery = discovery
        self.fileManager = fileManager
    }

    func command(for request: OperationRequest) throws -> ClopCommand {
        guard !request.inputs.isEmpty else {
            throw ClopCommandBuilderError.missingInputs
        }

        guard request.execution.backup == .trustClop else {
            throw ClopCommandBuilderError.unsupportedBackupBehavior
        }
        var resolvedRequest = request
        if let template = request.execution.output.template {
            do {
                let plan = try OutputTemplateValidator.plan(
                    template: template,
                    inputs: request.inputs,
                    fileManager: fileManager
                )
                resolvedRequest.execution.output = outputBehavior(
                    request.execution.output,
                    replacingTemplateWith: plan.template
                )
            } catch let error as OutputTemplateError {
                throw ClopCommandBuilderError.invalidOutputTemplate(error)
            }
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
                for: resolvedRequest,
                aggressive: aggressive
            )
            expectsJSON = true
        case let .crop(size, smartCrop, longEdge):
            guard let parsedSize = CropSizeParser.parse(size),
                  parsedSize.longEdge == longEdge else {
                throw ClopCommandBuilderError.invalidCropSize
            }
            arguments = cropArguments(
                for: resolvedRequest,
                size: size,
                smartCrop: smartCrop,
                longEdge: longEdge
            )
            expectsJSON = true
        case .uncropPDF:
            arguments = ["uncrop-pdf"]
                + recursiveArguments(for: resolvedRequest.execution)
                + outputArguments(for: resolvedRequest.execution.output)
                + request.inputs
            expectsJSON = false
        case .stripMetadata:
            arguments = ["strip-exif"]
                + recursiveArguments(for: request.execution)
                + request.inputs
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
        arguments.append("--skip-errors")

        if longEdge {
            arguments.append("--long-edge")
        }
        if smartCrop {
            arguments.append("--smart-crop")
        }
        if request.execution.aggressiveProcessing == true {
            arguments.append("--aggressive")
        }
        if request.execution.showClopUI {
            arguments.append("--gui")
        }
        if request.execution.copyResult {
            arguments.append("--copy")
        }
        if request.execution.recursiveFolders {
            arguments.append("--recursive")
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
        arguments.append("--skip-errors")

        if request.execution.showClopUI {
            arguments.append("--gui")
        }
        if request.execution.copyResult {
            arguments.append("--copy")
        }
        if request.execution.recursiveFolders {
            arguments.append("--recursive")
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

    private func outputBehavior(
        _ output: OutputBehavior,
        replacingTemplateWith template: String
    ) -> OutputBehavior {
        switch output {
        case .inPlace:
            return .inPlace
        case .sameFolder:
            return .sameFolder(template: template)
        case let .specificFolder(folder, _):
            return .specificFolder(folder: folder, template: template)
        }
    }

    private func recursiveArguments(
        for execution: ExecutionOptions
    ) -> [String] {
        execution.recursiveFolders ? ["--recursive"] : []
    }
}
