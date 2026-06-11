import Foundation

enum ActionInputContext: String {
    case selected
    case clipboard
    case arguments

    var subtitlePrefix: String {
        switch self {
        case .selected:
            return "Selected files"
        case .clipboard:
            return "Copied files"
        case .arguments:
            return "Passed files"
        }
    }
}

struct ActionDefinition: Equatable {
    var action: ClopAction
    var title: String
    var subtitle: String
    var aliases: [String]
    var supportedKinds: Set<MediaKind>
    var requiresParameters: Bool

    var searchTerms: [String] {
        [action.rawValue, title] + aliases
    }
}

enum ActionCatalog {
    static let definitions: [ActionDefinition] = [
        ActionDefinition(
            action: .optimise,
            title: "Optimize",
            subtitle: "Compress with Clop",
            aliases: ["compress", "shrink", "small", "optimise", "optimize"],
            supportedKinds: [.image, .video, .audio, .pdf],
            requiresParameters: false
        ),
        ActionDefinition(
            action: .aggressiveOptimise,
            title: "Aggressive Optimize",
            subtitle: "Use Clop's aggressive optimization",
            aliases: ["aggressive", "smaller", "compress more"],
            supportedKinds: [.image, .video, .audio, .pdf],
            requiresParameters: false
        ),
        ActionDefinition(
            action: .crop,
            title: "Crop / Resize",
            subtitle: "Crop to dimensions, aspect ratio, or edge size",
            aliases: ["crop", "resize", "dimensions", "ratio", "edge"],
            supportedKinds: [.image, .video, .pdf],
            requiresParameters: true
        ),
        ActionDefinition(
            action: .downscale,
            title: "Downscale",
            subtitle: "Scale images/videos or reduce audio bitrate",
            aliases: ["downscale", "scale", "half", "reduce", "smaller"],
            supportedKinds: [.image, .video, .audio],
            requiresParameters: true
        ),
        ActionDefinition(
            action: .convert,
            title: "Convert Image",
            subtitle: "Convert images to WebP, AVIF, or HEIC",
            aliases: ["convert", "webp", "avif", "heic", "format"],
            supportedKinds: [.image],
            requiresParameters: true
        ),
        ActionDefinition(
            action: .cropPDF,
            title: "Reversible PDF Crop",
            subtitle: "Crop PDF pages using Clop's reversible crop box",
            aliases: ["pdf", "crop pdf", "ipad", "paper", "device"],
            supportedKinds: [.pdf],
            requiresParameters: true
        ),
        ActionDefinition(
            action: .uncropPDF,
            title: "Uncrop PDF",
            subtitle: "Remove a reversible PDF crop box",
            aliases: ["uncrop", "restore pdf", "remove crop"],
            supportedKinds: [.pdf],
            requiresParameters: false
        ),
        ActionDefinition(
            action: .stripMetadata,
            title: "Strip Metadata",
            subtitle: "Remove EXIF and metadata from images/videos",
            aliases: ["metadata", "exif", "privacy", "strip"],
            supportedKinds: [.image, .video],
            requiresParameters: false
        )
    ]

    static func validActions(for mediaKinds: [MediaKind]) -> [ActionDefinition] {
        let selectedKinds = Set(mediaKinds)
        return definitions.filter { definition in
            selectedKinds.allSatisfy(definition.supportedKinds.contains)
        }
    }
}

enum ActionMenu {
    static let inputJSONVariable = "alfred_clop_input_json"
    static let inputContextVariable = "alfred_clop_input_context"

