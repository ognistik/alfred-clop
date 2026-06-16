import Foundation

enum AlfredClopCommand {
    static func run(arguments: [String] = Array(CommandLine.arguments.dropFirst())) {
        if let command = arguments.first,
           ["menu", "execute", "configure", "request", "automate"].contains(command) {
            do {
                try PresetStore().ensureExists()
            } catch {
                let message = "Unable to initialize settings: \(error.localizedDescription)"
                if arguments.contains("--quiet")
                    || ["configure", "automate"].contains(command) {
                    printText(message)
                } else {
                    JSONOutput.print(errorResponse(
                        title: "Unable to initialize settings",
                        subtitle: error.localizedDescription
                    ))
                }
                return
            }
        }
        switch arguments.first {
        case "probe":
            JSONOutput.print(ProbeMode.response())
        case "menu":
            JSONOutput.print(menuResponse(arguments: Array(arguments.dropFirst())))
        case "execute":
            execute(arguments: Array(arguments.dropFirst()))
        case "configure":
            configure(arguments: Array(arguments.dropFirst()))
        case "request":
            request(arguments: Array(arguments.dropFirst()))
        case "route":
            requestRoute(arguments: Array(arguments.dropFirst()))
        case "handoff":
            requestHandoff(arguments: Array(arguments.dropFirst()))
        case "automate":
            automate(arguments: Array(arguments.dropFirst()))
        case nil:
            JSONOutput.print(errorResponse(
                title: "Missing Alfred Clop mode",
                subtitle: "Run alfred-clop menu, request, execute, or probe."
            ))
        default:
            JSONOutput.print(errorResponse(
                title: "Unknown Alfred Clop mode",
                subtitle: "Unsupported mode: \(arguments[0])"
            ))
        }
    }

    private static func request(arguments: [String]) {
        let requestJSON: String
        do {
            requestJSON = try resolvedRequestJSON(arguments)
        } catch let error as PublicRequestError {
            if arguments.contains("--quiet") {
                printText("\(error.title): \(error.detail)")
            } else {
                JSONOutput.print(errorResponse(
                    title: error.title,
                    subtitle: error.detail
                ))
            }
            return
        } catch {
            JSONOutput.print(errorResponse(
                title: "Missing Clop request",
                subtitle: "Pass shorthand input or request JSON."
            ))
            return
        }
        let context = value(after: "--input-context", in: arguments)
            .flatMap(ActionInputContext.init(rawValue:))
        if arguments.contains("--quiet") {
            if let feedback = ClopRequestDispatcher.quietFeedback(
                requestJSON: requestJSON
            ) {
                printText(feedback)
            }
            return
        }
        let response = ClopRequestDispatcher.response(
            requestJSON: requestJSON,
            query: value(after: "--query", in: arguments) ?? "",
            contextOverride: context
        )
        if let request = try? JSONDecoder().decode(
            ClopRequest.self,
            from: Data(requestJSON.utf8)
        ), case .execute = request.route {
            if let feedback = response.items.first {
                let successful = ClopRequestDispatcher.isSuccessfulExecution(
                    feedback.title
                )
                let environment = Environment()
                let shouldNotify = successful
                    ? environment.completionNotifications
                        && !environment.executionOptions.showClopUI
                    : environment.errorNotifications
                if shouldNotify {
                    notify(feedback.subtitle.isEmpty
                        ? feedback.title
                        : "\(feedback.title): \(feedback.subtitle)"
                    )
                }
            }
            JSONOutput.print(ScriptFilterResponse())
            return
        }
        JSONOutput.print(response)
    }

    private static func requestRoute(arguments: [String]) {
        guard let request = try? resolvedRequest(arguments) else {
            printText("menu")
            return
        }
        switch request.route {
        case .menu, .configuration:
            printText("menu")
        case .execute:
            printText("execute")
        }
    }

    private static func requestHandoff(arguments: [String]) {
        guard let publicRequest = value(after: "--public-request", in: arguments),
              let json = menuHandoffJSON(publicRequest: publicRequest) else {
            printText("Invalid menu handoff.")
            return
        }
        printText(json)
    }

