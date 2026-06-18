import Foundation

enum PipelineMenu {
    static func response(
        stateJSON: String,
        query: String,
        environment: Environment = Environment(),
        provider: any ClopPipelineProviding = ClopPipelineProvider()
    ) -> ScriptFilterResponse {
        guard let decodedState = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ), let request = decodedState.parameterRequest else {
            return error(
                title: "Unable to open Pipeline",
                subtitle: "The menu state is invalid or incomplete."
            )
        }

        let pipelines: [SavedPipeline]
        do {
            pipelines = try provider.listPipelines()
        } catch let caughtError {
            return error(
                title: "Unable to read pipelines",
                subtitle: caughtError.localizedDescription
            )
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = MenuState.pipeline(request)
        if let route = categoryRoute(from: trimmed, request: request) {
            return pipelineList(
                pipelines,
                request: request,
                state: state,
                query: route.query,
                category: route.category,
                environment: environment,
                showGuideWhenEmpty: false
            )
        }

        if trimmed.isEmpty, shouldShowCategoryRows(for: request) {
            return response(
                items: branchingItems(for: request),
                request: request,
                state: state
            )
        }

        return pipelineList(
            pipelines,
            request: request,
            state: state,
            query: trimmed,
            category: defaultCategory(for: request),
            environment: environment,
            showGuideWhenEmpty: true
        )
    }

    private static func pipelineList(
        _ pipelines: [SavedPipeline],
        request: ParameterStepRequest,
        state: MenuState,
        query: String,
        category: PipelineCategory?,
        environment: Environment,
        showGuideWhenEmpty: Bool
    ) -> ScriptFilterResponse {
        let visible = pipelines
            .filter { isVisible($0, category: category, request: request) }
            .sorted(by: pipelineDisplayOrder)
        let inlineItem = inlinePipelineItem(
            query: query,
            request: request,
            environment: environment
        )

        guard !visible.isEmpty else {
            let items = [guideItem(for: request, category: category, emptySavedList: pipelines.isEmpty)]
            if let inlineItem {
                return response(
                    items: [inlineItem],
                    request: request,
                    state: state
                )
            }
            return response(
                items: items,
                request: request,
                state: state
            )
        }

        let items = visible.map {
            pipelineItem($0, request: request, environment: environment)
        }
        guard !query.isEmpty else {
            if !showGuideWhenEmpty {
                return response(items: items, request: request, state: state)
            }
            return response(
                items: [guideItem(for: request, category: category)] + items,
                request: request,
                state: state
            )
        }

        let search = FuzzySearch<ScriptFilterItem>(
            query: query,
            targetText: {
                [$0.title, $0.match].compactMap(\.self)
                    .joined(separator: " ")
            }
        )
        let matches = search.sorted(items)
        var resultItems = [ScriptFilterItem]()
        if let inlineItem {
            resultItems.append(inlineItem)
        }
        resultItems.append(contentsOf: matches.map { items[$0.targetIndex] })
        guard !resultItems.isEmpty else {
            return response(
                items: [guideItem(for: request, category: category, noMatches: true)],
                request: request,
                state: state
            )
        }
        return response(
            items: resultItems,
            request: request,
            state: state
        )
    }

    private static func pipelineItem(
        _ pipeline: SavedPipeline,
        request: ParameterStepRequest,
        environment: Environment
    ) -> ScriptFilterItem {
        let operation = OperationRequest(
            inputs: request.inputs,
            action: .pipeline(PipelineRunRequest(name: pipeline.name)),
            execution: pipelineExecutionOptions(environment: environment)
        )
        return ScriptFilterItem(
            uid: "pipeline.run.\(pipeline.id ?? pipeline.name).\(pipeline.fileType?.rawValue ?? "all")",
            title: pipeline.name,
            subtitle: [
                inputDescription(for: request),
                shouldShowAcceptedType(in: request)
                    ? acceptedTypeDescription(for: pipeline)
                    : nil,
                "⌘L Details"
            ].compactMap(\.self).joined(separator: " · "),
            arg: (try? JSONOutput.string(for: operation, prettyPrinted: false)) ?? "",
            valid: true,
            autocomplete: pipeline.name,
            match: "\(pipeline.name) \(pipeline.fileType?.rawValue ?? "all") \(pipeline.rawText)",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            text: ScriptFilterText(
                largetype: largeTypeDetails(for: pipeline, request: request)
            )
        )
    }

    private static func pipelineExecutionOptions(
        environment: Environment
    ) -> ExecutionOptions {
        var execution = environment.executionOptions
        execution.copyResult = false
        execution.output = .inPlace
        execution.aggressiveProcessing = nil
        return execution
    }

    private static func inlinePipelineItem(
        query: String,
        request: ParameterStepRequest,
        environment: Environment
    ) -> ScriptFilterItem? {
        let steps = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeInlinePipeline(steps) else {
            return nil
        }
        let operation = OperationRequest(
            inputs: request.inputs,
            action: .pipeline(PipelineRunRequest(name: steps)),
            execution: pipelineExecutionOptions(environment: environment)
        )
        return ScriptFilterItem(
            uid: "pipeline.inline.\(steps)",
            title: "Run inline pipeline",
            subtitle: "\(inputDescription(for: request)) · Clop validates steps · ⌘L Syntax",
            arg: (try? JSONOutput.string(for: operation, prettyPrinted: false)) ?? "",
            valid: true,
            autocomplete: steps,
            match: "\(steps) inline pipeline steps",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            text: ScriptFilterText(largetype: inlinePipelineDetails(
                steps: steps,
                request: request
            ))
        )
    }

