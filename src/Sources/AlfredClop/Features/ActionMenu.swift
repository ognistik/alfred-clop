import Foundation

struct ActionDefinition: Equatable {
    var action: ClopAction
    var title: String
    var subtitle: String
    var aliases: [String]
    var supportedKinds: Set<MediaKind>
    var requiresParameters: Bool
    var supportsURLs: Bool
    var supportsFolders: Bool

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
            requiresParameters: false,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .aggressiveOptimise,
            title: "Aggressive Optimize",
            subtitle: "Use Clop's aggressive optimization",
            aliases: ["aggressive", "smaller", "compress more"],
            supportedKinds: [.image, .video, .audio, .pdf],
            requiresParameters: false,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .crop,
            title: "Crop / Resize",
            subtitle: "Crop to dimensions, aspect ratio, or edge size",
            aliases: ["crop", "resize", "dimensions", "ratio", "edge"],
            supportedKinds: [.image, .video, .pdf],
            requiresParameters: true,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .downscale,
            title: "Downscale",
            subtitle: "Scale images/videos or reduce audio bitrate",
            aliases: ["downscale", "scale", "half", "reduce", "smaller"],
            supportedKinds: [.image, .video, .audio],
            requiresParameters: true,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .convert,
            title: "Convert Image",
            subtitle: "Convert images to WebP, AVIF, or HEIC",
            aliases: ["convert", "webp", "avif", "heic", "format"],
            supportedKinds: [.image],
            requiresParameters: true,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .cropPDF,
            title: "Reversible PDF Crop",
            subtitle: "Crop PDF pages using Clop's reversible crop box",
            aliases: ["pdf", "crop pdf", "ipad", "paper", "device"],
            supportedKinds: [.pdf],
            requiresParameters: true,
            supportsURLs: false,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .uncropPDF,
            title: "Uncrop PDF",
            subtitle: "Remove a reversible PDF crop box",
            aliases: ["uncrop", "restore pdf", "remove crop"],
            supportedKinds: [.pdf],
            requiresParameters: false,
            supportsURLs: false,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .stripMetadata,
            title: "Strip Metadata",
            subtitle: "Remove EXIF and metadata from images/videos",
            aliases: ["metadata", "exif", "privacy", "strip"],
            supportedKinds: [.image, .video],
            requiresParameters: false,
            supportsURLs: false,
            supportsFolders: true
        )
    ]

    static func validActions(for mediaKinds: [MediaKind]) -> [ActionDefinition] {
        let selectedKinds = Set(mediaKinds)
        return definitions.filter { definition in
            selectedKinds.allSatisfy(definition.supportedKinds.contains)
        }
    }

    static func validActions(for selection: InputSelection) -> [ActionDefinition] {
        definitions.filter { definition in
            let supportsKnownKinds = selection.mediaKinds.allSatisfy(
                definition.supportedKinds.contains
            )
            let supportsSources = selection.itemKinds.allSatisfy { kind in
                switch kind {
                case .localFile:
                    return true
                case .folder:
                    return definition.supportsFolders
                case .remoteURL:
                    return definition.supportsURLs
                }
            }
            let supportsAmbiguity = selection.ambiguousKinds.allSatisfy { kind in
                switch kind {
                case .folder:
                    return definition.supportsFolders
                case .remoteURL:
                    return definition.supportsURLs
                }
            }
            return supportsKnownKinds && supportsSources && supportsAmbiguity
        }
    }
}

enum ActionMenu {
    static let inputJSONVariable = "alfred_clop_input_json"
    static let inputContextVariable = "alfred_clop_input_context"
    static let menuStateVariable = "alfred_clop_menu_state"
    static let requestKindVariable = "alfred_clop_request_kind"

