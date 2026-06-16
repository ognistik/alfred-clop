import Foundation

enum OptimizeParameterMenu {
    static func response(
        stateJSON: String,
        query: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default
    ) -> ScriptFilterResponse {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ),
        state.mode == .optimise,
        let request = state.parameterRequest,
        request.step == "parameters",
        request.action == .optimise,
        !request.inputs.isEmpty else {
            return error(
                title: "Unable to open Optimize",
                subtitle: "The controls menu state is invalid or incomplete."
            )
        }

        return menuResponse(
            request: request,
            stateJSON: stateJSON,
            query: query,
            environment: environment,
            fileManager: fileManager
        )
    }

    private static func menuResponse(
        request: ParameterStepRequest,
        stateJSON: String,
        query: String,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let affordance = ScriptFilterAffordance.processingInputs(
            request.inputs,
            itemKinds: request.itemKinds
        )

        if isControlsQuery(trimmedQuery) {
            return ScriptFilterResponse(
                items: [
                    affordance.apply(to: controlReferenceItem(
                        for: request,
                        query: trimmedQuery
                    ))
                ],
                variables: preservedVariables(for: request, stateJSON: stateJSON),
                skipKnowledge: true
            )
        }

        var items = [ScriptFilterItem]()
        if let item = defaultItem(
            for: request,
            stateJSON: stateJSON,
            environment: environment,
            fileManager: fileManager
        ) {
            items.append(item)
        } else {
            items.append(ScriptFilterItem(
                title: "Unable to prepare Optimize",
                subtitle: "The operation request could not be encoded.",
                arg: "",
                valid: false
            ))
        }

        if shouldShowMediaBranches(for: request) {
            items.append(contentsOf: mediaBranches(
                for: request,
                stateJSON: stateJSON
            ))
        }

        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func defaultItem(
        for request: ParameterStepRequest,
        stateJSON: String,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem? {
        guard let arg = operationArgument(
            for: request,
            aggressive: environment.aggressiveByDefault,
            preserveOriginal: nil,
            environment: environment,
            fileManager: fileManager
        ) else {
            return nil
        }

        return ScriptFilterItem(
            uid: "optimise.defaults",
            title: defaultTitle(for: request),
            subtitle: [
                inputDescription(for: request),
                "Clop Defaults",
                "⏎ Run • ⇥ Controls • ⌃⏎ Custom Presets"
            ].joined(separator: " · "),
            arg: arg,
            valid: true,
            autocomplete: controlsPrefix(for: request),
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue,
                ActionMenu.inputJSONVariable: menuInputJSON(for: request),
                ActionMenu.inputContextVariable: request.inputContext.rawValue,
                ActionMenu.menuStateVariable: stateJSON
            ],
            mods: defaultModifiers(
                for: request,
                environment: environment,
                fileManager: fileManager
            )
        )
    }

    private static func defaultModifiers(
        for request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterMods {
        let preserve = environment.preserveOriginal
        let invertedPreserve = !preserve
        let preserveText = preserve ? "Replace Originals" : "Output Template"

        return ScriptFilterMods(
            command: operationModifier(
                for: request,
                aggressive: true,
                preserveOriginal: preserve,
                subtitle: "Aggressive",
                environment: environment,
                fileManager: fileManager
            ),
            option: operationModifier(
                for: request,
                aggressive: false,
                preserveOriginal: preserve,
                subtitle: "Standard",
                environment: environment,
                fileManager: fileManager
            ),
            shift: operationModifier(
                for: request,
                aggressive: environment.aggressiveByDefault,
                preserveOriginal: invertedPreserve,
                subtitle: preserveText,
                environment: environment,
                fileManager: fileManager
            ),
            commandShift: operationModifier(
                for: request,
                aggressive: true,
                preserveOriginal: invertedPreserve,
                subtitle: "Aggressive · \(preserveText)",
                environment: environment,
                fileManager: fileManager
            ),
            optionShift: operationModifier(
                for: request,
                aggressive: false,
                preserveOriginal: invertedPreserve,
                subtitle: "Standard · \(preserveText)",
                environment: environment,
                fileManager: fileManager
            )
        )
    }

    private static func operationModifier(
        for request: ParameterStepRequest,
        aggressive: Bool,
        preserveOriginal: Bool,
        subtitle: String,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterModifier? {
        guard let arg = operationArgument(
            for: request,
            aggressive: aggressive,
            preserveOriginal: preserveOriginal,
            environment: environment,
            fileManager: fileManager
        ) else {
            return nil
        }
        return ScriptFilterModifier(
            arg: arg,
            subtitle: "\(inputDescription(for: request)) · \(subtitle)",
            valid: true,
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ]
        )
    }

    private static func operationArgument(
        for request: ParameterStepRequest,
        aggressive: Bool,
        preserveOriginal: Bool?,
        environment: Environment,
        fileManager: FileManager
    ) -> String? {
        guard let execution = try? environment.resolvedExecutionOptions(
            fileManager: fileManager,
            preserveOriginal: preserveOriginal
        ) else {
            return nil
        }
        return try? JSONOutput.string(
            for: OperationRequest(
                inputs: request.inputs,
                action: .optimise(aggressive: aggressive),
                execution: execution
            ),
            prettyPrinted: false
        )
    }

    private static func mediaBranches(
        for request: ParameterStepRequest,
        stateJSON: String
    ) -> [ScriptFilterItem] {
        mediaBranchKinds(for: request).map { kind in
            ScriptFilterItem(
                uid: "optimise.controls.\(kind.rawValue)",
                title: "\(kind.displayName) Optimize Controls",
                subtitle: "\(inputDescription(for: request)) · Applies only to \(kind.pluralDisplayName.lowercased())",
                arg: "",
                valid: false,
                autocomplete: "\(kind.rawValue) controls: ",
                variables: preservedVariables(for: request, stateJSON: stateJSON)
            )
        }
    }

    private static func mediaBranchKinds(
        for request: ParameterStepRequest
    ) -> [MediaKind] {
        let known = Set(request.mediaKinds ?? [])
        let ordered: [MediaKind] = [.image, .video, .pdf, .audio]
        if !known.isEmpty {
            return ordered.filter(known.contains)
        }
        return ordered
    }

    private static func shouldShowMediaBranches(
        for request: ParameterStepRequest
    ) -> Bool {
        if !(request.ambiguousKinds ?? []).isEmpty {
            return true
        }
        return Set(request.mediaKinds ?? []).count > 1
    }

    private static func controlReferenceItem(
        for request: ParameterStepRequest,
        query: String
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Type optimization controls",
            subtitle: controlExamples(for: request, query: query),
            arg: "",
            valid: false,
            autocomplete: normalizedControlsQuery(for: request),
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.parameterStepQuery.rawValue
            ],
            text: ScriptFilterText(largetype: controlReference(
                for: request,
                query: query
            ))
        )
    }

    private static func isControlsQuery(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        return lowercased.hasPrefix("controls:")
            || lowercased.hasPrefix("image controls:")
            || lowercased.hasPrefix("video controls:")
            || lowercased.hasPrefix("pdf controls:")
            || lowercased.hasPrefix("audio controls:")
    }

    private static func normalizedControlsQuery(
        for request: ParameterStepRequest
    ) -> String {
        controlsPrefix(for: request)
    }

    private static func controlsPrefix(
        for request: ParameterStepRequest
    ) -> String {
        guard shouldShowMediaBranches(for: request) else {
            return "controls: "
        }
        return "controls: "
    }

    private static func defaultTitle(for request: ParameterStepRequest) -> String {
        switch homogeneousKind(for: request) {
        case .image:
            return "Optimize Images with Defaults"
        case .video:
            return "Optimize Videos with Defaults"
        case .pdf:
            return "Optimize PDFs with Defaults"
        case .audio:
            return "Optimize Audio with Defaults"
        case .folder, .unknown, nil:
            return "Optimize All with Defaults"
        }
    }

    private static func homogeneousKind(
        for request: ParameterStepRequest
    ) -> MediaKind? {
        let kinds = Set(request.mediaKinds ?? [])
        return kinds.count == 1 ? kinds.first : nil
    }

    private static func controlExamples(
        for request: ParameterStepRequest,
        query: String
    ) -> String {
        switch controlsKind(for: request, query: query) {
        case .image:
            return "Examples: 70, c70, adaptive"
        case .video:
            return "Examples: c70, auto, software, mute, 2x"
        case .pdf:
            return "Examples: adaptive, dpi 150, 150"
        case .audio:
            return "Examples: c70, b128, bitrate 128"
        case .folder, .unknown, nil:
            return "Choose image, video, PDF, or audio controls."
        }
    }

    private static func controlReference(
        for request: ParameterStepRequest,
        query: String
    ) -> String {
        switch controlsKind(for: request, query: query) {
        case .image:
            return "Image Optimize controls\n\n70 or c70: compression\nadaptive: let Clop choose"
        case .video:
            return "Video Optimize controls\n\nc70: compression\nauto: automatic compression\nhardware, software, lossless, adaptive: encoder\nmute: remove audio\n2x: playback speed"
        case .pdf:
            return "PDF Optimize controls\n\nadaptive\n300, 250, 200, 150, 100, 72, 48"
        case .audio:
            return "Audio Optimize controls\n\nc70: compression\nb128: bitrate in kbps"
        case .folder, .unknown, nil:
            return "Optimize controls\n\nUse image controls:, video controls:, pdf controls:, or audio controls:."
        }
    }

    private static func controlsKind(
        for request: ParameterStepRequest,
        query: String
    ) -> MediaKind? {
        let lowercased = query.lowercased()
        if lowercased.hasPrefix("image controls:") {
            return .image
        }
        if lowercased.hasPrefix("video controls:") {
            return .video
        }
        if lowercased.hasPrefix("pdf controls:") {
            return .pdf
        }
        if lowercased.hasPrefix("audio controls:") {
            return .audio
        }
        return homogeneousKind(for: request)
    }

    private static func inputDescription(for request: ParameterStepRequest) -> String {
        request.inputContext.inputDescription(
            inputs: request.inputs,
            itemKinds: request.itemKinds,
            ambiguousKinds: request.ambiguousKinds ?? [],
            processableItemCount: request.processableItemCount
        )
    }

    private static func preservedVariables(
        for request: ParameterStepRequest,
        stateJSON: String
    ) -> [String: String] {
        [
            ActionMenu.inputJSONVariable: menuInputJSON(for: request),
            ActionMenu.inputContextVariable: request.inputContext.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func menuInputJSON(for request: ParameterStepRequest) -> String {
        (try? JSONOutput.string(
            for: MenuInput(
                paths: request.inputs,
                mediaKinds: request.mediaKinds,
                itemKinds: request.itemKinds,
                ambiguousKinds: request.ambiguousKinds,
                processableItemCount: request.processableItemCount
            ),
            prettyPrinted: false
        )) ?? ""
    }

    private static func error(
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

private extension MediaKind {
    var displayName: String {
        switch self {
        case .image:
            return "Image"
        case .video:
            return "Video"
        case .pdf:
            return "PDF"
        case .audio:
            return "Audio"
        case .folder:
            return "Folder"
        case .unknown:
            return "Unknown"
        }
    }

    var pluralDisplayName: String {
        switch self {
        case .image:
            return "Images"
        case .video:
            return "Videos"
        case .pdf:
            return "PDFs"
        case .audio:
            return "Audio"
        case .folder:
            return "Folders"
        case .unknown:
            return "Items"
        }
    }
}