    static func response(
        clipboard: ClipboardReading,
        query: String,
        collector: InputCollector = InputCollector()
    ) -> ScriptFilterResponse {
        do {
            let selection = try collector.collect(clipboard: clipboard)
            let supportedKinds: Set<MediaKind> = [
                .image, .video, .audio, .pdf
            ]
            guard selection.mediaKinds.contains(where: supportedKinds.contains) else {
                return errorItem(
                    title: "No supported files in clipboard",
                    subtitle: "Copy one or more images, videos, audio files, or PDFs."
                )
            }
            return response(
                for: selection,
                query: query,
                context: .clipboard
            )
        } catch InputCollectionError.noPaths {
            return errorItem(
                title: "No supported files in clipboard",
                subtitle: "Copy one or more files or file paths and try again."
            )
        } catch InputCollectionError.missingPath(let path) {
            return errorItem(
                title: "Clipboard file was not found",
                subtitle: path
            )
        } catch {
            return errorItem(
                title: "Unable to read clipboard files",
                subtitle: error.localizedDescription
            )
        }
    }

    static func response(
        inputJSON: String,
        query: String,
        context: ActionInputContext = .selected,
        collector: InputCollector = InputCollector()
    ) -> ScriptFilterResponse {
        do {
            let selection = try collector.collect(json: inputJSON)
            return response(
                for: selection,
                query: query,
                context: context
            )
        } catch InputCollectionError.invalidJSON {
            return errorItem(
                title: "Unable to read selected files",
                subtitle: "The input JSON is invalid."
            )
        } catch InputCollectionError.noPaths {
            return errorItem(
                title: "No files selected",
                subtitle: "Select one or more media files and try again."
            )
        } catch InputCollectionError.missingPath(let path) {
            return errorItem(
                title: "Selected file was not found",
                subtitle: path
            )
        } catch {
            return errorItem(
                title: "Unable to inspect selected files",
                subtitle: error.localizedDescription
            )
        }
    }

    static func response(
        paths: [String],
        query: String,
        context: ActionInputContext = .selected,
        collector: InputCollector = InputCollector()
    ) -> ScriptFilterResponse {
        do {
            let selection = try collector.collect(paths: paths)
            return response(
                for: selection,
                query: query,
                context: context
            )
        } catch InputCollectionError.noPaths {
            switch context {
            case .arguments:
                return errorItem(
                    title: "No file paths provided",
                    subtitle: "Pass one or more file paths to the external trigger."
                )
            case .selected, .clipboard:
                return errorItem(
                    title: "No files selected",
                    subtitle: "Run Clop from Universal Actions on one or more files."
                )
            }
        } catch InputCollectionError.missingPath(let path) {
            return errorItem(
                title: context == .arguments
                    ? "Passed file was not found"
                    : "Selected file was not found",
                subtitle: path
            )
        } catch {
            return errorItem(
                title: "Unable to inspect selected files",
                subtitle: error.localizedDescription
            )
        }
    }

    static func response(
        for selection: InputSelection,
        query: String,
        context: ActionInputContext = .selected
    ) -> ScriptFilterResponse {
        if selection.mediaKinds.contains(.folder) {
            return errorItem(
                title: "Folders are not supported yet",
                subtitle: "Select individual files instead."
            )
        }
        if selection.mediaKinds.contains(.unknown) {
            return errorItem(
                title: "Unsupported file type",
                subtitle: "Clop cannot process one or more \(context.subtitlePrefix.lowercased())."
            )
        }

        let validActions = ActionCatalog.validActions(for: selection.mediaKinds)
        let filteredActions = ActionMenuSearch.filter(validActions, query: query)

        guard !filteredActions.isEmpty else {
            return errorItem(
                title: "No matching actions",
                subtitle: "Try another search term."
            )
        }

        return ScriptFilterResponse(
            items: filteredActions.map { definition in
                ScriptFilterItem(
                    uid: "action.\(definition.action.rawValue)",
                    title: definition.title,
                    subtitle: "\(context.subtitlePrefix): \(definition.subtitle)",
                    arg: encodedArgument(for: definition, inputs: selection.inputs),
                    valid: true,
                    autocomplete: definition.title,
                    match: definition.searchTerms.joined(separator: " ")
                )
            },
            variables: inputVariables(
                for: selection.inputs,
                context: context
            )
        )
    }