    static func response(
        clipboard: ClipboardReading,
        query: String,
        collector: InputCollector = InputCollector(),
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        do {
            let selection = try collector.collect(
                clipboard: clipboard,
                recursiveFolders: environment.checkbox("recursiveFolders")
            )
            let supportedKinds: Set<MediaKind> = [
                .image, .video, .audio, .pdf
            ]
            guard selection.mediaKinds.contains(where: supportedKinds.contains)
                || !selection.ambiguousKinds.isEmpty else {
                return errorItem(
                    title: "No supported files in clipboard",
                    subtitle: "Copy one or more images, videos, audio files, or PDFs."
                )
            }
            return response(
                for: selection,
                query: query,
                context: .clipboard,
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch InputCollectionError.noInputs {
            return responseWithoutInputs(
                context: .clipboard,
                title: "No supported files in clipboard",
                subtitle: "Copy one or more files or file paths and try again.",
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch InputCollectionError.missingPath(let path) {
            return errorItem(
                title: "Clipboard file was not found",
                subtitle: path
            )
        } catch {
            return collectionErrorResponse(error, context: .clipboard)
        }
    }

    static func response(
        request: ClopInputRequest,
        query: String,
        context: ActionInputContext,
        clipboard: ClipboardReading = SystemClipboardReader(),
        finder: any FinderSelectionReading = SystemFinderSelectionReader(),
        collector: InputCollector = InputCollector(),
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        do {
            let selection = try collector.collect(
                request: request,
                clipboard: clipboard,
                finder: finder,
                recursiveFolders: environment.checkbox("recursiveFolders")
            )
            return response(
                for: selection,
                query: query,
                context: context,
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch {
            return collectionErrorResponse(error, context: context)
        }
    }

    static func collectionErrorResponse(
        _ error: Error,
        context: ActionInputContext
    ) -> ScriptFilterResponse {
        switch error {
        case InputCollectionError.noInputs:
            return errorItem(
                title: context == .clipboard
                    ? "No supported input in clipboard"
                    : "No supported input provided",
                subtitle: "Use files, folders, or HTTP/HTTPS URLs."
            )
        case InputCollectionError.emptyFinderSelection:
            return errorItem(
                title: "No Finder selection",
                subtitle: "Select one or more Finder items and try again."
            )
        case InputCollectionError.finderSelectionUnavailable:
            return errorItem(
                title: "Unable to read Finder selection",
                subtitle: "Allow Alfred to control Finder, then try again."
            )
        case InputCollectionError.missingPath(let path):
            return errorItem(title: "Input was not found", subtitle: path)
        case InputCollectionError.unsupportedURL(let value):
            return errorItem(
                title: "Unsupported URL",
                subtitle: "Only HTTP and HTTPS URLs are accepted: \(value)"
            )
        case InputCollectionError.credentialedURL:
            return errorItem(
                title: "URL credentials are not allowed",
                subtitle: "Remove the username or password from the URL."
            )
        case InputCollectionError.emptyFolder(let path):
            return errorItem(title: "Folder is empty", subtitle: path)
        case InputCollectionError.unsupportedFolder(let path):
            return errorItem(
                title: "No supported content in folder",
                subtitle: path
            )
        case InputCollectionError.unreadableFolder(let path):
            return errorItem(title: "Unable to read folder", subtitle: path)
        default:
            return errorItem(
                title: "Unable to inspect input",
                subtitle: error.localizedDescription
            )
        }
    }

    static func response(
        inputJSON: String,
        query: String,
        context: ActionInputContext = .selected,
        collector: InputCollector = InputCollector(),
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        do {
            let selection = try collector.collect(json: inputJSON)
            return response(
                for: selection,
                query: query,
                context: context,
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch InputCollectionError.invalidJSON {
            return errorItem(
                title: "Unable to read selected files",
                subtitle: "The input JSON is invalid."
            )
        } catch InputCollectionError.noInputs {
            return responseWithoutInputs(
                context: context,
                title: "No files selected",
                subtitle: "Select one or more media files and try again.",
                environment: environment,
                fileManager: fileManager,
                writer: writer
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
        collector: InputCollector = InputCollector(),
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        do {
            let selection = try collector.collect(paths: paths)
            return response(
                for: selection,
                query: query,
                context: context,
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch InputCollectionError.noInputs {
            switch context {
            case .arguments:
                return responseWithoutInputs(
                    context: context,
                    title: "No file paths provided",
                    subtitle: "Pass one or more file paths to the external trigger.",
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer
                )
            case .selected, .clipboard:
                return responseWithoutInputs(
                    context: context,
                    title: "No files selected",
                    subtitle: "Run Clop from Universal Actions on one or more files.",
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer
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
        context: ActionInputContext = .selected,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        if selection.mediaKinds.contains(.unknown) {
            return errorItem(
                title: "Unsupported file type",
                subtitle: "Clop cannot process one or more \(context.subtitlePrefix.lowercased())."
            )
        }

        let validActions = ActionCatalog.validActions(for: selection)
        let filteredActions = ActionMenuSearch.filter(validActions, query: query)
        let migrationItem = presetMigrationItem(
            status: PresetMigrationCoordinator(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            ).status(),
            selection: selection,
            context: context
        )

        guard !filteredActions.isEmpty || migrationItem != nil else {
            return errorItem(
                title: "No matching actions",
                subtitle: "Try another search term."
            )
        }

        return ScriptFilterResponse(
            items: [migrationItem].compactMap(\.self) + filteredActions.map { definition in
                let argument = encodedArgument(
                    for: definition,
                    inputs: selection.inputs,
                    context: context,
                    environment: environment
                )
                return ScriptFilterItem(
                    uid: "action.\(definition.action.rawValue)",
                    title: definition.title,
                    subtitle: actionSubtitle(
                        definition: definition,
                        selection: selection,
                        context: context
                    ),
                    arg: argument,
                    valid: true,
                    autocomplete: definition.title,
                    match: definition.searchTerms.joined(separator: " "),
                    variables: requestVariables(
                        for: definition,
                        selection: selection,
                        context: context
                    )
                )
            },
            variables: inputVariables(
                for: selection,
                context: context
            )
        )
    }

    private static func presetMigrationItem(
        status: PresetMigrationStatus,
        selection: InputSelection,
        context: ActionInputContext
    ) -> ScriptFilterItem? {
        switch status {
        case .none:
            return nil
        case .available(let migration):
            let request = PresetMigrationRequest(
                sourcePath: migration.sourceURL.path,
                destinationPath: migration.destinationURL.path,
                inputs: selection.inputs,
                mediaKinds: selection.mediaKinds,
                inputContext: context
            )
            let state = MenuState.presetMigrationConfirmation(request)
            let stateJSON = (try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            )) ?? ""
            return ScriptFilterItem(
                uid: "preset.migration",
                title: "Move existing settings",
                subtitle: "Move existing settings to the newly configured location",
                arg: stateJSON,
                valid: true,
                autocomplete: "Move existing settings",
                match: "move migrate existing settings presets recipes location",
                variables: migrationVariables(
                    stateJSON: stateJSON,
                    request: request
                )
            )
        case .conflict:
            return ScriptFilterItem(
                title: "Settings location conflict",
                subtitle: "Settings exist in both locations. Automatic migration is unavailable.",
                arg: "",
                valid: false
            )
        case .sourceMissing:
            return ScriptFilterItem(
                title: "Previous settings file is missing",
                subtitle: "The previous settings could not be found at the last configured location.",
                arg: "",
                valid: false
            )
        case .sourceInvalid(_, let error):
            return ScriptFilterItem(
                title: "Previous settings cannot be moved",
                subtitle: migrationErrorDetail(error),
                arg: "",
                valid: false
            )
        case .metadataInvalid(let error):
            return ScriptFilterItem(
                title: "Unable to read settings location",
                subtitle: migrationErrorDetail(error),
                arg: "",
                valid: false
            )
        }
    }

    static func migrationVariables(
        stateJSON: String,
        request: PresetMigrationRequest
    ) -> [String: String] {
        [
            requestKindVariable: WorkflowRequestKind.parameterStep.rawValue,
            menuStateVariable: stateJSON,
            inputJSONVariable: (try? JSONOutput.string(
                for: MenuInput(paths: request.inputs),
                prettyPrinted: false
            )) ?? "",
            inputContextVariable: request.inputContext.rawValue
        ]
    }

    static func responseWithoutInputs(
        context: ActionInputContext,
        title: String,
        subtitle: String,
        environment: Environment,
        fileManager: FileManager,
        writer: any AtomicDataWriting
    ) -> ScriptFilterResponse {
        let selection = InputSelection(inputs: [], mediaKinds: [])
        let migrationItem = presetMigrationItem(
            status: PresetMigrationCoordinator(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            ).status(),
            selection: selection,
            context: context
        )
        return ScriptFilterResponse(
            items: [migrationItem].compactMap(\.self) + [
                ScriptFilterItem(
                    title: title,
                    subtitle: subtitle,
                    arg: "",
                    valid: false
                )
            ],
            variables: inputVariables(
                for: InputSelection(inputs: [], mediaKinds: []),
                context: context
            )
        )
    }

    static func migrationErrorDetail(_ error: PresetMigrationError) -> String {
        switch error {
        case .missingWorkflowDataDirectory:
            return "Alfred did not provide a workflow data directory."
        case .invalidMetadata:
            return "The workflow-owned settings location metadata is malformed."
        case .unsupportedMetadataVersion(let version):
            return "Settings location metadata version \(version) is unsupported."
        case .sourceMissing:
            return "The previous settings file is missing."
        case .sourceInvalid:
            return "The settings file is malformed or contains unsupported data."
        case .sourceUnsupportedVersion(let version):
            return "Settings schema version \(version) is unsupported."
        case .destinationConflict:
            return "The new location already contains settings."
        case .destinationValidationFailed:
            return "The destination could not be reloaded and validated."
        case .locationChanged:
            return "The configured settings location changed before the move completed."
        }
    }

    private static func encodedArgument(
        for definition: ActionDefinition,
        inputs: [String],
        context: ActionInputContext,
        environment: Environment
    ) -> String {
        do {
            if definition.requiresParameters {
                return try JSONOutput.string(
                    for: ParameterStepRequest(
                        action: definition.action,
                        inputs: inputs,
                        inputContext: context
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
                    execution: environment.executionOptions
                ),
                prettyPrinted: false
            )
        } catch {
            return ""
        }
    }

    private static func requestVariables(
        for definition: ActionDefinition,
        selection: InputSelection,
        context: ActionInputContext
    ) -> [String: String] {
        guard definition.requiresParameters else {
            return [
                requestKindVariable: WorkflowRequestKind.operation.rawValue
            ]
        }

        let request = ParameterStepRequest(
            action: definition.action,
            inputs: selection.inputs,
            inputContext: context,
            mediaKinds: selection.mediaKinds,
            itemKinds: selection.itemKinds,
            ambiguousKinds: selection.ambiguousKinds
        )
        let state: MenuState
        switch definition.action {
        case .crop:
            state = .crop(request)
        case .downscale, .convert, .cropPDF:
            state = MenuState(mode: .actions, parameterRequest: request)
        case .optimise, .aggressiveOptimise, .uncropPDF, .stripMetadata:
            preconditionFailure("Immediate actions do not have parameter state")
        }

        return [
            requestKindVariable: WorkflowRequestKind.parameterStep.rawValue,
            menuStateVariable: (try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            )) ?? "",
            inputJSONVariable: (try? JSONOutput.string(
                for: MenuInput(
                    paths: selection.inputs,
                    mediaKinds: selection.mediaKinds,
                    itemKinds: selection.itemKinds,
                    ambiguousKinds: selection.ambiguousKinds
                ),
                prettyPrinted: false
            )) ?? "",
            inputContextVariable: context.rawValue
        ]
    }

    private static func inputVariables(
        for selection: InputSelection,
        context: ActionInputContext
    ) -> [String: String]? {
        guard let json = try? JSONOutput.string(
            for: MenuInput(
                paths: selection.inputs,
                mediaKinds: selection.mediaKinds,
                itemKinds: selection.itemKinds,
                ambiguousKinds: selection.ambiguousKinds
            ),
            prettyPrinted: false
        ) else {
            return nil
        }
        return [
            inputJSONVariable: json,
            inputContextVariable: context.rawValue,
            menuStateVariable: (try? JSONOutput.string(
                for: MenuState.actions,
                prettyPrinted: false
            )) ?? ""
        ]
    }

    private static func actionSubtitle(
        definition: ActionDefinition,
        selection: InputSelection,
        context: ActionInputContext
    ) -> String {
        guard !selection.ambiguousKinds.isEmpty else {
            return "\(context.subtitlePrefix): \(definition.subtitle)"
        }

        let requirement: String?
        switch definition.action {
        case .crop:
            requirement = "Requires image, video, or PDF content"
        case .downscale:
            requirement = "Requires image, video, or audio content"
        case .convert:
            requirement = "Requires image content"
        case .cropPDF, .uncropPDF:
            requirement = "Requires PDF content"
        case .stripMetadata:
            requirement = "Requires image or video content"
        case .optimise, .aggressiveOptimise:
            requirement = nil
        }

        return [
            "\(context.subtitlePrefix): \(definition.subtitle)",
            requirement
        ].compactMap(\.self).joined(separator: " - ")
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