    static func menuHandoffJSON(publicRequest: String) -> String? {
        let argument: String
        if let request = try? PublicRequestParser.parse(publicRequest),
           request.route == .configuration {
            argument = ConfigurationMenu.namespacePrefix
        } else {
            argument = ""
        }
        let output: [String: Any] = [
            "alfredworkflow": [
                "arg": argument,
                "variables": [
                    ActionMenu.publicRequestVariable: publicRequest,
                    "alfred_clop_public_route": "menu"
                ]
            ]
        ]
        guard JSONSerialization.isValidJSONObject(output),
              let data = try? JSONSerialization.data(withJSONObject: output),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func resolvedRequest(_ arguments: [String]) throws -> ClopRequest {
        if let publicRequest = value(after: "--public-request", in: arguments) {
            return try PublicRequestParser.parse(publicRequest)
        }
        if let requestJSON = value(after: "--request-json", in: arguments) {
            return try JSONDecoder().decode(
                ClopRequest.self,
                from: Data(requestJSON.utf8)
            )
        }
        throw PublicRequestError.empty
    }

    private static func resolvedRequestJSON(_ arguments: [String]) throws -> String {
        try JSONOutput.string(
            for: resolvedRequest(arguments),
            prettyPrinted: false
        )
    }

    private static func automate(arguments: [String]) {
        let input: ClopInputRequest
        switch value(after: "--input-source", in: arguments) {
        case "clipboard":
            input = .clipboard
        case "finderSelection":
            input = .finderSelection
        case "explicit":
            guard let value = value(after: "--input-value", in: arguments) else {
                printText("Missing Clop input: Explicit input requires a value.")
                return
            }
            input = .explicit(items: [value], extractText: true)
        default:
            printText("Invalid Clop input: Use clipboard, finderSelection, or explicit.")
            return
        }

        let environment = Environment()
        let aggressive: Bool
        if arguments.contains("--aggressive") {
            aggressive = true
        } else if arguments.contains("--standard") {
            aggressive = false
        } else if arguments.contains("--invert-aggressive") {
            aggressive = !environment.aggressiveByDefault
        } else {
            aggressive = environment.aggressiveByDefault
        }
        let preserveOriginal = arguments.contains("--invert-preserve")
            ? !environment.preserveOriginal
            : nil
        let request = ClopRequest(
            input: input,
            route: .execute(action: .optimise(aggressive: aggressive))
        )
        guard let json = try? JSONOutput.string(
            for: request,
            prettyPrinted: false
        ) else {
            printText("Unable to encode Clop request.")
            return
        }
        if let feedback = ClopRequestDispatcher.quietFeedback(
            requestJSON: json,
            preserveOriginalOverride: preserveOriginal
        ) {
            printText(feedback)
        }
    }

    private static func execute(arguments: [String]) {
        guard let requestJSON = value(after: "--request-json", in: arguments) else {
            if arguments.contains("--quiet") {
                printText("Missing Clop request: The execute mode requires OperationRequest JSON.")
            } else {
                JSONOutput.print(errorResponse(
                    title: "Missing Clop request",
                    subtitle: "The execute mode requires OperationRequest JSON."
                ))
            }
            return
        }

        if arguments.contains("--quiet") {
            if let feedback = ExecuteMode.quietFeedback(
                requestJSON: requestJSON,
                environment: Environment()
            ) {
                printText(feedback)
            }
        } else {
            JSONOutput.print(ExecuteMode.response(requestJSON: requestJSON))
        }
    }

    private static func configure(arguments: [String]) {
        guard let stateJSON = value(after: "--menu-state", in: arguments) else {
            printText("Unable to update settings: Missing Configuration state.")
            return
        }
        if let feedback = ConfigurationMenu.quietMutationFeedback(
            stateJSON: stateJSON
        ) {
            printText(feedback)
        }
    }

    private static func menuResponse(arguments: [String]) -> ScriptFilterResponse {
        let query = value(after: "--query", in: arguments) ?? ""

        if let stateJSON = value(after: "--menu-state", in: arguments) {
            guard let state = try? JSONDecoder().decode(
                MenuState.self,
                from: Data(stateJSON.utf8)
            ) else {
                return errorResponse(
                    title: "Unable to open Clop menu",
                    subtitle: "The typed menu state is invalid."
                )
            }

            switch state.mode {
            case .optimise, .optimisePresetRemoval:
                return OptimizeParameterMenu.response(
                    stateJSON: stateJSON,
                    query: query
                )
            case .crop, .cropPresetRemoval:
                return CropParameterMenu.response(
                    stateJSON: stateJSON,
                    query: query
                )
            case .downscale, .downscalePresetRemoval:
                return DownscaleParameterMenu.response(
                    stateJSON: stateJSON,
                    query: query
                )
            case .conversion, .conversionPresetRemoval:
                return ConversionParameterMenu.response(
                    stateJSON: stateJSON,
                    query: query
                )
            case .configuration,
                 .configurationOutputTemplate,
                 .configurationSaveOutput,
                 .configurationResetOutputConfirmation,
                 .configurationResetOutput,
                 .configurationResetPresetsConfirmation,
                 .configurationResetPresets,
                 .configurationCacheCleanupConfirmation,
                 .configurationCacheCleanup:
                return ConfigurationMenu.response(
                    stateJSON: stateJSON,
                    query: query
                )
            case .actions:
                if state.parameterRequest != nil {
                    return errorResponse(
                        title: "This action needs more information",
                        subtitle: "Its parameter menu is not available yet."
                    )
                }
            }
        }
        if let requestJSON = value(after: "--request-json", in: arguments) {
            let context = value(after: "--input-context", in: arguments)
                .flatMap(ActionInputContext.init(rawValue:))
            return ClopRequestDispatcher.response(
                requestJSON: requestJSON,
                query: query,
                contextOverride: context
            )
        }
        if let explicitInput = value(after: "--explicit-input", in: arguments) {
            let context = value(after: "--input-context", in: arguments)
                .flatMap(ActionInputContext.init(rawValue:))
                ?? .selected
            return ActionMenu.response(
                request: .explicit(items: [explicitInput], extractText: true),
                query: query,
                context: context
            )
        }
        if value(after: "--input-source", in: arguments) == "keywordClipboard" {
            return ActionMenu.keywordResponse(
                clipboard: SystemClipboardReader(),
                query: query
            )
        }
        if value(after: "--input-source", in: arguments) == "clipboard" {
            return ActionMenu.response(
                clipboard: SystemClipboardReader(),
                query: query
            )
        }
        if let inputJSON = value(after: "--input-json", in: arguments) {
            let context = value(after: "--input-context", in: arguments)
                .flatMap(ActionInputContext.init(rawValue:))
                ?? .selected
            return ActionMenu.response(
                inputJSON: inputJSON,
                query: query,
                context: context
            )
        }
        let paths = values(after: "--input-paths", in: arguments)
        if !paths.isEmpty {
            let context = value(after: "--input-context", in: arguments)
                .flatMap(ActionInputContext.init(rawValue:))
                ?? .selected
            return ActionMenu.response(
                paths: paths,
                query: query,
                context: context
            )
        }

        return errorResponse(
            title: "Missing selected files",
            subtitle: "Run Clop from Universal Actions on one or more files."
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private static func values(after flag: String, in arguments: [String]) -> [String] {
        guard let flagIndex = arguments.firstIndex(of: flag) else {
            return []
        }

        let startIndex = arguments.index(after: flagIndex)
        let endIndex = arguments[startIndex...]
            .firstIndex(where: { $0.hasPrefix("--") })
            ?? arguments.endIndex
        return Array(arguments[startIndex..<endIndex])
    }

    private static func errorResponse(title: String, subtitle: String) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: title,
                subtitle: subtitle,
                arg: "",
                valid: false
            )
        ])
    }

    private static func printText(_ text: String) {
        FileHandle.standardOutput.write(Data("\(text)\n".utf8))
    }

    private static func notify(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-", "Alfred Clop", text]
        let input = Pipe()
        process.standardInput = input
        do {
            try process.run()
            input.fileHandleForWriting.write(Data("""
            on run argv
                display notification (item 2 of argv) with title (item 1 of argv)
            end run
            """.utf8))
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            try? input.fileHandleForWriting.close()
        }
    }
}

AlfredClopCommand.run()