    private static func encodedArgument(
        for definition: ActionDefinition,
        inputs: [String]
    ) -> String {
        do {
            if definition.requiresParameters {
                return try JSONOutput.string(
                    for: ParameterStepRequest(
                        action: definition.action,
                        inputs: inputs
                    ),
                    prettyPrinted: false
                )
            }

            let action: ActionRequest
            switch definition.action {
            case .optimise:
                action = .optimise(aggressive: false)
            case .aggressiveOptimise:
                action = .optimise(aggressive: true)
            case .uncropPDF:
                action = .uncropPDF
            case .stripMetadata:
                action = .stripMetadata
            case .crop, .downscale, .convert, .cropPDF:
                preconditionFailure("Parameter actions must use ParameterStepRequest")
            }

            return try JSONOutput.string(
                for: OperationRequest(
                    inputs: inputs,
                    action: action,
                    execution: defaultExecutionOptions
                ),
                prettyPrinted: false
            )
        } catch {
            return ""
        }
    }

    private static var defaultExecutionOptions: ExecutionOptions {
        ExecutionOptions(
            showClopUI: true,
            copyResult: false,
            output: .inPlace,
            backup: .trustClop,
            adaptiveOptimisation: nil,
            pdfDPI: nil
        )
    }

    private static func inputVariables(
        for paths: [String],
        context: ActionInputContext
    ) -> [String: String]? {
        guard let json = try? JSONOutput.string(
            for: MenuInput(paths: paths),
            prettyPrinted: false
        ) else {
            return nil
        }
        return [
            inputJSONVariable: json,
            inputContextVariable: context.rawValue
        ]
    }

    private static func errorItem(
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

private enum ActionMenuSearch {
    private struct RankedAction {
        var definition: ActionDefinition
        var tier: Int
        var score: Int
        var originalIndex: Int
    }

    static func filter(
        _ definitions: [ActionDefinition],
        query: String
    ) -> [ActionDefinition] {
        let normalizedQuery = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedQuery.isEmpty else {
            return definitions
        }

        return definitions.enumerated().compactMap { index, definition in
            rank(definition, query: normalizedQuery, originalIndex: index)
        }
        .sorted {
            if $0.tier != $1.tier {
                return $0.tier > $1.tier
            }
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.originalIndex < $1.originalIndex
        }
        .map(\.definition)
    }

    private static func rank(
        _ definition: ActionDefinition,
        query: String,
        originalIndex: Int
    ) -> RankedAction? {
        let terms = definition.searchTerms.map(normalize)

        if terms.contains(query) {
            return RankedAction(
                definition: definition,
                tier: 4,
                score: 0,
                originalIndex: originalIndex
            )
        }
        if terms.contains(where: { $0.hasPrefix(query) }) {
            return RankedAction(
                definition: definition,
                tier: 3,
                score: 0,
                originalIndex: originalIndex
            )
        }
        if terms.contains(where: { hasWordBoundaryMatch(query, in: $0) }) {
            return RankedAction(
                definition: definition,
                tier: 2,
                score: 0,
                originalIndex: originalIndex
            )
        }

        let matches = terms.map { term in
            FuzzySearch<String>(query: query, targetText: { $0 })
                .sorted([term])
                .first
        }.compactMap { $0 }

        guard let best = matches.max(by: { $0.score < $1.score }) else {
            return nil
        }

        return RankedAction(
            definition: definition,
            tier: 1,
            score: best.score,
            originalIndex: originalIndex
        )
    }

    private static func hasWordBoundaryMatch(_ query: String, in term: String) -> Bool {
        var searchStart = term.startIndex
        while searchStart < term.endIndex,
              let range = term.range(of: query, range: searchStart..<term.endIndex) {
            if range.lowerBound == term.startIndex {
                return true
            }
            let previous = term.index(before: range.lowerBound)
            if !term[previous].isLetter && !term[previous].isNumber {
                return true
            }
            searchStart = term.index(after: range.lowerBound)
        }
        return false
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
    }
}
