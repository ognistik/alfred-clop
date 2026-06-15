import Foundation

enum ClopRequestDispatcher {
    static func isSuccessfulExecution(_ title: String) -> Bool {
        [
            "Optimization complete",
            "Aggressive optimization complete",
            "Crop / resize complete",
            "Downscale complete",
            "Conversion complete",
            "PDF uncrop complete",
            "Metadata removed",
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
        case let .execute(action):
            guard supports(action: action, selection: selection) else {
                return feedback(
                    title: "Action does not support this input",
                    subtitle: "Choose an action compatible with every supplied item."
                )
            }
            let execution: ExecutionOptions
            do {
                execution = try environment.resolvedExecutionOptions(
                    preserveOriginal: preserveOriginalOverride
                )
            } catch {
                return feedback(
                    title: "Unable to read settings",
                    subtitle: error.localizedDescription
                )
            }
            let operation = OperationRequest(
                inputs: selection.inputs,
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
            return feedback(
                title: "This action needs more information",
                subtitle: "Its parameter menu is not available yet."
            )
        case .optimise, .uncropPDF, .stripMetadata:
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
        }
        return ActionCatalog.validActions(for: selection)
            .contains(where: { $0.action == menuAction })
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
