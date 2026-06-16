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
    case invalidDownscaleFactor
    case invalidConversion
    case invalidOptimizeControls
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
                let outputExtension: String?
                if case .convert(let choice) = request.action {
                    outputExtension = choice.outputExtension
                } else {
                    outputExtension = nil
                }
                let plan = try OutputTemplateValidator.plan(
                    template: template,
                    inputs: request.inputs,
                    outputExtension: outputExtension,
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
        case let .optimiseMedia(optimize):
            guard OptimizeControlParser.isSupported(optimize) else {
                throw ClopCommandBuilderError.invalidOptimizeControls
            }
            arguments = typedOptimiseArguments(
                for: resolvedRequest,
                optimize: optimize
            )
            expectsJSON = true
        case let .crop(
            size,
            smartCrop,
            longEdge,
            adaptiveOptimisation,
            removeAudio
        ):
            guard let parsedSize = CropSizeParser.parse(size),
                  parsedSize.longEdge == longEdge else {
                throw ClopCommandBuilderError.invalidCropSize
            }
            arguments = cropArguments(
                for: resolvedRequest,
                size: size,
                smartCrop: smartCrop,
                longEdge: longEdge,
                adaptiveOptimisation: adaptiveOptimisation,
                removeAudio: removeAudio
            )
            expectsJSON = true
        case let .downscale(factor):
            guard DownscaleFactorParser.isSupported(factor) else {
                throw ClopCommandBuilderError.invalidDownscaleFactor
            }
            arguments = downscaleArguments(
                for: resolvedRequest,
                factor: factor
            )
            expectsJSON = true
        case .convert(let choice):
            guard ConversionCatalog.isSupported(choice) else {
                throw ClopCommandBuilderError.invalidConversion
            }
            arguments = conversionArguments(
                for: resolvedRequest,
                choice: choice
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
        case .cropPDF:
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
        longEdge: Bool,
        adaptiveOptimisation: CropAdaptiveOptimisation?,
        removeAudio: Bool
    ) -> [String] {
        var arguments = ["crop", "--size", size, "--json", "--no-progress"]
        arguments.append("--skip-errors")

        if longEdge {
            arguments.append("--long-edge")
        }
        if smartCrop {
            arguments.append("--smart-crop")
        }
        switch adaptiveOptimisation {
        case .enabled:
            arguments.append("--adaptive-optimisation")
        case .disabled:
            arguments.append("--no-adaptive-optimisation")
        case nil:
            break
        }
        if removeAudio {
            arguments.append("--remove-audio")
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

    private func downscaleArguments(
        for request: OperationRequest,
        factor: Double
    ) -> [String] {
        var arguments = [
            "downscale",
            "--factor",
            DownscaleFactorParser.factorValue(for: factor),
            "--json",
            "--no-progress",
            "--skip-errors"
        ]

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

    private func conversionArguments(
        for request: OperationRequest,
        choice: ConversionChoice
    ) -> [String] {
        var arguments = [
            "convert",
            choice.media.rawValue,
            "--to",
            choice.format,
            "--json",
            "--no-progress",
            "--skip-errors"
        ]

        switch choice.setting {
        case .compression(let value):
            arguments += ["--compression", String(value)]
        case .automaticCompression:
            arguments += ["--compression", "auto"]
        case .bitrate(let value):
            arguments += ["--bitrate", String(value)]
        case nil:
            break
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

    private func typedOptimiseArguments(
        for request: OperationRequest,
        optimize: OptimizeRequest
    ) -> [String] {
        var arguments = [
            "optimise",
            optimize.media.rawValue,
            "--json",
            "--no-progress",
            "--skip-errors"
        ]

        switch optimize.controls {
        case .image(let controls):
            switch controls.compression {
            case .value(let value):
                arguments += ["--compression", String(value)]
            case .adaptive:
                arguments += ["--compression", "adaptive"]
            case nil:
                break
            }
        case .video(let controls):
            switch controls.compression {
            case .value(let value):
                arguments += ["--compression", String(value)]
            case .automatic:
                arguments += ["--compression", "auto"]
            case nil:
                break
            }
            if let encoder = controls.encoder {
                arguments += ["--encoder", encoder.rawValue]
            }
            if controls.removeAudio {
                arguments.append("--remove-audio")
            }
            if let speed = controls.playbackSpeed {
                arguments += [
                    "--playback-speed-factor",
                    OptimizeControlParser.displayNumber(speed)
                ]
            }
        case .pdf(let controls):
            switch controls.dpi {
            case .value(let value):
                arguments += ["--dpi", String(value)]
            case .adaptive:
                arguments += ["--dpi", "adaptive"]
            case nil:
                break
            }
        case .audio(let controls):
            if let compression = controls.compression {
                arguments += ["--compression", String(compression)]
            }
            if let bitrate = controls.bitrate {
                arguments += ["--bitrate", String(bitrate)]
            }
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
