import Foundation

enum AlfredClopCommand {
    static func run(arguments: [String] = Array(CommandLine.arguments.dropFirst())) {
        switch arguments.first {
        case "probe":
            JSONOutput.print(ProbeMode.response())
        case "menu":
            JSONOutput.print(menuResponse(arguments: Array(arguments.dropFirst())))
        case nil:
            JSONOutput.print(errorResponse(
                title: "Missing Alfred Clop mode",
                subtitle: "Run alfred-clop menu or alfred-clop probe."
            ))
        default:
            JSONOutput.print(errorResponse(
                title: "Unknown Alfred Clop mode",
                subtitle: "Unsupported mode: \(arguments[0])"
            ))
        }
    }

    private static func menuResponse(arguments: [String]) -> ScriptFilterResponse {
        let query = value(after: "--query", in: arguments) ?? ""

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
}

AlfredClopCommand.run()