    private static func categoryRows(
        for request: ParameterStepRequest
    ) -> [ScriptFilterItem] {
        categories(for: request).map { category in
            ScriptFilterItem(
                uid: "pipeline.category.\(category.query)",
                title: category.title,
                subtitle: "\(inputDescription(for: request)) · Filter saved pipelines",
                arg: category.autocomplete,
                valid: true,
                autocomplete: category.autocomplete,
                match: category.matchText,
                variables: [
                    ActionMenu.requestKindVariable:
                        WorkflowRequestKind.parameterStepQuery.rawValue
                ]
            )
        }
    }

    private static func response(
        items: [ScriptFilterItem],
        request: ParameterStepRequest,
        state: MenuState
    ) -> ScriptFilterResponse {
        let stateJSON = encoded(state)
        let affordance = ScriptFilterAffordance.processingInputs(
            request.inputs,
            itemKinds: request.itemKinds
        )
        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func isVisible(
        _ pipeline: SavedPipeline,
        category: PipelineCategory?,
        request: ParameterStepRequest
    ) -> Bool {
        if let category {
            return category.accepts(pipeline)
        }
        if request.ambiguousKinds?.isEmpty == false {
            return true
        }
        let known = Set(request.mediaKinds ?? [])
        guard !known.isEmpty else {
            return true
        }
        return pipeline.fileType == nil
            || pipeline.fileType.map { known.contains($0.mediaKind) } == true
    }

    private static func shouldShowCategoryRows(
        for request: ParameterStepRequest
    ) -> Bool {
        if request.ambiguousKinds?.isEmpty == false {
            return true
        }
        return Set(request.mediaKinds ?? []).count > 1
    }

    private static func shouldShowAcceptedType(
        in request: ParameterStepRequest
    ) -> Bool {
        shouldShowCategoryRows(for: request)
    }

    private static func defaultCategory(
        for request: ParameterStepRequest
    ) -> PipelineCategory? {
        shouldShowCategoryRows(for: request) ? nil : nil
    }

    private static func categories(
        for request: ParameterStepRequest
    ) -> [PipelineCategory] {
        if request.ambiguousKinds?.isEmpty == false {
            return PipelineCategory.allCases
        }
        let known = Set(request.mediaKinds ?? [])
        return PipelineCategory.mediaCases.filter { category in
            guard let fileType = category.fileType else { return false }
            return known.contains(fileType.mediaKind)
        }
    }

    private static func categoryRoute(
        from query: String,
        request: ParameterStepRequest
    ) -> (category: PipelineCategory, query: String)? {
        let normalized = query.lowercased()
        for category in categories(for: request) {
            for alias in category.aliases where normalized == alias
                || normalized.hasPrefix("\(alias) ") {
                let value = normalized == alias
                    ? ""
                    : String(query.dropFirst(alias.count + 1))
                return (category, value)
            }
        }
        return nil
    }

    private static func branchingItems(
        for request: ParameterStepRequest
    ) -> [ScriptFilterItem] {
        [guideItem(for: request)] + categoryRows(for: request)
    }

    private static func guideItem(
        for request: ParameterStepRequest,
        category: PipelineCategory? = nil,
        noMatches: Bool = false,
        emptySavedList: Bool = false
    ) -> ScriptFilterItem {
        let title: String
        let subtitle: String
        if noMatches {
            title = "No matching pipelines"
            subtitle = "Search saved pipelines or use steps like convert(to: webp)"
        } else if emptySavedList {
            title = "Search saved pipelines or type inline steps"
            subtitle = "\(inputDescription(for: request)) · No saved pipelines · ⌘L Syntax"
        } else if category == nil, shouldShowCategoryRows(for: request) {
            title = "Pick a media type, search, or type inline steps"
            subtitle = "\(inputDescription(for: request)) · Compatible pipeline groups · ⌘L Syntax"
        } else {
            title = "Search saved pipelines or type inline steps"
            subtitle = "\(inputDescription(for: request)) · Example: convert(to: webp) · ⌘L Syntax"
        }
        return ScriptFilterItem(
            uid: "pipeline.guide",
            title: title,
            subtitle: subtitle,
            arg: "",
            valid: false,
            text: ScriptFilterText(largetype: inlinePipelineReference(for: request))
        )
    }

    private static func homogeneousKind(
        for request: ParameterStepRequest
    ) -> MediaKind? {
        let kinds = Set(request.mediaKinds ?? [])
        return kinds.count == 1 ? kinds.first : nil
    }

    private static func acceptedTypeDescription(
        for pipeline: SavedPipeline
    ) -> String {
        guard let fileType = pipeline.fileType else {
            return "All-file pipeline"
        }
        return "\(fileType.title) pipeline"
    }

    private static func largeTypeDetails(
        for pipeline: SavedPipeline,
        request: ParameterStepRequest
    ) -> String {
        var lines = [
            pipeline.name,
            "",
            acceptedTypeDescription(for: pipeline),
            settingsDescription(for: pipeline),
            "",
            "Steps",
            pipeline.rawText
        ]
        if let inputs = ScriptFilterAffordance.inputLargeType(request.inputs) {
            lines += ["", "Inputs", inputs]
        }
        return lines.joined(separator: "\n")
    }

    private static func inlinePipelineDetails(
        steps: String,
        request: ParameterStepRequest
    ) -> String {
        var lines = [
            "Run inline pipeline",
            "",
            "Steps",
            steps,
            "",
            "Clop validates the pipeline syntax."
        ]
        if let inputs = ScriptFilterAffordance.inputLargeType(request.inputs) {
            lines += ["", "Inputs", inputs]
        }
        lines += ["", inlinePipelineReference(for: request)]
        return lines.joined(separator: "\n")
    }

    private static func inlinePipelineReference(
        for request: ParameterStepRequest
    ) -> String {
        var lines = [
            "Pipeline syntax",
            "",
            "Search saved pipelines by name, or type inline Clop pipeline steps.",
            "",
            "Examples",
            "crop(width: 1600) -> convert(to: webp)",
            "changeSpeed(factor: 2.0) -> removeAudio",
            "convert(to: gif)",
            "",
            "Type only the steps here. Saved pipeline creation uses:",
            "Name => steps ; options"
        ]
        if let inputs = ScriptFilterAffordance.inputLargeType(request.inputs) {
            lines += ["", "Inputs", inputs]
        }
        return lines.joined(separator: "\n")
    }

    private static func looksLikeInlinePipeline(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed.contains("->") {
            return true
        }
        if trimmed.contains("("), trimmed.contains(")") {
            return true
        }
        return knownPipelineSteps.contains(trimmed.lowercased())
    }

    private static func settingsDescription(
        for pipeline: SavedPipeline
    ) -> String {
        var parts = [String]()
        parts.append(pipeline.skipOptimisation ? "Steps only" : "Includes implicit optimization")
        if pipeline.hideResult {
            parts.append("Hides Clop result")
        }
        return parts.joined(separator: " · ")
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

    private static func pipelineDisplayOrder(
        _ lhs: SavedPipeline,
        _ rhs: SavedPipeline
    ) -> Bool {
        let lhsType = lhs.fileType?.rawValue ?? "all"
        let rhsType = rhs.fileType?.rawValue ?? "all"
        let typeComparison = lhsType.localizedStandardCompare(rhsType)
        if typeComparison != .orderedSame {
            return typeComparison == .orderedAscending
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func encoded(_ state: MenuState) -> String {
        (try? JSONOutput.string(for: state, prettyPrinted: false)) ?? ""
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

    private static let knownPipelineSteps: Set<String> = [
        "optimise",
        "downscale",
        "lowerbitrate",
        "convert",
        "crop",
        "extractpagesasimages",
        "copy",
        "move",
        "rename",
        "delete",
        "if",
        "ifnot",
        "removeaudio",
        "changespeed",
        "runscript",
        "runshortcut",
        "copytoclipboard",
        "copylinkforsending",
        "shelvewith",
        "uploadwith",
        "openwith"
    ]
}

private enum PipelineCategory: CaseIterable {
    case image
    case video
    case audio
    case pdf
    case allFile
    case all

    static var mediaCases: [PipelineCategory] {
        [.image, .video, .audio, .pdf]
    }

    var title: String {
        switch self {
        case .image:
            return "Image Pipelines"
        case .video:
            return "Video Pipelines"
        case .audio:
            return "Audio Pipelines"
        case .pdf:
            return "PDF Pipelines"
        case .allFile:
            return "All-File Pipelines"
        case .all:
            return "All Pipelines"
        }
    }

    var query: String {
        switch self {
        case .image:
            return "image"
        case .video:
            return "video"
        case .audio:
            return "audio"
        case .pdf:
            return "pdf"
        case .allFile:
            return "all-file"
        case .all:
            return "all"
        }
    }

    var autocomplete: String {
        "\(query) "
    }

    var aliases: [String] {
        switch self {
        case .image:
            return ["image", "img"]
        case .video:
            return ["video", "vid"]
        case .audio:
            return ["audio", "aud"]
        case .pdf:
            return ["pdf"]
        case .allFile:
            return ["all-file", "all file", "any"]
        case .all:
            return ["all"]
        }
    }

    var fileType: PipelineFileType? {
        switch self {
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case .pdf:
            return .pdf
        case .allFile, .all:
            return nil
        }
    }

    var matchText: String {
        "\(title) \(aliases.joined(separator: " "))"
    }

    func accepts(_ pipeline: SavedPipeline) -> Bool {
        switch self {
        case .all:
            return true
        case .allFile:
            return pipeline.fileType == nil
        case .image, .video, .audio, .pdf:
            return pipeline.fileType == nil || pipeline.fileType == fileType
        }
    }
}
