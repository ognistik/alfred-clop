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
            action: .convertImage,
            title: "Convert Image",
            subtitle: "Choose an image format",
            aliases: ["convert", "webp", "avif", "heic", "jxl", "jpeg", "png", "format"],
            supportedKinds: [.image],
            requiresParameters: true,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .convertVideo,
            title: "Convert Video",
            subtitle: "Choose a video format or codec",
            aliases: ["convert", "mp4", "gif", "webm", "hevc", "x265", "av1", "codec"],
            supportedKinds: [.video],
            requiresParameters: true,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .convertAudio,
            title: "Convert Audio",
            subtitle: "Choose an audio format",
            aliases: ["convert", "mp3", "aac", "m4a", "opus", "ogg", "flac", "wav", "aiff"],
            supportedKinds: [.audio],
            requiresParameters: true,
            supportsURLs: true,
            supportsFolders: true
        ),
        ActionDefinition(
            action: .cropPDF,
            title: "Crop PDF (Reversible)",
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
    static let publicRequestVariable = "alfred_clop_request"

    static func keywordResponse(
        clipboard: ClipboardReading,
        query: String,
        collector: InputCollector = InputCollector(),
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        guard environment.readClipboardForKeyword else {
            let disabledItem = workflowSettingsItem(
                title: "Clipboard input is disabled",
                subtitle: "Press Return to enable it in Workflow Configuration."
            ).items[0]
            return ScriptFilterResponse(items: [
                disabledItem,
                ConfigurationMenu.actionItem
            ])
        }
        return response(
            clipboard: clipboard,
            query: query,
            collector: collector,
            environment: environment,
            fileManager: fileManager,
            writer: writer
        )
    }

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
                return noSupportedInputResponse(context: .clipboard)
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
            return noSupportedInputResponse(context: .clipboard)
        } catch InputCollectionError.missingPath(let path) {
            return responseWithConfiguration(
                context: .clipboard,
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
        func feedback(title: String, subtitle: String) -> ScriptFilterResponse {
            responseWithConfiguration(
                context: context,
                title: title,
                subtitle: subtitle
            )
        }

        switch error {
        case InputCollectionError.noInputs:
            return noSupportedInputResponse(context: context)
        case InputCollectionError.emptyFinderSelection:
            return feedback(
                title: "No Finder selection",
                subtitle: "Select one or more Finder items and try again."
            )
        case InputCollectionError.finderSelectionUnavailable:
            return feedback(
                title: "Unable to read Finder selection",
                subtitle: "Allow Alfred to control Finder, then try again."
            )
        case InputCollectionError.missingPath(let path):
            return feedback(title: "Input was not found", subtitle: path)
        case InputCollectionError.unsupportedURL(let value):
            return feedback(
                title: "Unsupported URL",
                subtitle: "Only HTTP and HTTPS URLs are accepted: \(value)"
            )
        case InputCollectionError.credentialedURL:
            return feedback(
                title: "URL credentials are not allowed",
                subtitle: "Remove the username or password from the URL."
            )
        case InputCollectionError.emptyFolder,
             InputCollectionError.unsupportedFolder:
            return noSupportedInputResponse(context: context)
        case InputCollectionError.recursionDisabledFolder:
            return ScriptFilterResponse(
                items: [
                    ConfigurationMenu.actionItem,
                    workflowSettingsItem(
                        title: "Supported media is in subfolders",
                        subtitle: "Press Return to open workflow configuration."
                    ).items[0]
                ],
                variables: inputVariables(
                    for: InputSelection(inputs: [], mediaKinds: []),
                    context: context
                )
            )
        case InputCollectionError.unreadableFolder(let path):
            return feedback(title: "Unable to read folder", subtitle: path)
        default:
            return feedback(
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
            return responseWithConfiguration(
                context: context,
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
            return responseWithConfiguration(
                context: context,
                title: "Selected file was not found",
                subtitle: path
            )
        } catch {
            return collectionErrorResponse(error, context: context)
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
            return responseWithConfiguration(
                context: context,
                title: context == .arguments
                    ? "Passed file was not found"
                    : "Selected file was not found",
                subtitle: path
            )
        } catch {
            return collectionErrorResponse(error, context: context)
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
            return noSupportedInputResponse(context: context)
        }

        let validActions = ActionCatalog.validActions(for: selection)
        let filteredActions = ActionMenuSearch.filter(validActions, query: query)
        let configurationItem = configurationItem(query: query)

        guard !filteredActions.isEmpty || configurationItem != nil else {
            return errorItem(
                title: "No matching actions",
                subtitle: "Try another search term."
            )
        }

        return ScriptFilterResponse(
            items: filteredActions.map { definition in
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
                    ),
                    mods: operationModifiers(
                        for: definition,
                        inputs: selection.inputs,
                        context: context,
                        environment: environment,
                        fileManager: fileManager
                    )
                )
            } + [configurationItem].compactMap(\.self),
            variables: inputVariables(
                for: selection,
                context: context
            )
        )
    }

    static func responseWithoutInputs(
        context: ActionInputContext,
        title: String,
        subtitle: String,
        environment: Environment,
        fileManager: FileManager,
        writer: any AtomicDataWriting
    ) -> ScriptFilterResponse {
        responseWithConfiguration(
            context: context,
            title: title,
            subtitle: subtitle
        )
    }

    private static func responseWithConfiguration(
        context: ActionInputContext,
        title: String,
        subtitle: String
    ) -> ScriptFilterResponse {
        return ScriptFilterResponse(
            items: [
                ConfigurationMenu.actionItem,
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

    private static func noSupportedInputResponse(
        context: ActionInputContext
    ) -> ScriptFilterResponse {
        let title: String
        let subtitle: String
        switch context {
        case .clipboard:
            title = "No supported clipboard content"
            subtitle = "Copy a supported file, folder, URL, or image and try again."
        case .selected:
            title = "No supported input"
            subtitle = "Select a supported file, folder, or URL and try again."
        case .arguments:
            title = "No supported input"
            subtitle = "Pass a supported file, folder, or HTTP/HTTPS URL."
        }
        return responseWithConfiguration(
            context: context,
            title: title,
            subtitle: subtitle
        )
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
                action = .optimise(aggressive: environment.aggressiveByDefault)
            case .uncropPDF:
                action = .uncropPDF
            case .stripMetadata:
                action = .stripMetadata
            case .crop, .downscale, .convertImage, .convertVideo,
                 .convertAudio, .cropPDF:
                preconditionFailure("Parameter actions must use ParameterStepRequest")
            }

            var execution = try environment.resolvedExecutionOptions()
            if definition.action == .stripMetadata {
                execution.output = .inPlace
            }
            return try JSONOutput.string(
                for: OperationRequest(
                    inputs: inputs,
                    action: action,
                    execution: execution
                ),
                prettyPrinted: false
            )
        } catch {
            return ""
        }
    }

    private static func configurationItem(query: String) -> ScriptFilterItem? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.isEmpty
            || "configuration settings output template cache cleanup folder"
                .contains(normalized) else {
            return nil
        }
        return ConfigurationMenu.actionItem
    }

    private static func operationModifiers(
        for definition: ActionDefinition,
        inputs: [String],
        context: ActionInputContext,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterMods? {
        guard !definition.requiresParameters else {
            return nil
        }

        let configuredAggressive = environment.aggressiveByDefault
        let configuredPreserve = environment.preserveOriginal
        let template = (try? PresetStore(
            environment: environment,
            fileManager: fileManager
        ).load().outputTemplate)
            ?? SettingsDocument.builtInOutputTemplate

        func modifier(
            aggressive: Bool,
            preserve: Bool,
            subtitle: String
        ) -> ScriptFilterModifier? {
            let action: ActionRequest
            switch definition.action {
            case .optimise:
                action = .optimise(aggressive: aggressive)
            case .uncropPDF:
                action = .uncropPDF
            case .stripMetadata:
                action = .stripMetadata
            default:
                return nil
            }
            guard let arg = try? JSONOutput.string(
                for: OperationRequest(
                    inputs: inputs,
                    action: action,
                    execution: environment.executionOptions(
                        outputTemplate: template,
                        preserveOriginal: preserve
                    )
                ),
                prettyPrinted: false
            ) else {
                return nil
            }
            return ScriptFilterModifier(
                arg: arg,
                subtitle: "\(context.subtitlePrefix): \(subtitle)",
                valid: true,
                variables: [
                    requestKindVariable: WorkflowRequestKind.operation.rawValue
                ]
            )
        }

        let preservationText = configuredPreserve
            ? "replace originals for this run"
            : "preserve originals for this run"
        let invertedPreserve = !configuredPreserve
        let shift = modifier(
            aggressive: configuredAggressive,
            preserve: invertedPreserve,
            subtitle: preservationText
        )

        if definition.action == .stripMetadata {
            return nil
        }
        guard definition.action == .optimise else {
            return ScriptFilterMods(shift: shift)
        }
        let commandText = configuredAggressive
            ? "use standard optimization"
            : "use aggressive optimization"
        return ScriptFilterMods(
            command: modifier(
                aggressive: !configuredAggressive,
                preserve: configuredPreserve,
                subtitle: commandText
            ),
            shift: shift,
            commandShift: modifier(
                aggressive: !configuredAggressive,
                preserve: invertedPreserve,
                subtitle: "\(commandText) and \(preservationText)"
            )
        )
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
        case .downscale, .convertImage, .convertVideo, .convertAudio, .cropPDF:
            state = MenuState(mode: .actions, parameterRequest: request)
        case .optimise, .uncropPDF, .stripMetadata:
            preconditionFailure("Immediate actions do not have parameter state")
        }

        return [
            requestKindVariable: WorkflowRequestKind.parameterStep.rawValue,
            publicRequestVariable: "",
            menuStateVariable: (try? JSONOutput.string(
                for: state,
                prettyPrinted: false
            )) ?? "",
            inputJSONVariable: (try? JSONOutput.string(
                for: MenuInput(
                    paths: selection.inputs,
                    mediaKinds: selection.mediaKinds,
                    itemKinds: selection.itemKinds,
                    ambiguousKinds: selection.ambiguousKinds,
                    processableItemCount: selection.processableItemCount
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
                ambiguousKinds: selection.ambiguousKinds,
                processableItemCount: selection.processableItemCount
            ),
            prettyPrinted: false
        ) else {
            return nil
        }
        return [
            inputJSONVariable: json,
            inputContextVariable: context.rawValue,
            publicRequestVariable: "",
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
            return clearInputSubtitle(
                definition: definition,
                selection: selection,
                context: context
            )
        }

        let requirement: String?
        switch definition.action {
        case .crop:
            requirement = "Image, video, or PDF only"
        case .downscale:
            requirement = "Image, video, or audio only"
        case .convertImage:
            requirement = "Images only"
        case .convertVideo:
            requirement = "Videos only"
        case .convertAudio:
            requirement = "Audio only"
        case .cropPDF, .uncropPDF:
            requirement = "PDF only"
        case .stripMetadata:
            requirement = "Images or videos only"
        case .optimise:
            requirement = nil
        }

        if let requirement {
            return "\(context.subtitlePrefix) · \(requirement)"
        }
        return "\(context.subtitlePrefix): \(definition.subtitle)"
    }

    private static func clearInputSubtitle(
        definition: ActionDefinition,
        selection: InputSelection,
        context: ActionInputContext
    ) -> String {
        let includesFolder = selection.itemKinds.contains(.folder)
        let count = selection.processableItemCount
        let inputDescription: String
        if includesFolder, let count, count > 1 {
            inputDescription = "\(context.subtitlePrefix), folder: \(count) items"
        } else if includesFolder {
            inputDescription = "\(context.subtitlePrefix), folder"
        } else if let count, count > 1 {
            inputDescription = "\(context.subtitlePrefix): \(count) items"
        } else {
            inputDescription = context.subtitlePrefix
        }
        return "\(inputDescription): \(definition.subtitle)"
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

    private static func workflowSettingsItem(
        title: String,
        subtitle: String
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: title,
                subtitle: subtitle,
                arg: "",
                valid: true,
                variables: [
                    requestKindVariable:
                        WorkflowRequestKind.workflowSettings.rawValue
                ]
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
