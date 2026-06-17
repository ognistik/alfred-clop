import Foundation

enum ClopRequestDispatcher {
    static func isSuccessfulExecution(_ title: String) -> Bool {
        [
            "Optimization complete",
            "Aggressive optimization complete",
            "Crop / resize complete",
            "Downscale complete",
            "Conversion complete",
            "PDF crop complete",
            "PDF uncrop complete",
            "Metadata removed",
            "Pipeline complete",
            "Clop operation complete"
        ].contains(title)
    }

    static func response(
        requestJSON: String,
        query: String = "",
        contextOverride: ActionInputContext? = nil,
        clipboard: ClipboardReading = SystemClipboardReader(),
        finder: any FinderSelectionReading = SystemFinderSelectionReader(),
        collector: InputCollector = InputCollector(),
        environment: Environment = Environment(),
        builder: ClopCommandBuilder = ClopCommandBuilder(),
        runner: any ClopProcessRunning = FoundationClopProcessRunner(),
        preserveOriginalOverride: Bool? = nil
    ) -> ScriptFilterResponse {
        let request: ClopRequest
        do {
            request = try JSONDecoder().decode(
                ClopRequest.self,
                from: Data(requestJSON.utf8)
            )
        } catch {
            return feedback(
                title: "Invalid Clop request",
                subtitle: "Use the documented shorthand or typed JSON format."
            )
        }

        if let version = request.version, version != 1 {
            return feedback(
                title: "Unsupported Clop request",
                subtitle: "Request version \(version) is not supported."
            )
        }

        let selection: InputSelection
        do {
            selection = try collector.collect(
                request: request.input,
                clipboard: clipboard,
                finder: finder,
                recursiveFolders: environment.checkbox("recursiveFolders")
            )
        } catch {
            if request.route == .configuration,
               query.hasPrefix(ConfigurationMenu.namespacePrefix) {
                return ConfigurationMenu.namespaceResponse(
                    query: query,
                    environment: environment
                )
            }
            return ActionMenu.collectionErrorResponse(
                error,
                context: contextOverride ?? context(for: request.input)
            )
        }

        let context = contextOverride ?? context(for: request.input)
        switch request.route {
        case let .menu(action):
            guard let action else {
                return ActionMenu.response(
                    for: selection,
                    query: query,
                    context: context,
                    environment: environment
                )
            }
            return parameterMenu(
                action: action,
                selection: selection,
                context: context,
                query: query,
                environment: environment
            )
        case .configuration:
            return ActionMenu.response(
                for: selection,
                query: query,
                context: context,
                environment: environment
            )
        case let .execute(action, overrides):
            guard supports(action: action, selection: selection) else {
                if case let .convert(choice) = action {
                    return feedback(
                        title: "Conversion does not support this input",
                        subtitle: "\(choice.displayFormat) conversion requires \(choice.media.rawValue) input."
                    )
                }
                return feedback(
                    title: "Action does not support this input",
                    subtitle: "Choose an action compatible with every supplied item."
                )
            }
            var execution: ExecutionOptions
            do {
                execution = try environment.resolvedExecutionOptions(
                    preserveOriginal: preserveOriginalOverride
                )
                execution = try applying(
                    overrides,
                    to: execution,
                    action: action,
                    environment: environment
                )
            } catch let error as ExecutionOverrideError {
                return feedback(
                    title: "Output override not supported",
                    subtitle: error.localizedDescription
                )
            } catch {
                return feedback(
                    title: "Unable to read settings",
                    subtitle: error.localizedDescription
                )
            }
            let operationInputs = inputs(
                for: action,
                selection: selection
            )
            guard !operationInputs.isEmpty else {
                if case let .optimiseMedia(request) = action {
                    return feedback(
                        title: "Optimize controls do not support this input",
                        subtitle: "\(request.media.displayName) controls require \(request.media.rawValue) input."
                    )
                }
                return feedback(
                    title: "No files to process",
                    subtitle: "Choose one or more files and try again."
                )
            }
            let operation = OperationRequest(
                inputs: operationInputs,
                action: action,
                execution: execution
            )
            guard let operationJSON = try? JSONOutput.string(
                for: operation,
                prettyPrinted: false
            ) else {
                return feedback(
                    title: "Unable to prepare Clop request",
                    subtitle: "The normalized operation could not be encoded."
                )
            }
            return ExecuteMode.response(
                requestJSON: operationJSON,
                builder: builder,
                runner: runner
            )
        }
    }

