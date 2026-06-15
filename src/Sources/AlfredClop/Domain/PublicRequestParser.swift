import Foundation

enum PublicRequestError: Error, Equatable {
    case empty
    case missingSeparator
    case missingInput
    case mixedInputSources
    case unknownDirective(String)
    case unknownAction(String)
    case unsupportedExecution(String)
    case missingParameter(String)
    case invalidParameter(String, String)
    case unexpectedParameter(String)

    var title: String { "Invalid Clop request" }

    var detail: String {
        switch self {
        case .empty:
            return "Pass finder, clipboard, or one or more paths or URLs."
        case .missingSeparator:
            return "Add a blank line between directives and input."
        case .missingInput:
            return "Add finder, clipboard, or one or more paths or URLs after the blank line."
        case .mixedInputSources:
            return "Use finder, clipboard, or explicit paths and URLs, but do not combine them."
        case .unknownDirective(let directive):
            return "Unknown directive: \(directive)"
        case .unknownAction(let action):
            return "Unknown workflow action: \(action)"
        case .unsupportedExecution(let action):
            return "\(action) execution is not available yet. Open its menu instead."
        case .missingParameter(let parameter):
            return "Missing required parameter: \(parameter)"
        case let .invalidParameter(parameter, value):
            return "Invalid \(parameter): \(value)"
        case .unexpectedParameter(let parameter):
            return "The selected action does not use the \(parameter) parameter."
        }
    }
}

enum PublicRequestParser {
    static func parse(_ value: String) throws -> ClopRequest {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PublicRequestError.empty
        }

        if trimmed.first == "{" {
            do {
                return try JSONDecoder().decode(
                    ClopRequest.self,
                    from: Data(trimmed.utf8)
                )
            } catch {
                throw PublicRequestError.invalidParameter(
                    "JSON request",
                    "use the documented typed request format"
                )
            }
        }

