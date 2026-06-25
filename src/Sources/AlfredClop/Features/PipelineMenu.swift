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

        let state = MenuState.pipeline(request)
        if let action = decodedState.pipelineAction {
            switch action.kind {
            case .nameInline:
                guard let add = action.add else {
                    return error(
                        title: "Unable to save pipeline",
                        subtitle: "The pipeline save state is invalid."
                    )
                }
                return saveInlinePipelineResponse(
                    add,
                    pipelines: pipelines,
                    request: request,
                    state: decodedState,
                    query: query
                )
            case .add:
                guard let add = action.add else {
                    return error(
                        title: "Unable to save pipeline",
                        subtitle: "The pipeline save state is invalid."
                    )
                }
                do {
                    try provider.addPipeline(add)
                } catch let caughtError {
                    return error(
                        title: "Unable to save pipeline",
                        subtitle: caughtError.localizedDescription
                    )
                }
                return pipelineList(
                    (try? provider.listPipelines()) ?? pipelines,
                    request: request,
                    state: state,
                    query: "",
                    category: defaultCategory(for: request),
                    environment: environment,
                    showGuideWhenEmpty: true
                )
            case .confirmDelete:
                guard let pipeline = action.pipeline else {
                    return error(
                        title: "Unable to delete pipeline",
                        subtitle: "The pipeline delete state is invalid."
                    )
                }
                return deleteConfirmation(pipeline, request: request)
            case .delete:
                guard let pipeline = action.pipeline else {
                    return error(
                        title: "Unable to delete pipeline",
                        subtitle: "The pipeline delete state is invalid."
                    )
                }
                do {
                    try provider.deletePipeline(named: pipeline.name)
                } catch let caughtError {
                    return error(
                        title: "Unable to delete pipeline",
                        subtitle: caughtError.localizedDescription
                    )
                }
                return pipelineList(
                    (try? provider.listPipelines()) ?? pipelines,
                    request: request,
                    state: state,
                    query: "",
                    category: defaultCategory(for: request),
                    environment: environment,
                    showGuideWhenEmpty: true
                )
            }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let route = categoryRoute(
            from: trimmed,
            request: request,
            pipelines: pipelines
        ) {
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
                items: branchingItems(for: request, pipelines: pipelines),
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
        let guidanceItem = inlineGuidanceItem(query: query, request: request)
        let inlineItem = inlinePipelineItem(
            query: query,
            request: request,
            environment: environment
        )

        guard !visible.isEmpty else {
            let items = [guideItem(for: request, category: category, emptySavedList: pipelines.isEmpty)]
            if let guidanceItem {
                return response(
                    items: [guidanceItem],
                    request: request,
                    state: state
                )
            }
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

        let matches = visible.enumerated().compactMap { index, pipeline in
            PipelineSearch.match(
                pipeline,
                query: query,
                visibleText: PipelineSearch.visibleText(
                    for: pipeline,
                    typeDescription: acceptedTypeDescription(for: pipeline)
                )
            ).map { (index: index, result: $0) }
        }.sorted { lhs, rhs in
            if (lhs.result.matchedStep == nil) != (rhs.result.matchedStep == nil) {
                return lhs.result.matchedStep == nil
            }
            if lhs.result.score == rhs.result.score {
                return lhs.index < rhs.index
            }
            return lhs.result.score > rhs.result.score
        }
        var resultItems = [ScriptFilterItem]()
        if let guidanceItem {
            resultItems.append(guidanceItem)
        } else if let inlineItem {
            resultItems.append(inlineItem)
        }
        resultItems.append(contentsOf: matches.map {
            pipelineItem(
                visible[$0.index],
                request: request,
                environment: environment,
                matchedStep: $0.result.matchedStep
            )
        })
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
        environment: Environment,
        matchedStep: String? = nil
    ) -> ScriptFilterItem {
        let operation = OperationRequest(
            inputs: request.inputs,
            action: .pipeline(PipelineRunRequest(pipeline: pipeline.name)),
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
                matchedStep.map { "Step: \($0)" },
                "⌃↩ Delete Pipeline",
                "⌘L Details"
            ].compactMap(\.self).joined(separator: " · "),
            arg: (try? JSONOutput.string(for: operation, prettyPrinted: false)) ?? "",
            valid: true,
            autocomplete: pipeline.name,
            match: "\(pipeline.name) \(pipeline.fileType?.rawValue ?? "all") \(pipeline.rawText)",
            icon: WorkflowIcon.preset,
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            mods: ScriptFilterMods(control: pipelineDeleteModifier(
                pipeline,
                request: request
            )),
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
        guard let inline = InlinePipelineParser.parse(steps),
              looksLikeInlinePipeline(inline.steps) else {
            return nil
        }
        let operation = OperationRequest(
            inputs: request.inputs,
            action: .pipeline(PipelineRunRequest(
                pipeline: inline.steps,
                isInline: true,
                optimizeFirst: inline.optimizeFirst,
                hideResult: inline.hideResult
            )),
            execution: pipelineExecutionOptions(environment: environment)
        )
        return ScriptFilterItem(
            uid: "pipeline.inline.\(steps)",
            title: "Run inline pipeline",
            subtitle: ([
                inputDescription(for: request),
                inlineSettingsDescription(for: inline),
                "⌃↩ Save Pipeline",
                "⌘L Syntax"
            ] as [String]).joined(separator: " · "),
            arg: (try? JSONOutput.string(for: operation, prettyPrinted: false)) ?? "",
            valid: true,
            autocomplete: steps,
            match: "\(steps) inline pipeline steps",
            icon: WorkflowIcon.inlinePipeline,
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            mods: ScriptFilterMods(control: inlineSaveModifier(
                inline,
                request: request
            )),
            text: ScriptFilterText(largetype: inlinePipelineDetails(
                inline: inline,
                request: request
            ))
        )
    }

    private static func inlineGuidanceItem(
        query: String,
        request: ParameterStepRequest
    ) -> ScriptFilterItem? {
        guard let issue = PipelineSyntax.guidanceIssue(for: query),
              PipelineSyntax.looksLikePipelineAttempt(query) else {
            return nil
        }
        return ScriptFilterItem(
            uid: "pipeline.inline.guidance.\(query)",
            title: issue.title,
            subtitle: "\(inputDescription(for: request)) · \(issue.subtitle) · ⌘L Syntax",
            arg: "",
            valid: false,
            autocomplete: query,
            match: "\(query) pipeline syntax help",
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(largetype: issue.detail)
        )
    }

    private static func categoryRows(
        for request: ParameterStepRequest,
        pipelines: [SavedPipeline]
    ) -> [ScriptFilterItem] {
        categories(for: request, pipelines: pipelines).map { category in
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
            itemKinds: request.itemKinds,
            pixelDimensions: request.pixelDimensions
        )
        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func saveInlinePipelineResponse(
        _ base: PipelineAddRequest,
        pipelines: [SavedPipeline],
        request: ParameterStepRequest,
        state: MenuState,
        query: String
    ) -> ScriptFilterResponse {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return response(
                items: [
                    ScriptFilterItem(
                        title: "Name this pipeline",
                        subtitle: [
                            pipelineAddSummary(base),
                            "Type a name",
                            "⌘L Details"
                        ].joined(separator: " · "),
                        arg: "",
                        valid: false,
                        icon: WorkflowIcon.guide,
                        text: ScriptFilterText(largetype: pipelineAddDetails(base))
                    )
                ],
                request: request,
                state: state
            )
        }

        var add = base
        add.name = name
        let exists = pipelines.contains {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        var replace = add
        replace.replace = true
        let addState = MenuState.pipeline(
            request,
            action: PipelineMenuAction(kind: .add, add: add)
        )
        let replaceState = MenuState.pipeline(
            request,
            action: PipelineMenuAction(kind: .add, add: replace)
        )
        let addJSON = encoded(addState)
        let replaceJSON = encoded(replaceState)
        let title = exists
            ? "Pipeline \(name) already exists"
            : "Save Pipeline \(name)"
        let subtitle = ([
            pipelineAddSummary(add),
            exists ? "⌘↩ Replace" : nil,
            "⌘L Details"
        ] as [String?]).compactMap(\.self).joined(separator: " · ")

        return response(
            items: [
                ScriptFilterItem(
                    title: title,
                    subtitle: subtitle,
                    arg: exists ? "" : addJSON,
                    valid: !exists,
                    icon: exists ? WorkflowIcon.guide : WorkflowIcon.inlinePipeline,
                    variables: exists ? nil : transitionVariables(
                        stateJSON: addJSON,
                        request: request
                    ),
                    mods: ScriptFilterMods(command: ScriptFilterModifier(
                        arg: replaceJSON,
                        subtitle: "Replace Pipeline",
                        valid: true,
                        variables: transitionVariables(
                            stateJSON: replaceJSON,
                            request: request
                        )
                    )),
                    text: ScriptFilterText(largetype: pipelineAddDetails(add))
                )
            ],
            request: request,
            state: state
        )
    }

    private static func deleteConfirmation(
        _ pipeline: SavedPipeline,
        request: ParameterStepRequest
    ) -> ScriptFilterResponse {
        let deleteState = MenuState.pipeline(
            request,
            action: PipelineMenuAction(kind: .delete, pipeline: pipeline)
        )
        let deleteJSON = encoded(deleteState)
        let cancelState = MenuState.pipeline(request)
        let cancelJSON = encoded(cancelState)
        return response(
            items: [
                ScriptFilterItem(
                    title: "Delete Pipeline \(pipeline.name)?",
                    subtitle: "Return confirms · Cannot be undone",
                    arg: deleteJSON,
                    valid: true,
                    icon: WorkflowIcon.destructive,
                    variables: transitionVariables(
                        stateJSON: deleteJSON,
                        request: request
                    ),
                    text: ScriptFilterText(
                        largetype: largeTypeDetails(
                            for: pipeline,
                            request: request
                        )
                    )
                ),
                ScriptFilterItem(
                    title: "Cancel",
                    subtitle: "Return keeps pipeline",
                    arg: cancelJSON,
                    valid: true,
                    variables: transitionVariables(
                        stateJSON: cancelJSON,
                        request: request
                    )
                )
            ],
            request: request,
            state: deleteState
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
        for request: ParameterStepRequest,
        pipelines: [SavedPipeline]
    ) -> [PipelineCategory] {
        if request.ambiguousKinds?.isEmpty == false {
            return PipelineCategory.allCases
        }
        let known = Set(request.mediaKinds ?? [])
        let pipelineMediaKinds = Set(pipelines.compactMap { $0.fileType?.mediaKind })
        let mediaCategories = PipelineCategory.mediaCases.filter { category in
            guard let fileType = category.fileType else { return false }
            return known.contains(fileType.mediaKind)
                && pipelineMediaKinds.contains(fileType.mediaKind)
        }
        let hasKnownMediaWithoutSpecificPipeline = known.contains {
            !pipelineMediaKinds.contains($0)
        }
        let hasAllFilePipelines = pipelines.contains { $0.fileType == nil }
        return hasKnownMediaWithoutSpecificPipeline && hasAllFilePipelines
            ? mediaCategories + [.allFile]
            : mediaCategories
    }

    private static func categoryRoute(
        from query: String,
        request: ParameterStepRequest,
        pipelines: [SavedPipeline]
    ) -> (category: PipelineCategory, query: String)? {
        let normalized = query.lowercased()
        for category in categories(for: request, pipelines: pipelines) {
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
        for request: ParameterStepRequest,
        pipelines: [SavedPipeline]
    ) -> [ScriptFilterItem] {
        [guideItem(for: request)] + categoryRows(
            for: request,
            pipelines: pipelines
        )
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
            icon: WorkflowIcon.guide,
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
        if let inputs = ScriptFilterAffordance.inputLargeType(
            request.inputs,
            pixelDimensions: request.pixelDimensions
        ) {
            lines += ["", "Inputs", inputs]
        }
        return lines.joined(separator: "\n")
    }

    private static func inlinePipelineDetails(
        inline: InlinePipeline,
        request: ParameterStepRequest
    ) -> String {
        var lines = [
            "Run inline pipeline",
            "",
            inline.optimizeFirst
                ? "Optimizes first"
                : "Steps only",
            inline.hideResult
                ? "Hides Clop result"
                : "Uses workflow Clop UI setting",
            "",
            "Steps",
            inline.steps,
            "",
            "Clop validates the pipeline syntax.",
            "",
            "Options",
            "opt: optimize before the written steps",
            "hide: hide Clop's floating result UI for this run"
        ]
        if let inputs = ScriptFilterAffordance.inputLargeType(
            request.inputs,
            pixelDimensions: request.pixelDimensions
        ) {
            lines += ["", "Inputs", inputs]
        }
        lines += ["", inlinePipelineReference(for: request)]
        return lines.joined(separator: "\n")
    }

    private static func inlinePipelineReference(
        for request: ParameterStepRequest
    ) -> String {
        var lines = [
            "Search saved pipelines by name, or type inline Clop pipeline steps.",
            "",
            PipelineSyntax.syntaxReference()
        ]
        if let inputs = ScriptFilterAffordance.inputLargeType(
            request.inputs,
            pixelDimensions: request.pixelDimensions
        ) {
            lines += ["", "Inputs", inputs]
        }
        return lines.joined(separator: "\n")
    }

    private static func looksLikeInlinePipeline(_ value: String) -> Bool {
        PipelineSyntax.looksLikeInlinePipeline(value)
    }

    private static func settingsDescription(
        for pipeline: SavedPipeline
    ) -> String {
        var parts = [String]()
        parts.append(pipeline.skipOptimisation ? "Steps only" : "Optimizes first")
        if pipeline.hideResult {
            parts.append("Hides Clop result")
        }
        return parts.joined(separator: " · ")
    }

    private static func inlineSettingsDescription(
        for inline: InlinePipeline
    ) -> String {
        [
            inline.optimizeFirst ? "Optimizes First" : "Steps Only",
            inline.hideResult ? "Hide Result" : nil
        ].compactMap(\.self).joined(separator: " · ")
    }

    private static func inlineSaveModifier(
        _ inline: InlinePipeline,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let add = PipelineAddRequest(
            name: "",
            steps: inline.steps,
            fileType: inferredPipelineFileType(for: request),
            optimizeFirst: inline.optimizeFirst,
            hideResult: inline.hideResult
        )
        let state = MenuState.pipeline(
            request,
            action: PipelineMenuAction(kind: .nameInline, add: add)
        )
        let stateJSON = encoded(state)
        return ScriptFilterModifier(
            arg: "",
            subtitle: "Save Pipeline",
            valid: true,
            variables: queryTransitionVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
    }

    private static func pipelineDeleteModifier(
        _ pipeline: SavedPipeline,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let state = MenuState.pipeline(
            request,
            action: PipelineMenuAction(kind: .confirmDelete, pipeline: pipeline)
        )
        let stateJSON = encoded(state)
        return ScriptFilterModifier(
            arg: stateJSON,
            subtitle: "Delete Pipeline \(pipeline.name)",
            valid: true,
            variables: transitionVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
    }

    private static func inferredPipelineFileType(
        for request: ParameterStepRequest
    ) -> PipelineFileType? {
        guard request.ambiguousKinds?.isEmpty != false,
              let kind = homogeneousKind(for: request) else {
            return nil
        }
        switch kind {
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case .pdf:
            return .pdf
        case .folder, .unknown:
            return nil
        }
    }

    private static func pipelineAddSummary(
        _ request: PipelineAddRequest
    ) -> String {
        [
            request.fileType?.title ?? "All file types",
            request.optimizeFirst ? "Optimizes First" : "Steps Only",
            request.hideResult ? "Hide Result" : nil
        ].compactMap(\.self).joined(separator: " · ")
    }

    private static func pipelineAddDetails(
        _ request: PipelineAddRequest
    ) -> String {
        [
            request.name.isEmpty
                ? "Save inline pipeline"
                : "Save Pipeline \(request.name)",
            "",
            request.fileType.map { "\($0.title) pipeline" }
                ?? "All-file pipeline",
            pipelineAddSummary(request),
            "",
            "Steps",
            request.steps,
            "",
            "Options",
            "opt: optimize before the written steps",
            "hide: save this Clop pipeline as hidden-result; this overrides the workflow Floating Result setting"
        ].joined(separator: "\n")
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

    private static func transitionVariables(
        stateJSON: String,
        request: ParameterStepRequest
    ) -> [String: String] {
        var variables = preservedVariables(
            for: request,
            stateJSON: stateJSON
        )
        variables[ActionMenu.requestKindVariable] =
            WorkflowRequestKind.parameterStep.rawValue
        return variables
    }

    private static func queryTransitionVariables(
        stateJSON: String,
        request: ParameterStepRequest
    ) -> [String: String] {
        var variables = preservedVariables(
            for: request,
            stateJSON: stateJSON
        )
        variables[ActionMenu.requestKindVariable] =
            WorkflowRequestKind.parameterStepQuery.rawValue
        return variables
    }

    private static func menuInputJSON(for request: ParameterStepRequest) -> String {
        (try? JSONOutput.string(
            for: MenuInput(
                paths: request.inputs,
                mediaKinds: request.mediaKinds,
                itemKinds: request.itemKinds,
                pixelDimensions: request.pixelDimensions,
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

}

private struct InlinePipeline: Equatable {
    var steps: String
    var optimizeFirst: Bool
    var hideResult: Bool
}

private enum InlinePipelineParser {
    static func parse(_ value: String) -> InlinePipeline? {
        guard let split = PipelineSyntax.splitOptions(from: value),
              !split.steps.isEmpty else {
            return nil
        }

        var optimizeFirst = false
        var hideResult = false
        for rawOption in split.options.split(whereSeparator: \.isWhitespace) {
            switch rawOption.lowercased() {
            case "opt":
                optimizeFirst = true
            case "hide":
                hideResult = true
            default:
                return nil
            }
        }

        return InlinePipeline(
            steps: PipelineSyntax.normalizedSteps(split.steps),
            optimizeFirst: optimizeFirst,
            hideResult: hideResult
        )
    }
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