    static func quietFeedback(
        requestJSON: String,
        clipboard: ClipboardReading = SystemClipboardReader(),
        finder: any FinderSelectionReading = SystemFinderSelectionReader(),
        collector: InputCollector = InputCollector(),
        environment: Environment = Environment(),
        builder: ClopCommandBuilder = ClopCommandBuilder(),
        runner: any ClopProcessRunning = FoundationClopProcessRunner(),
        preserveOriginalOverride: Bool? = nil
    ) -> String? {
        let response = response(
            requestJSON: requestJSON,
            clipboard: clipboard,
            finder: finder,
            collector: collector,
            environment: environment,
            builder: builder,
            runner: runner,
            preserveOriginalOverride: preserveOriginalOverride
        )
        guard let item = response.items.first else {
            return nil
        }
        let isSuccess = isSuccessfulExecution(item.title)
        if isSuccess && environment.executionOptions.showClopUI {
            return nil
        }
        guard isSuccess ? environment.completionNotifications
            : environment.errorNotifications else {
            return nil
        }
        return item.subtitle.isEmpty
            ? item.title
            : "\(item.title): \(item.subtitle)"
    }

    private static func parameterMenu(
        action: ClopAction,
        selection: InputSelection,
        context: ActionInputContext,
        query: String,
        environment: Environment
    ) -> ScriptFilterResponse {
        let supported = ActionCatalog.validActions(for: selection)
            .contains(where: { $0.action == action })
        guard supported else {
            return feedback(
                title: "Action does not support this input",
                subtitle: "Choose an action compatible with every supplied item."
            )
        }

        let parameterRequest = ParameterStepRequest(
            action: action,
            inputs: selection.inputs,
            inputContext: context,
            mediaKinds: selection.mediaKinds,
            itemKinds: selection.itemKinds,
            ambiguousKinds: selection.ambiguousKinds
        )
        switch action {
        case .optimise:
            let state = MenuState.optimise(parameterRequest)
            guard let stateJSON = try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            ) else {
                return feedback(
                    title: "Unable to open Optimize",
                    subtitle: "The controls menu state could not be encoded."
                )
            }
            return OptimizeParameterMenu.response(
                stateJSON: stateJSON,
                query: query,
                environment: environment
            )
        case .crop:
            let state = MenuState.crop(parameterRequest)
            guard let stateJSON = try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            ) else {
                return feedback(
                    title: "Unable to open Crop / Resize",
                    subtitle: "The menu state could not be encoded."
                )
            }
            return CropParameterMenu.response(
                stateJSON: stateJSON,
                query: query,
                environment: environment
            )
        case .downscale:
            let state = MenuState.downscale(parameterRequest)
            guard let stateJSON = try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            ) else {
                return feedback(
                    title: "Unable to open Downscale",
                    subtitle: "The menu state could not be encoded."
                )
            }
            return DownscaleParameterMenu.response(
                stateJSON: stateJSON,
                query: query,
                environment: environment
            )
        case .convertImage, .convertVideo, .convertAudio:
            let state = MenuState.conversion(parameterRequest)
            guard let stateJSON = try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            ) else {
                return feedback(
                    title: "Unable to open Convert",
                    subtitle: "The menu state could not be encoded."
                )
            }
            return ConversionParameterMenu.response(
                stateJSON: stateJSON,
                query: query,
                environment: environment
            )
        case .cropPDF:
            let state = MenuState.cropPDF(parameterRequest)
            guard let stateJSON = try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            ) else {
                return feedback(
                    title: "Unable to open Crop PDF",
                    subtitle: "The menu state could not be encoded."
                )
            }
            return CropPDFParameterMenu.response(
                stateJSON: stateJSON,
                query: query,
                environment: environment
            )
        case .pipeline:
            let state = MenuState.pipeline(parameterRequest)
            guard let stateJSON = try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            ) else {
                return feedback(
                    title: "Unable to open Pipeline",
                    subtitle: "The menu state could not be encoded."
                )
            }
            return PipelineMenu.response(
                stateJSON: stateJSON,
                query: query,
                environment: environment
            )
        case .uncropPDF, .stripMetadata:
            return ActionMenu.response(
                for: selection,
                query: query,
                context: context,
                environment: environment
            )
        }
    }

    private static func supports(
        action: ActionRequest,
        selection: InputSelection
    ) -> Bool {
        let menuAction: ClopAction
        switch action {
        case .optimise:
            menuAction = .optimise
        case .optimiseMedia(let request):
            menuAction = .optimise
            guard OptimizeControlParser.isSupported(request),
                  !inputs(for: action, selection: selection).isEmpty else {
                return false
            }
        case .crop:
            menuAction = .crop
        case .downscale:
            menuAction = .downscale
        case .convert(let choice):
            menuAction = choice.media.action
            guard ConversionCatalog.isSupported(choice) else {
                return false
            }
        case .cropPDF:
            menuAction = .cropPDF
        case .uncropPDF:
            menuAction = .uncropPDF
        case .stripMetadata:
            menuAction = .stripMetadata
        case .pipeline:
            menuAction = .pipeline
        }
        return ActionCatalog.validActions(for: selection)
            .contains(where: { $0.action == menuAction })
    }

    private static func inputs(
        for action: ActionRequest,
        selection: InputSelection
    ) -> [String] {
        guard case let .optimiseMedia(request) = action else {
            return selection.inputs
        }
        return mediaInputs(
            for: request.media,
            selection: selection
        )
    }

    private static func mediaInputs(
        for media: OptimizeMediaKind,
        selection: InputSelection
    ) -> [String] {
        if !selection.ambiguousKinds.isEmpty {
            return selection.inputs
        }
        let kinds = selection.itemKinds.isEmpty
            ? Array(repeating: InputItemKind.localFile, count: selection.inputs.count)
            : selection.itemKinds
        let detector = MediaKindDetector()
        return selection.inputs.enumerated().compactMap { index, input in
            let kind = index < kinds.count ? kinds[index] : .localFile
            switch kind {
            case .folder:
                return input
            case .remoteURL:
                guard let url = URL(string: input) else { return nil }
                return detector.kind(for: url) == media.mediaKind ? input : nil
            case .localFile:
                return detector.kind(for: URL(fileURLWithPath: input))
                    == media.mediaKind ? input : nil
            }
        }
    }

    private static func applying(
        _ overrides: ExecutionOverrides?,
        to execution: ExecutionOptions,
        action: ActionRequest,
        environment: Environment
    ) throws -> ExecutionOptions {
        guard let output = overrides?.output else {
            return execution
        }
        if case .stripMetadata = action, output != .default {
            throw ExecutionOverrideError.unsupportedOutputOverride
        }

        var resolved = execution
        switch output {
        case .default:
            break
        case .template:
            resolved.output = .sameFolder(
                template: try configuredOutputTemplate(environment: environment)
            )
        case let .customTemplate(template):
            resolved.output = .sameFolder(template: template)
        case .disabled:
            resolved.output = .inPlace
        }
        return resolved
    }

    private static func configuredOutputTemplate(
        environment: Environment
    ) throws -> String {
        do {
            return try PresetStore(environment: environment).load().outputTemplate
        } catch PresetStoreError.missingWorkflowDataDirectory {
            return SettingsDocument.builtInOutputTemplate
        }
    }

    private static func context(
        for input: ClopInputRequest
    ) -> ActionInputContext {
        switch input {
        case .clipboard:
            return .clipboard
        case .finderSelection:
            return .selected
        case .explicit:
            return .arguments
        }
    }

    private static func feedback(
        title: String,
        subtitle: String
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: title,
                subtitle: subtitle,
                arg: "",
                valid: false
            )
        ])
    }
}

private enum ExecutionOverrideError: LocalizedError {
    case unsupportedOutputOverride

    var errorDescription: String? {
        switch self {
        case .unsupportedOutputOverride:
            return "Strip Metadata does not support output templates."
        }
    }
}