        var lines = normalized.components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        guard let separator = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            if looksLikeDirective(lines[0]) {
                throw PublicRequestError.missingSeparator
            }
            return ClopRequest(
                input: try input(from: lines),
                route: .menu(action: nil)
            )
        }

        let directiveLines = Array(lines[..<separator])
        let inputLines = Array(lines[(separator + 1)...])
        guard !directiveLines.isEmpty else {
            return ClopRequest(
                input: try input(from: inputLines),
                route: .menu(action: nil)
            )
        }

        let directives = try parseDirectives(directiveLines)
        return ClopRequest(
            input: try input(from: inputLines),
            route: try route(from: directives)
        )
    }

    private static func looksLikeDirective(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else {
            return false
        }
        let key = normalizedName(String(line[..<colon]))
        return key == "menu" || key == "execute" || action(for: key) != nil
    }

    private static func parseDirectives(
        _ lines: [String]
    ) throws -> [(key: String, value: String)] {
        try lines.map { line in
            guard let colon = line.firstIndex(of: ":") else {
                throw PublicRequestError.unknownDirective(line)
            }
            let key = normalizedName(String(line[..<colon]))
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw PublicRequestError.unknownDirective(line)
            }
            return (key, value)
        }
    }

    private static func input(from lines: [String]) throws -> ClopInputRequest {
        let values = lines.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !values.isEmpty else {
            throw PublicRequestError.missingInput
        }

        let sources = values.map(normalizedName)
        if sources == ["finder"] {
            return .finderSelection
        }
        if sources == ["clipboard"] {
            return .clipboard
        }
        if sources.contains("finder") || sources.contains("clipboard") {
            throw PublicRequestError.mixedInputSources
        }
        return .explicit(items: values, extractText: false)
    }

    private static func route(
        from directives: [(key: String, value: String)]
    ) throws -> ClopRouteRequest {
        guard let first = directives.first else {
            return .menu(action: nil)
        }

        if first.key == "menu" {
            guard !first.value.isEmpty else {
                return .menu(action: nil)
            }
            if normalizedName(first.value) == "configuration" {
                guard directives.count == 1 else {
                    throw PublicRequestError.unexpectedParameter(
                        directives[1].key
                    )
                }
                return .configuration
            }
            guard let action = action(for: first.value) else {
                throw PublicRequestError.unknownAction(first.value)
            }
            guard directives.count == 1 else {
                throw PublicRequestError.unexpectedParameter(directives[1].key)
            }
            return .menu(action: action)
        }

        if first.key == "execute" {
            guard let action = action(for: first.value) else {
                throw PublicRequestError.unknownAction(first.value)
            }
            return .execute(
                action: try execution(
                    for: action,
                    parameters: Array(directives.dropFirst())
                )
            )
        }

        guard first.value.isEmpty, let action = action(for: first.key) else {
            throw PublicRequestError.unknownDirective(first.key)
        }
        guard directives.count == 1 else {
            throw PublicRequestError.unexpectedParameter(directives[1].key)
        }
        return .menu(action: action)
    }

    private static func execution(
        for action: ClopAction,
        parameters: [(key: String, value: String)]
    ) throws -> ActionRequest {
        let values = try parameterDictionary(parameters)
        switch action {
        case .optimise:
            try rejectUnknown(values, allowed: ["aggressive"])
            return .optimise(
                aggressive: try boolean(
                    values["aggressive"],
                    name: "aggressive",
                    defaultValue: false
                )
            )
        case .crop:
            try rejectUnknown(values, allowed: ["size", "smart crop"])
            guard let sizeValue = values["size"], !sizeValue.isEmpty else {
                throw PublicRequestError.missingParameter("size")
            }
            guard let size = CropSizeParser.parse(sizeValue) else {
                throw PublicRequestError.invalidParameter("size", sizeValue)
            }
            return .crop(
                size: size.value,
                smartCrop: try boolean(
                    values["smart crop"],
                    name: "smart crop",
                    defaultValue: false
                ),
                longEdge: size.longEdge
            )
        case .uncropPDF:
            try rejectUnknown(values, allowed: [])
            return .uncropPDF
        case .stripMetadata:
            try rejectUnknown(values, allowed: [])
            return .stripMetadata
        case .downscale, .convertImage, .convertVideo, .convertAudio, .cropPDF:
            throw PublicRequestError.unsupportedExecution(title(for: action))
        }
    }

    private static func parameterDictionary(
        _ parameters: [(key: String, value: String)]
    ) throws -> [String: String] {
        var values = [String: String]()
        for parameter in parameters {
            guard values[parameter.key] == nil else {
                throw PublicRequestError.invalidParameter(
                    parameter.key,
                    "specified more than once"
                )
            }
            values[parameter.key] = parameter.value
        }
        return values
    }

    private static func rejectUnknown(
        _ parameters: [String: String],
        allowed: Set<String>
    ) throws {
        if let unknown = parameters.keys.sorted().first(where: {
            !allowed.contains($0)
        }) {
            throw PublicRequestError.unexpectedParameter(unknown)
        }
    }

    private static func boolean(
        _ value: String?,
        name: String,
        defaultValue: Bool
    ) throws -> Bool {
        guard let value else {
            return defaultValue
        }
        switch normalizedName(value) {
        case "true", "yes", "on":
            return true
        case "false", "no", "off":
            return false
        default:
            throw PublicRequestError.invalidParameter(name, value)
        }
    }

    private static func action(for value: String) -> ClopAction? {
        actionNames[normalizedName(value)]
    }

    private static func title(for action: ClopAction) -> String {
        ActionCatalog.definitions.first(where: { $0.action == action })?.title
            ?? action.rawValue
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let actionNames: [String: ClopAction] = [
        "optimize": .optimise,
        "crop": .crop,
        "crop / resize": .crop,
        "downscale": .downscale,
        "convert image": .convertImage,
        "convert video": .convertVideo,
        "convert audio": .convertAudio,
        "crop pdf": .cropPDF,
        "crop pdf (reversible)": .cropPDF,
        "uncrop pdf": .uncropPDF,
        "strip metadata": .stripMetadata
    ]
}
