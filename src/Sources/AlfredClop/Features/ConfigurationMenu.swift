import Foundation

enum ConfigurationMenu {
    static let namespacePrefix = ":"
    static let templatePrefix = ":template "
    static let presetsPrefix = ":presets"
    static let presetsAutocomplete = ":presets "
    static let pipelinesPrefix = ":pipelines"
    static let pipelinesAutocomplete = ":pipelines "

    private enum PresetCategory: String, CaseIterable, Equatable {
        case optimize
        case crop
        case cropPDF
        case downscale
        case convertImage
        case convertVideo
        case convertAudio

        var title: String {
            switch self {
            case .optimize:
                return "Optimize Presets"
            case .crop:
                return "Crop / Resize Presets"
            case .cropPDF:
                return "Crop PDF Presets"
            case .downscale:
                return "Downscale Presets"
            case .convertImage:
                return "Convert Image Presets"
            case .convertVideo:
                return "Convert Video Presets"
            case .convertAudio:
                return "Convert Audio Presets"
            }
        }

        var autocomplete: String {
            "\(presetsPrefix) \(canonicalQuery) "
        }

        var canonicalQuery: String {
            switch self {
            case .optimize:
                return "optimize"
            case .crop:
                return "crop"
            case .cropPDF:
                return "crop pdf"
            case .downscale:
                return "downscale"
            case .convertImage:
                return "convert image"
            case .convertVideo:
                return "convert video"
            case .convertAudio:
                return "convert audio"
            }
        }

        var matchText: String {
            switch self {
            case .optimize:
                return "optimize opt presets"
            case .crop:
                return "crop resize presets"
            case .cropPDF:
                return "crop pdf pdf presets"
            case .downscale:
                return "downscale down presets"
            case .convertImage:
                return "convert image img presets"
            case .convertVideo:
                return "convert video vid presets"
            case .convertAudio:
                return "convert audio aud presets"
            }
        }
    }

    private enum PipelineCategory: String, CaseIterable, Equatable {
        case image
        case video
        case audio
        case pdf
        case allFile
        case all

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

        var autocomplete: String {
            "\(pipelinesPrefix) \(canonicalQuery) "
        }

        var canonicalQuery: String {
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
                return pipeline.fileType == fileType
            }
        }
    }

    static func namespaceResponse(
        query: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter(),
        cache: ClipboardImageCache? = nil,
        pipelineProvider: any ClopPipelineProviding = ClopPipelineProvider()
    ) -> ScriptFilterResponse {
        let namespaceQuery = String(query.dropFirst())
        do {
            let store = try PresetStore(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
            let normalized = namespaceQuery.lowercased()
            if normalized == "template"
                || normalized.hasPrefix("template ") {
                let templateQuery = normalized == "template"
                    ? ""
                    : String(namespaceQuery.dropFirst("template ".count))
                return withSettingsAffordance(
                    outputTemplateMenu(
                        query: templateQuery,
                        store: store
                    ),
                    store: store
                )
            }
            if normalized == "presets"
                || normalized.hasPrefix("presets ") {
                let presetQuery = normalized == "presets"
                    ? ""
                    : String(namespaceQuery.dropFirst("presets ".count))
                return withSettingsAffordance(
                    presetsMenu(
                        store: store,
                        query: presetQuery,
                        category: nil
                    ),
                    store: store
                )
            }
            if normalized == "pipelines"
                || normalized.hasPrefix("pipelines ") {
                let pipelineQuery = normalized == "pipelines"
                    ? ""
                    : String(namespaceQuery.dropFirst("pipelines ".count))
                return withSettingsAffordance(
                    pipelinesMenu(
                        provider: pipelineProvider,
                        query: pipelineQuery,
                        category: nil
                    ),
                    store: store
                )
            }
            return withSettingsAffordance(
                menu(
                    store: store,
                    query: namespaceQuery,
                    environment: environment,
                    fileManager: fileManager,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    ),
                    pipelineProvider: pipelineProvider
                ),
                store: store
            )
        } catch let caughtError {
            return error(
                "Unable to read settings",
                caughtError.localizedDescription
            )
        }
    }

    static func response(
        stateJSON: String,
        query: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter(),
        cache: ClipboardImageCache? = nil,
        pipelineProvider: any ClopPipelineProviding = ClopPipelineProvider()
    ) -> ScriptFilterResponse {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ) else {
            return error("Unable to open Configuration", "The menu state is invalid.")
        }

        do {
            let store = try PresetStore(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
            let response: ScriptFilterResponse
            switch state.mode {
            case .configuration:
                response = menu(
                    store: store,
                    query: "",
                    environment: environment,
                    fileManager: fileManager,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    ),
                    pipelineProvider: pipelineProvider
                )
            case .configurationOutputTemplate:
                response = outputTemplateMenu(
                    query: query,
                    store: store
                )
            case .configurationPresets:
                response = presetsMenu(
                    store: store,
                    query: query,
                    category: nil
                )
            case .configurationPresetCategory:
                response = presetsMenu(
                    store: store,
                    query: query,
                    category: category(from: state.configurationValue)
                )
            case .configurationPresetRemovalConfirmation:
                guard let action = state.presetAction else {
                    return error(
                        "Unable to remove preset",
                        "The preset removal state is invalid."
                    )
                }
                response = presetRemovalConfirmation(
                    action: action,
                    category: category(from: state.configurationValue)
                )
            case .configurationRemovePreset:
                guard let action = state.presetAction else {
                    return error(
                        "Unable to remove preset",
                        "The preset removal state is invalid."
                    )
                }
                _ = try store.remove(action.preset)
                response = presetsMenu(
                    store: store,
                    query: "",
                    category: category(from: state.configurationValue)
                )
            case .configurationSaveOutput:
                try store.updateOutputTemplate(state.configurationValue ?? "")
                response = menu(
                    store: store,
                    query: "",
                    environment: environment,
                    fileManager: fileManager,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    ),
                    pipelineProvider: pipelineProvider
                )
            case .configurationResetOutputConfirmation:
                response = confirmation(
                    title: "Reset output template?",
                    subtitle: "Restore \(SettingsDocument.builtInOutputTemplate) · Presets unchanged",
                    nextMode: .configurationResetOutput
                )
            case .configurationResetOutput:
                try store.updateOutputTemplate(SettingsDocument.builtInOutputTemplate)
                response = menu(
                    store: store,
                    query: "",
                    environment: environment,
                    fileManager: fileManager,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    ),
                    pipelineProvider: pipelineProvider
                )
            case .configurationResetPresetsConfirmation:
                let count = try store.load().presets.count
                response = confirmation(
                    title: "Remove all \(count) saved action presets?",
                    subtitle: "Return confirms · Cannot be undone",
                    nextMode: .configurationResetPresets
                )
            case .configurationResetPresets:
                _ = try store.removeAllPresets()
                response = presetsMenu(
                    store: store,
                    query: "",
                    category: nil
                )
            case .configurationCacheCleanupConfirmation:
                let activeCache = cache ?? ClipboardImageCache(
                    environment: environment,
                    fileManager: fileManager
                )
                let summary = activeCache.summary()
                response = confirmation(
                    title: "Remove \(summary.fileCount) cached clipboard images?",
                    subtitle: "Reclaim \(formattedBytes(summary.byteCount)) · Return confirms",
                    nextMode: .configurationCacheCleanup
                )
            case .configurationCacheCleanup:
                let removed = (cache ?? ClipboardImageCache(
                    environment: environment,
                    fileManager: fileManager
                )).removeAll()
                response = message(
                    title: "Removed \(removed.fileCount) cached clipboard images",
                    subtitle: "Reclaimed \(formattedBytes(removed.byteCount))."
                )
            case .configurationPipelines:
                response = pipelinesMenu(
                    provider: pipelineProvider,
                    query: query,
                    category: nil
                )
            case .configurationPipelineCategory:
                response = pipelinesMenu(
                    provider: pipelineProvider,
                    query: query,
                    category: pipelineCategory(from: state.configurationValue)
                )
            case .configurationPipelineAdd:
                guard let add = state.pipelineAction?.add else {
                    return error(
                        "Unable to add pipeline",
                        "The pipeline add state is invalid."
                    )
                }
                try pipelineProvider.addPipeline(add)
                response = pipelinesMenu(
                    provider: pipelineProvider,
                    query: "",
                    category: nil
                )
            case .configurationPipelineDeleteConfirmation:
                guard let pipeline = state.pipelineAction?.pipeline else {
                    return error(
                        "Unable to delete pipeline",
                        "The pipeline delete state is invalid."
                    )
                }
                response = pipelineDeleteConfirmation(
                    pipeline,
                    returnQuery: state.configurationValue
                )
            case .configurationPipelineDelete:
                guard let pipeline = state.pipelineAction?.pipeline else {
                    return error(
                        "Unable to delete pipeline",
                        "The pipeline delete state is invalid."
                    )
                }
                try pipelineProvider.deletePipeline(named: pipeline.name)
                response = pipelinesMenu(
                    provider: pipelineProvider,
                    query: state.configurationValue ?? "",
                    category: nil
                )
            case .configurationResetPipelinesConfirmation:
                let count = try pipelineProvider.listPipelines().count
                response = confirmation(
                    title: "Remove all \(count) saved pipelines?",
                    subtitle: "Return confirms · Cannot be undone",
                    nextMode: .configurationResetPipelines
                )
            case .configurationResetPipelines:
                let count = try removeAllPipelines(provider: pipelineProvider)
                response = message(
                    title: "Removed \(count) saved \(count == 1 ? "pipeline" : "pipelines")",
                    subtitle: "Pipeline library is empty."
                )
            default:
                return error(
                    "Unable to open Configuration",
                    "The menu state does not belong to Configuration."
                )
            }
            return withSettingsAffordance(response, store: store)
        } catch let caughtError {
            return error(
                "Unable to update settings",
                caughtError.localizedDescription
            )
        }
    }

    static func quietMutationFeedback(
        stateJSON: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter(),
        cache: ClipboardImageCache? = nil,
        pipelineProvider: any ClopPipelineProviding = ClopPipelineProvider()
    ) -> String? {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ) else {
            return environment.errorNotifications
                ? "Unable to update settings: The Configuration state is invalid."
                : nil
        }

        do {
            let store = try PresetStore(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
            let message: String
            switch state.mode {
            case .configurationSaveOutput:
                try store.updateOutputTemplate(state.configurationValue ?? "")
                message = "Output template updated"
            case .configurationResetOutput:
                try store.updateOutputTemplate(SettingsDocument.builtInOutputTemplate)
                message = "Output template reset"
            case .configurationResetPresets:
                let count = try store.removeAllPresets()
                message = "Removed \(count) action \(count == 1 ? "preset" : "presets")"
            case .configurationRemovePreset:
                guard let action = state.presetAction else {
                    return environment.errorNotifications
                        ? "Unable to update settings: The preset removal state is invalid."
                        : nil
                }
                let removed = try store.remove(action.preset)
                message = removed
                    ? "Removed \(presetDisplayValue(action.preset))"
                    : "Preset already removed"
            case .configurationCacheCleanup:
                let removed = (cache ?? ClipboardImageCache(
                    environment: environment,
                    fileManager: fileManager
                )).removeAll()
                message = "Cleared \(removed.fileCount) cached clipboard \(removed.fileCount == 1 ? "image" : "images")"
            case .configurationPipelineAdd:
                guard let add = state.pipelineAction?.add else {
                    return environment.errorNotifications
                        ? "Unable to update settings: The pipeline add state is invalid."
                        : nil
                }
                try pipelineProvider.addPipeline(add)
                message = add.replace
                    ? "Replaced pipeline \(add.name)"
                    : "Added pipeline \(add.name)"
            case .configurationPipelineDelete:
                guard let pipeline = state.pipelineAction?.pipeline else {
                    return environment.errorNotifications
                        ? "Unable to update settings: The pipeline delete state is invalid."
                        : nil
                }
                try pipelineProvider.deletePipeline(named: pipeline.name)
                message = "Deleted pipeline \(pipeline.name)"
            case .configurationResetPipelines:
                let count = try removeAllPipelines(provider: pipelineProvider)
                message = "Removed \(count) saved \(count == 1 ? "pipeline" : "pipelines")"
            default:
                return environment.errorNotifications
                    ? "Unable to update settings: The Configuration action is invalid."
                    : nil
            }
            return environment.completionNotifications ? message : nil
        } catch {
            return environment.errorNotifications
                ? "Unable to update settings: \(error.localizedDescription)"
                : nil
        }
    }

    static func mutationReturnQuery(stateJSON: String) -> String {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ) else {
            return namespacePrefix
        }

        switch state.mode {
        case .configurationRemovePreset:
            guard let category = category(from: state.configurationValue) else {
                return presetsAutocomplete
            }
            return category.autocomplete
        case .configurationResetPresets:
            return presetsAutocomplete
        case .configurationPipelineDelete:
            return "\(pipelinesAutocomplete)\(state.configurationValue ?? "")"
        case .configurationPipelineAdd:
            return pipelinesAutocomplete
        case .configurationResetPipelines:
            return pipelinesAutocomplete
        default:
            return namespacePrefix
        }
    }

    private static func menu(
        store: PresetStore,
        query: String,
        environment: Environment,
        fileManager: FileManager,
        cache: ClipboardImageCache,
        pipelineProvider: any ClopPipelineProviding
    ) -> ScriptFilterResponse {
        let document: SettingsDocument
        do {
            document = try store.load()
        } catch let caughtError {
            return error(
                "Unable to read settings",
                caughtError.localizedDescription
            )
        }

        var items = [
            ScriptFilterItem(
                title: "Output Template",
                subtitle: templateExample(document.outputTemplate),
                arg: templatePrefix,
                valid: false,
                autocomplete: templatePrefix,
                match: "output template preserve original path filename"
            ),
            workflowSettingsItem(store: store)
        ]

        if document.outputTemplate != SettingsDocument.builtInOutputTemplate {
            items.append(resetOutputItem())
        }
        if !document.presets.isEmpty {
            items.append(managePresetsItem(count: document.presets.count))
        }
        items.append(managePipelinesItem(provider: pipelineProvider))

        let summary = cache.summary()
        if summary.fileCount > 0 {
            let stateJSON = encoded(.configuration(
                mode: .configurationCacheCleanupConfirmation
            ))
            items.append(ScriptFilterItem(
                title: "Clear cached clipboard images",
                subtitle: "\(summary.fileCount) files · \(formattedBytes(summary.byteCount))",
                arg: stateJSON,
                valid: true,
                autocomplete: ":clear cache",
                match: "clear cached clipboard images cache cleanup",
                variables: transitionVariables(stateJSON)
            ))
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ScriptFilterResponse(items: items)
        }
        let search = FuzzySearch<ScriptFilterItem>(
            query: trimmed,
            targetText: {
                [$0.title, $0.match].compactMap(\.self).joined(separator: " ")
            }
        )
        let matches = search.sorted(items)
        guard !matches.isEmpty else {
            return error(
                "No matching Configuration commands",
                "Try another search term."
            )
        }
        return ScriptFilterResponse(items: matches.map {
            items[$0.targetIndex]
        })
    }

    private static func workflowSettingsItem(
        store: PresetStore
    ) -> ScriptFilterItem {
        let filePath = store.fileURL.path
        let directoryPath = store.fileURL.deletingLastPathComponent().path
        return ScriptFilterItem(
            type: "file",
            title: "Workflow Settings",
            subtitle: "↩ Open Workflow Configuration · ⌘↩ Reveal Settings Folder",
            arg: filePath,
            valid: true,
            autocomplete: ":settings",
            match: "workflow configuration settings file folder reveal finder",
            icon: ScriptFilterIcon(path: filePath, type: .fileIcon),
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.workflowSettings.rawValue
            ],
            mods: ScriptFilterMods(command: ScriptFilterModifier(
                arg: directoryPath,
                subtitle: "Reveal Settings Folder",
                valid: true,
                variables: [
                    ActionMenu.requestKindVariable:
                        WorkflowRequestKind.revealSettingsFolder.rawValue
                ]
            )),
            quickLookURL: filePath,
            action: ScriptFilterAction(file: filePath)
        )
    }

    private static func managePipelinesItem(
        provider: any ClopPipelineProviding
    ) -> ScriptFilterItem {
        let countText: String
        if let count = try? provider.listPipelines().count {
            countText = "\(count) Saved \(count == 1 ? "Pipeline" : "Pipelines")"
        } else {
            countText = "Manage saved Clop pipelines"
        }
        return ScriptFilterItem(
            title: "Manage pipelines",
            subtitle: countText,
            arg: Self.pipelinesAutocomplete,
            valid: true,
            autocomplete: Self.pipelinesAutocomplete,
            match: "manage add replace remove delete pipelines",
            variables: queryTransitionVariables()
        )
    }

    private static func removeAllPipelines(
        provider: any ClopPipelineProviding
    ) throws -> Int {
        let pipelines = try provider.listPipelines()
        for pipeline in pipelines {
            try provider.deletePipeline(named: pipeline.name)
        }
        return pipelines.count
    }

    private static func pipelinesMenu(
        provider: any ClopPipelineProviding,
        query: String,
        category: PipelineCategory?
    ) -> ScriptFilterResponse {
        let savedPipelines: [SavedPipeline]
        do {
            savedPipelines = try provider.listPipelines()
        } catch let caughtError {
            return error(
                "Unable to read saved pipelines",
                caughtError.localizedDescription
            )
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPipelineAddQuery(trimmed) {
            return addPipelineResponse(
                trimmed,
                pipelines: savedPipelines
            )
        }
        if let route = pipelineCategoryRoute(from: trimmed) {
            return categoryPipelineMenu(
                savedPipelines,
                category: route.category,
                query: route.query
            )
        }
        if let category {
            return categoryPipelineMenu(
                savedPipelines,
                category: category,
                query: trimmed
            )
        }

        var items: [ScriptFilterItem]
        if trimmed.isEmpty {
            items = [addPipelineGuideItem()]
            items += PipelineCategory.allCases.compactMap { category in
                let count = pipelines(in: savedPipelines, category: category).count
                guard count > 0 || category == .all else { return nil }
                return pipelineCategoryItem(category, count: count)
            }
            if !savedPipelines.isEmpty {
                items.append(removePipelinesItem(count: savedPipelines.count))
            }
            return ScriptFilterResponse(items: items, skipKnowledge: true)
        }

        let categoryItems = PipelineCategory.allCases.compactMap { category -> ScriptFilterItem? in
            let count = pipelines(in: savedPipelines, category: category).count
            guard count > 0 || category == .all else { return nil }
            return pipelineCategoryItem(category, count: count)
        }
        let pipelineItems = savedPipelines
            .sorted(by: pipelineDisplayOrder)
            .map { pipelineItem($0, returnQuery: trimmed) }
        items = categoryItems + pipelineItems
        if !savedPipelines.isEmpty {
            items.append(removePipelinesItem(count: savedPipelines.count))
        }

        let search = FuzzySearch<ScriptFilterItem>(
            query: trimmed,
            targetText: {
                [$0.title, $0.match].compactMap(\.self)
                    .joined(separator: " ")
            }
        )
        let matches = search.sorted(items)
        guard !matches.isEmpty else {
            return addPipelinePromptItem(query: trimmed)
        }
        return ScriptFilterResponse(
            items: [addPipelineGuideItem()] + matches.map {
                items[$0.targetIndex]
            },
            skipKnowledge: true
        )
    }

    private static func categoryPipelineMenu(
        _ allPipelines: [SavedPipeline],
        category: PipelineCategory,
        query: String
    ) -> ScriptFilterResponse {
        let categoryPipelines = pipelines(in: allPipelines, category: category)
            .sorted(by: pipelineDisplayOrder)
        guard !categoryPipelines.isEmpty else {
            return message(
                title: "No \(category.title.lowercased())",
                subtitle: "Add a pipeline or choose another filter."
            )
        }

        let items = categoryPipelines.map {
            pipelineItem(
                $0,
                returnQuery: "\(category.canonicalQuery) \(query)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !query.isEmpty else {
            return ScriptFilterResponse(items: items, skipKnowledge: true)
        }

        let search = FuzzySearch<ScriptFilterItem>(
            query: query,
            targetText: {
                [$0.title, $0.match].compactMap(\.self)
                    .joined(separator: " ")
            }
        )
        let matches = search.sorted(items)
        guard !matches.isEmpty else {
            return error(
                "No matching \(category.title.lowercased())",
                "Try another pipeline name."
            )
        }
        return ScriptFilterResponse(items: matches.map {
            items[$0.targetIndex]
        }, skipKnowledge: true)
    }

    private static func pipelineCategoryItem(
        _ category: PipelineCategory,
        count: Int
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: category.title,
            subtitle: "\(count) Saved \(count == 1 ? "Pipeline" : "Pipelines")",
            arg: category.autocomplete,
            valid: true,
            autocomplete: category.autocomplete,
            match: category.matchText,
            variables: queryTransitionVariables(),
            text: ScriptFilterText(largetype: pipelineAddReference)
        )
    }

    private static func removePipelinesItem(count: Int) -> ScriptFilterItem {
        let stateJSON = encoded(.configuration(
            mode: .configurationResetPipelinesConfirmation
        ))
        return ScriptFilterItem(
            title: "Remove all saved pipelines",
            subtitle: "\(count) Saved \(count == 1 ? "Pipeline" : "Pipelines") in Clop",
            arg: stateJSON,
            valid: true,
            autocomplete: "\(pipelinesPrefix) remove all",
            match: "remove reset delete saved pipelines",
            variables: transitionVariables(stateJSON)
        )
    }

    private static func pipelineItem(
        _ pipeline: SavedPipeline,
        returnQuery: String
    ) -> ScriptFilterItem {
        let confirmState = MenuState.configuration(
            mode: .configurationPipelineDeleteConfirmation,
            value: returnQuery,
            pipelineAction: PipelineMenuAction(
                kind: .confirmDelete,
                pipeline: pipeline
            )
        )
        let confirmJSON = encoded(confirmState)
        return ScriptFilterItem(
            uid: "configuration.pipeline.\(pipeline.id ?? pipeline.name).\(pipeline.fileType?.rawValue ?? "all")",
            title: pipeline.name,
            subtitle: "\(pipelineTypeDescription(for: pipeline)) · ⌘L Details · ⌘↩ Delete",
            arg: "",
            valid: false,
            autocomplete: "\(pipelinesPrefix) \(pipeline.name)",
            match: "\(pipeline.name) \(pipeline.fileType?.rawValue ?? "all") \(pipeline.rawText)",
            variables: queryTransitionVariables(),
            mods: ScriptFilterMods(command: ScriptFilterModifier(
                arg: confirmJSON,
                subtitle: "Delete Pipeline",
                valid: true,
                variables: transitionVariables(confirmJSON)
            )),
            text: ScriptFilterText(largetype: pipelineDetails(pipeline))
        )
    }

    private static func pipelineDeleteConfirmation(
        _ pipeline: SavedPipeline,
        returnQuery: String?
    ) -> ScriptFilterResponse {
        let removeState = MenuState.configuration(
            mode: .configurationPipelineDelete,
            value: returnQuery,
            pipelineAction: PipelineMenuAction(
                kind: .delete,
                pipeline: pipeline
            )
        )
        let removeJSON = encoded(removeState)
        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Delete Pipeline \(pipeline.name)?",
                    subtitle: "Return confirms · Cannot be undone · ⌘↩ Confirm and close",
                    arg: removeJSON,
                    valid: true,
                    variables: returnMutationVariables(removeJSON),
                    mods: closeModifier(removeJSON),
                    text: ScriptFilterText(largetype: pipelineDetails(pipeline))
                ),
                ScriptFilterItem(
                    title: "Cancel",
                    subtitle: "Return keeps pipeline",
                    arg: "\(pipelinesAutocomplete)\(returnQuery ?? "")",
                    valid: true,
                    variables: queryTransitionVariables()
                )
            ],
            skipKnowledge: true
        )
    }

    private static func addPipelineResponse(
        _ query: String,
        pipelines: [SavedPipeline]
    ) -> ScriptFilterResponse {
        let value = normalizedAddValue(query)
        guard let request = PipelineAddParser.parse(value) else {
            if let issue = PipelineAddParser.guidanceIssue(for: value) {
                return ScriptFilterResponse(items: [
                    ScriptFilterItem(
                        title: issue.title,
                        subtitle: "\(issue.subtitle) · ⌘L Reference",
                        arg: "",
                        valid: false,
                        text: ScriptFilterText(largetype: issue.detail)
                    )
                ], skipKnowledge: true)
            }
            return ScriptFilterResponse(items: [
                ScriptFilterItem(
                    title: "Type pipeline name and steps",
                    subtitle: "Use Name => steps ; img skip hide · ⌘L Reference",
                    arg: "",
                    valid: false,
                    text: ScriptFilterText(largetype: pipelineAddReference)
                )
            ], skipKnowledge: true)
        }
        if let issue = PipelineSyntax.guidanceIssue(for: request.steps) {
            return ScriptFilterResponse(items: [
                ScriptFilterItem(
                    title: issue.title,
                    subtitle: "\(issue.subtitle) · ⌘L Reference",
                    arg: "",
                    valid: false,
                    text: ScriptFilterText(largetype: issue.detail)
                )
            ], skipKnowledge: true)
        }

        let existing = pipelines.contains {
            $0.name.caseInsensitiveCompare(request.name) == .orderedSame
        }
        let addJSON = encoded(.configuration(
            mode: .configurationPipelineAdd,
            pipelineAction: PipelineMenuAction(kind: .add, add: request)
        ))
        var replace = request
        replace.replace = true
        let replaceJSON = encoded(.configuration(
            mode: .configurationPipelineAdd,
            pipelineAction: PipelineMenuAction(kind: .add, add: replace)
        ))

        let subtitle = "\(pipelineAddSummary(request)) · ⌘L Reference"
        if existing {
            return ScriptFilterResponse(items: [
                ScriptFilterItem(
                    title: "Pipeline \(request.name) already exists",
                    subtitle: "\(subtitle) · ⌘↩ Replace",
                    arg: "",
                    valid: false,
                    mods: ScriptFilterMods(command: ScriptFilterModifier(
                        arg: replaceJSON,
                        subtitle: "Replace Pipeline",
                        valid: true,
                        variables: returnMutationVariables(replaceJSON)
                    )),
                    text: ScriptFilterText(largetype: pipelineAddDetails(request))
                )
            ], skipKnowledge: true)
        }

        return ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: "Add Pipeline \(request.name)",
                subtitle: subtitle,
                arg: addJSON,
                valid: true,
                variables: returnMutationVariables(addJSON),
                mods: ScriptFilterMods(command: ScriptFilterModifier(
                    arg: replaceJSON,
                    subtitle: "Replace if Pipeline Exists",
                    valid: true,
                    variables: returnMutationVariables(replaceJSON)
                )),
                text: ScriptFilterText(largetype: pipelineAddDetails(request))
            )
        ], skipKnowledge: true)
    }

    private static func addPipelineGuideItem() -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Add pipeline",
            subtitle: "Use Name => steps ; img skip hide · ⌘L Reference",
            arg: "\(pipelinesAutocomplete)add ",
            valid: true,
            autocomplete: "\(pipelinesAutocomplete)add ",
            match: "add create pipeline image video audio pdf skip hide",
            variables: queryTransitionVariables(),
            text: ScriptFilterText(largetype: pipelineAddReference)
        )
    }

    private static func addPipelinePromptItem(query: String) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: "Add a new pipeline",
                subtitle: "Use Name => steps ; img skip hide · ⌘L Reference",
                arg: "\(pipelinesAutocomplete)\(query)",
                valid: true,
                autocomplete: "\(pipelinesAutocomplete)\(query)",
                variables: queryTransitionVariables(),
                text: ScriptFilterText(largetype: pipelineAddReference)
            )
        ], skipKnowledge: true)
    }

    private static func isPipelineAddQuery(_ query: String) -> Bool {
        let normalized = query.lowercased()
        return normalized.hasPrefix("add ") || query.contains("=>")
    }

    private static func normalizedAddValue(_ query: String) -> String {
        query.lowercased().hasPrefix("add ")
            ? String(query.dropFirst("add ".count))
            : query
    }

    private static func outputTemplateMenu(
        query: String,
        store: PresetStore
    ) -> ScriptFilterResponse {
        let document: SettingsDocument
        do {
            document = try store.load()
        } catch let caughtError {
            return error(
                "Unable to read settings",
                caughtError.localizedDescription
            )
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ScriptFilterResponse(items: [
                templateReferenceItem(
                    title: "Type a suffix, prefix, or advanced template",
                    subtitle: "Current: \(document.outputTemplate) · ⌘L token reference"
                )
            ])
        }

        if isAdvancedInput(trimmed) {
            return advancedTemplateResponse(trimmed)
        }

        let name = trimmed.trimmingCharacters(
            in: CharacterSet(charactersIn: "- ")
        )
        guard !name.isEmpty else {
            return templateError(
                "Enter a name",
                "Type a suffix such as optimized or an advanced template."
            )
        }
        let suffix = "%P/%f-\(name)"
        let prefix = "%P/\(name)-%f"
        if let validation = OutputTemplateValidator.validate(suffix) {
            return templateError(
                "Invalid output name",
                validation.localizedDescription
            )
        }
        return ScriptFilterResponse(items: [
            saveTemplateItem(
                title: "Add “-\(name)”",
                template: suffix
            ),
            saveTemplateItem(
                title: "Add “\(name)-”",
                template: prefix
            )
        ])
    }

    private static func advancedTemplateResponse(
        _ template: String
    ) -> ScriptFilterResponse {
        if let validation = OutputTemplateValidator.validate(template) {
            return templateError(
                "Invalid output template",
                validation.localizedDescription
            )
        }
        return ScriptFilterResponse(items: [
            saveTemplateItem(
                title: "Use template \(template)",
                template: template
            )
        ])
    }

    private static func saveTemplateItem(
        title: String,
        template: String
    ) -> ScriptFilterItem {
        let stateJSON = encoded(.configuration(
            mode: .configurationSaveOutput,
            value: template
        ))
        return templateReferenceItem(
            title: title,
            subtitle: "\(templateExample(template)) · ⌘L Reference",
            arg: stateJSON,
            valid: true,
            variables: returnMutationVariables(stateJSON),
            mods: closeModifier(stateJSON)
        )
    }

    private static func templateReferenceItem(
        title: String,
        subtitle: String,
        arg: String? = "",
        valid: Bool = false,
        variables: [String: String]? = nil,
        mods: ScriptFilterMods? = nil
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: title,
            subtitle: subtitle,
            arg: arg,
            valid: valid,
            variables: variables,
            mods: mods,
            text: ScriptFilterText(
                copy: tokenReference,
                largetype: tokenReference
            )
        )
    }

    private static func templateError(
        _ title: String,
        _ subtitle: String
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            templateReferenceItem(
                title: title,
                subtitle: "\(subtitle) · ⌘L Reference"
            )
        ])
    }

    private static func resetOutputItem() -> ScriptFilterItem {
        let resetState = encoded(.configuration(
            mode: .configurationResetOutputConfirmation
        ))
        return ScriptFilterItem(
            title: "Reset output template",
            subtitle: "Restore \(SettingsDocument.builtInOutputTemplate)",
            arg: resetState,
            valid: true,
            autocomplete: ":reset output",
            match: "reset output template restore preserve original",
            variables: transitionVariables(resetState)
        )
    }

    private static func managePresetsItem(count: Int) -> ScriptFilterItem {
        return ScriptFilterItem(
            title: "Manage action presets",
            subtitle: "\(count) Saved \(count == 1 ? "Preset" : "Presets") across all action menus",
            arg: Self.presetsAutocomplete,
            valid: true,
            autocomplete: Self.presetsAutocomplete,
            match: "manage remove reset delete action presets",
            variables: queryTransitionVariables()
        )
    }

    private static func removePresetsItem(count: Int) -> ScriptFilterItem {
        let stateJSON = encoded(.configuration(
            mode: .configurationResetPresetsConfirmation
        ))
        return ScriptFilterItem(
            title: "Remove all action presets",
            subtitle: "\(count) Saved \(count == 1 ? "Preset" : "Presets") across all action menus",
            arg: stateJSON,
            valid: true,
            autocomplete: "\(presetsPrefix) remove all",
            match: "remove reset delete action presets",
            variables: transitionVariables(stateJSON)
        )
    }

    private static func presetsMenu(
        store: PresetStore,
        query: String,
        category: PresetCategory?
    ) -> ScriptFilterResponse {
        let document: SettingsDocument
        do {
            document = try store.load()
        } catch let caughtError {
            return error(
                "Unable to read saved presets",
                caughtError.localizedDescription
            )
        }

        guard !document.presets.isEmpty else {
            return message(
                title: "No saved action presets",
                subtitle: "Save presets from an action menu first."
            )
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let categoryRoute = presetCategoryRoute(from: trimmed) {
            return categoryPresetMenu(
                document.presets,
                category: categoryRoute.category,
                query: categoryRoute.query
            )
        }
        if let category {
            return categoryPresetMenu(
                document.presets,
                category: category,
                query: trimmed
            )
        }

        var items: [ScriptFilterItem]
        if trimmed.isEmpty {
            items = PresetCategory.allCases.compactMap { category -> ScriptFilterItem? in
                let count = presets(in: document.presets, category: category).count
                guard count > 0 else { return nil }
                return categoryItem(category, count: count)
            }
            items.append(removePresetsItem(count: document.presets.count))
            return ScriptFilterResponse(items: items)
        }

        let categoryItems = PresetCategory.allCases.compactMap { category -> ScriptFilterItem? in
            let count = presets(in: document.presets, category: category).count
            guard count > 0 else { return nil }
            return categoryItem(category, count: count)
        }
        let presetItems = document.presets
            .sorted(by: presetDisplayOrder)
            .map { presetItem($0, sourceCategory: nil) }
        items = categoryItems + presetItems + [
            removePresetsItem(count: document.presets.count)
        ]

        let search = FuzzySearch<ScriptFilterItem>(
            query: trimmed,
            targetText: {
                [$0.title, $0.match].compactMap(\.self)
                    .joined(separator: " ")
            }
        )
        let matches = search.sorted(items)
        guard !matches.isEmpty else {
            return error(
                "No matching action presets",
                "Try a preset value or category name."
            )
        }
        return ScriptFilterResponse(items: matches.map {
            items[$0.targetIndex]
        })
    }

    private static func categoryPresetMenu(
        _ allPresets: [ActionPreset],
        category: PresetCategory,
        query: String
    ) -> ScriptFilterResponse {
        let categoryPresets = presets(in: allPresets, category: category)
            .sorted(by: presetDisplayOrder)
        guard !categoryPresets.isEmpty else {
            return message(
                title: "No \(category.title.lowercased())",
                subtitle: "Save presets from that action menu first."
            )
        }

        let items = categoryPresets.map {
            presetItem($0, sourceCategory: category)
        }
        guard !query.isEmpty else {
            return ScriptFilterResponse(items: items)
        }

        let search = FuzzySearch<ScriptFilterItem>(
            query: query,
            targetText: {
                [$0.title, $0.match].compactMap(\.self)
                    .joined(separator: " ")
            }
        )
        let matches = search.sorted(items)
        guard !matches.isEmpty else {
            return error(
                "No matching \(category.title.lowercased())",
                "Try another preset value."
            )
        }
        return ScriptFilterResponse(items: matches.map {
            items[$0.targetIndex]
        })
    }

    private static func categoryItem(
        _ category: PresetCategory,
        count: Int
    ) -> ScriptFilterItem {
        return ScriptFilterItem(
            title: category.title,
            subtitle: "\(count) Saved \(count == 1 ? "Preset" : "Presets") · ⌘L Filter Shortcuts",
            arg: category.autocomplete,
            valid: true,
            autocomplete: category.autocomplete,
            match: category.matchText,
            variables: queryTransitionVariables(),
            text: ScriptFilterText(largetype: presetCategoryReference)
        )
    }

    private static func presetItem(
        _ preset: ActionPreset,
        sourceCategory: PresetCategory?
    ) -> ScriptFilterItem {
        let state = MenuState(
            mode: .configurationPresetRemovalConfirmation,
            presetAction: PresetMenuAction(
                kind: .confirmRemoval,
                preset: preset
            ),
            configurationValue: sourceCategory?.rawValue
        )
        let stateJSON = encoded(state)
        let categoryTitle = category(for: preset).title
        return ScriptFilterItem(
            uid: "configuration.\(presetStableUID(preset))",
            title: presetDisplayValue(preset),
            subtitle: "Saved \(categoryTitle.dropLast(" Presets".count)) Preset · Return to review removal",
            arg: stateJSON,
            valid: true,
            autocomplete: "\(presetsPrefix) \(presetDisplayValue(preset))",
            match: "\(categoryTitle) \(presetDisplayValue(preset))",
            variables: transitionVariables(stateJSON)
        )
    }

    private static func presetRemovalConfirmation(
        action: PresetMenuAction,
        category: PresetCategory?
    ) -> ScriptFilterResponse {
        let removeState = MenuState(
            mode: .configurationRemovePreset,
            presetAction: PresetMenuAction(kind: .remove, preset: action.preset),
            configurationValue: category?.rawValue
        )
        let removeJSON = encoded(removeState)
        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Remove Preset \(presetDisplayValue(action.preset))?",
                    subtitle: "Return confirms · Cannot be undone · ⌘↩ Confirm and close",
                    arg: removeJSON,
                    valid: true,
                    variables: returnMutationVariables(removeJSON),
                    mods: closeModifier(removeJSON)
                ),
                ScriptFilterItem(
                    title: "Cancel",
                    subtitle: "Return keeps preset",
                    arg: category?.autocomplete ?? Self.presetsAutocomplete,
                    valid: true,
                    variables: queryTransitionVariables()
                )
            ],
            skipKnowledge: true
        )
    }

    private static func presetCategoryRoute(
        from query: String
    ) -> (category: PresetCategory, query: String)? {
        let routes: [(aliases: [String], category: PresetCategory)] = [
            (["crop pdf", "pdf"], .cropPDF),
            (["convert image", "image", "img"], .convertImage),
            (["convert video", "video", "vid"], .convertVideo),
            (["convert audio", "audio", "aud"], .convertAudio),
            (["optimize", "opt"], .optimize),
            (["crop", "resize"], .crop),
            (["downscale", "down"], .downscale)
        ]
        let normalized = query.lowercased()
        for route in routes {
            for alias in route.aliases {
                if normalized == alias {
                    return (route.category, "")
                }
                if normalized.hasPrefix(alias + " ") {
                    let remaining = String(query.dropFirst(alias.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return (route.category, remaining)
                }
            }
        }
        return nil
    }

    private static func presets(
        in presets: [ActionPreset],
        category: PresetCategory
    ) -> [ActionPreset] {
        presets.filter { self.category(for: $0) == category }
    }

    private static func category(for preset: ActionPreset) -> PresetCategory {
        switch preset {
        case .optimize:
            return .optimize
        case .crop:
            return .crop
        case .cropPDF:
            return .cropPDF
        case .downscale:
            return .downscale
        case .conversion(let value):
            switch value.choice.media {
            case .image:
                return .convertImage
            case .video:
                return .convertVideo
            case .audio:
                return .convertAudio
            }
        }
    }

    private static func category(from value: String?) -> PresetCategory? {
        value.flatMap(PresetCategory.init(rawValue:))
    }

    private static func pipelineCategory(from value: String?) -> PipelineCategory? {
        value.flatMap(PipelineCategory.init(rawValue:))
    }

    private static func pipelineCategoryRoute(
        from query: String
    ) -> (category: PipelineCategory, query: String)? {
        let normalized = query.lowercased()
        for category in PipelineCategory.allCases {
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

    private static func pipelines(
        in pipelines: [SavedPipeline],
        category: PipelineCategory
    ) -> [SavedPipeline] {
        pipelines.filter(category.accepts)
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

    private static func pipelineTypeDescription(
        for pipeline: SavedPipeline
    ) -> String {
        guard let fileType = pipeline.fileType else {
            return "All-file pipeline"
        }
        return "\(fileType.title) pipeline"
    }

    private static func pipelineDetails(_ pipeline: SavedPipeline) -> String {
        [
            pipeline.name,
            "",
            pipelineTypeDescription(for: pipeline),
            pipelineSettingsDescription(
                skipOptimisation: pipeline.skipOptimisation,
                hideResult: pipeline.hideResult
            ),
            "",
            "Steps",
            pipeline.rawText
        ].joined(separator: "\n")
    }

    private static func pipelineAddDetails(_ request: PipelineAddRequest) -> String {
        [
            "Add Pipeline \(request.name)",
            "",
            pipelineTypeDescription(for: SavedPipeline(
                name: request.name,
                fileType: request.fileType,
                rawText: request.steps,
                skipOptimisation: request.skipOptimisation,
                hideResult: request.hideResult
            )),
            pipelineSettingsDescription(
                skipOptimisation: request.skipOptimisation,
                hideResult: request.hideResult
            ),
            "",
            "Steps",
            request.steps,
            "",
            pipelineAddReference
        ].joined(separator: "\n")
    }

    private static func pipelineAddSummary(
        _ request: PipelineAddRequest
    ) -> String {
        [
            request.fileType?.title ?? "All file types",
            request.skipOptimisation
                ? "Steps only"
                : "Optimizes first",
            request.hideResult ? "Hide result" : nil
        ].compactMap(\.self).joined(separator: " · ")
    }

    private static func pipelineSettingsDescription(
        skipOptimisation: Bool,
        hideResult: Bool
    ) -> String {
        var parts = [
            skipOptimisation
                ? "Steps only"
                : "Includes implicit optimization"
        ]
        if hideResult {
            parts.append("Hides Clop result")
        }
        return parts.joined(separator: " · ")
    }

    private static var pipelineAddReference: String {
        [
            PipelineSyntax.syntaxReference(savedCreation: true),
            "",
            "Steps are passed directly to Clop. Return adds. Command-Return replaces."
        ].joined(separator: "\n")
    }

    private static func presetDisplayOrder(
        _ lhs: ActionPreset,
        _ rhs: ActionPreset
    ) -> Bool {
        let lhsCategory = category(for: lhs).title
        let rhsCategory = category(for: rhs).title
        let categoryComparison = lhsCategory.localizedStandardCompare(rhsCategory)
        if categoryComparison != .orderedSame {
            return categoryComparison == .orderedAscending
        }
        return presetDisplayValue(lhs).localizedStandardCompare(
            presetDisplayValue(rhs)
        ) == .orderedAscending
    }

    private static func presetDisplayValue(_ preset: ActionPreset) -> String {
        switch preset {
        case .crop(let value):
            return value.displayValue
        case .downscale(let value):
            return value.displayValue
        case .conversion(let value):
            return value.displayValue
        case .optimize(let value):
            return value.displayValue
        case .cropPDF(let value):
            return value.displayValue
        }
    }

    private static func presetStableUID(_ preset: ActionPreset) -> String {
        switch preset {
        case .crop(let value):
            return value.stableUID
        case .downscale(let value):
            return value.stableUID
        case .conversion(let value):
            return value.stableUID
        case .optimize(let value):
            return value.stableUID
        case .cropPDF(let value):
            return value.stableUID
        }
    }

    private static func isAdvancedInput(_ value: String) -> Bool {
        value.contains("%") || value.contains("/") || value.hasPrefix("~")
    }

    private static func templateExample(_ template: String) -> String {
        let preview = OutputTemplateValidator.preview(
            template: template,
            source: URL(fileURLWithPath: "/Original folder/Photo.png"),
            homeDirectory: "/Users/me"
        ) ?? template
        let friendly: String
        if preview.hasPrefix("/Original folder/") {
            friendly = String(preview.dropFirst())
        } else {
            friendly = preview.replacingOccurrences(
                of: "/Users/me",
                with: "~"
            )
        }
        return "\(template) · Photo.png → \(friendly)"
    }

    private static let tokenReference = """
    OUTPUT TEMPLATE TOKENS

    %P  Source folder
    %f  Filename without extension

    DATE
    %y  Year
    %m  Month number
    %n  Month name
    %d  Day
    %w  Weekday

    TIME
    %H  Hour
    %M  Minute
    %S  Second
    %p  AM or PM

    UNIQUE NAMES
    %r  Random characters
    %i  Incrementing number

    EXAMPLES
    %P/%f-clop
    ~/Desktop/Clop/%f
    %P/Processed/%y-%m-%d-%f

    Clop adds the output extension automatically.
    """

    private static let presetCategoryReference = """
    PRESET FILTER SHORTCUTS

    Optimize Presets
    optimize
    opt

    Crop / Resize Presets
    crop
    resize

    Crop PDF Presets
    crop pdf
    pdf

    Downscale Presets
    downscale
    down

    Convert Image Presets
    convert image
    image
    img

    Convert Video Presets
    convert video
    video
    vid

    Convert Audio Presets
    convert audio
    audio
    aud
    """

    private static func confirmation(
        title: String,
        subtitle: String,
        nextMode: MenuMode
    ) -> ScriptFilterResponse {
        let stateJSON = encoded(.configuration(mode: nextMode))
        return ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: title,
                subtitle: "\(subtitle) · ⌘↩ Apply and close",
                arg: stateJSON,
                valid: true,
                variables: returnMutationVariables(stateJSON),
                mods: closeModifier(stateJSON)
            )
        ])
    }

    private static func message(title: String, subtitle: String) -> ScriptFilterResponse {
        ScriptFilterResponse(items: [
            ScriptFilterItem(title: title, subtitle: subtitle, arg: "", valid: false)
        ])
    }

    private static func error(_ title: String, _ subtitle: String) -> ScriptFilterResponse {
        message(title: title, subtitle: subtitle)
    }

    private static func withSettingsAffordance(
        _ response: ScriptFilterResponse,
        store: PresetStore
    ) -> ScriptFilterResponse {
        let affordance = ScriptFilterAffordance.settingsFile(
            store.fileURL.path,
            largeType: configurationSummary(store: store)
        )
        var response = response
        response.items = response.items.map(affordance.apply)
        return response
    }

    private static func configurationSummary(store: PresetStore) -> String? {
        guard let document = try? store.load() else {
            return nil
        }

        var lines = [
            "SETTINGS",
            store.fileURL.path,
            "",
            "OUTPUT TEMPLATE",
            document.outputTemplate,
            "",
            "PRESETS"
        ]
        let groups = presetGroups(document.presets)
        if groups.isEmpty {
            lines.append("None")
        } else {
            for (index, group) in groups.enumerated() {
                if index > 0 {
                    lines.append("")
                }
                lines.append("\(group.title): \(group.values.count)")
                lines.append(contentsOf: visiblePresetValues(group.values))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func visiblePresetValues(_ values: [String]) -> [String] {
        let maximum = 5
        var lines = values.prefix(maximum).map { "- \($0)" }
        if values.count > maximum {
            lines.append("... and \(values.count - maximum) more")
        }
        return lines
    }

    private static func presetGroups(
        _ presets: [ActionPreset]
    ) -> [(title: String, values: [String])] {
        var crop = [String]()
        var downscale = [String]()
        var convertImage = [String]()
        var convertVideo = [String]()
        var convertAudio = [String]()
        var optimize = [String]()
        var cropPDF = [String]()

        for preset in presets {
            switch preset {
            case .crop(let value):
                crop.append(value.displayValue)
            case .downscale(let value):
                downscale.append(value.displayValue)
            case .conversion(let value):
                switch value.choice.media {
                case .image:
                    convertImage.append(value.displayValue)
                case .video:
                    convertVideo.append(value.displayValue)
                case .audio:
                    convertAudio.append(value.displayValue)
                }
            case .optimize(let value):
                optimize.append(value.displayValue)
            case .cropPDF(let value):
                cropPDF.append(value.displayValue)
            }
        }

        return [
            ("Optimize", optimize),
            ("Crop / Resize", crop),
            ("Crop PDF", cropPDF),
            ("Downscale", downscale),
            ("Convert Image", convertImage),
            ("Convert Video", convertVideo),
            ("Convert Audio", convertAudio)
        ].compactMap { group in
            group.1.isEmpty ? nil : group
        }
    }

    private static func encoded(_ state: MenuState) -> String {
        (try? JSONOutput.string(for: state, prettyPrinted: false)) ?? ""
    }

    private static func transitionVariables(_ stateJSON: String) -> [String: String] {
        [
            ActionMenu.requestKindVariable:
                WorkflowRequestKind.parameterStep.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func queryTransitionVariables() -> [String: String] {
        [
            ActionMenu.requestKindVariable:
                WorkflowRequestKind.parameterStepQuery.rawValue,
            ActionMenu.menuStateVariable: ""
        ]
    }

    private static func mutationVariables(_ stateJSON: String) -> [String: String] {
        [
            ActionMenu.requestKindVariable:
                WorkflowRequestKind.configurationMutation.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func returnMutationVariables(_ stateJSON: String) -> [String: String] {
        [
            ActionMenu.requestKindVariable:
                WorkflowRequestKind.configurationMutationReturn.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func closeModifier(
        _ stateJSON: String
    ) -> ScriptFilterMods {
        ScriptFilterMods(command: ScriptFilterModifier(
            arg: stateJSON,
            subtitle: "Apply and close",
            valid: true,
            variables: mutationVariables(stateJSON)
        ))
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private enum PipelineAddParser {
    static func parse(_ value: String) -> PipelineAddRequest? {
        let parts = value.components(separatedBy: "=>")
        guard parts.count >= 2 else {
            return nil
        }
        let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = parts.dropFirst().joined(separator: "=>")
        guard !name.isEmpty else {
            return nil
        }

        guard let split = PipelineSyntax.splitOptions(from: remainder),
              !split.steps.isEmpty else {
            return nil
        }

        var fileType: PipelineFileType?
        var sawAll = false
        var skipOptimisation = false
        var hideResult = false
        for rawOption in split.options.split(whereSeparator: \.isWhitespace) {
            switch rawOption.lowercased() {
            case "img", "image":
                guard fileType == nil, !sawAll else { return nil }
                fileType = .image
            case "vid", "video":
                guard fileType == nil, !sawAll else { return nil }
                fileType = .video
            case "aud", "audio":
                guard fileType == nil, !sawAll else { return nil }
                fileType = .audio
            case "pdf":
                guard fileType == nil, !sawAll else { return nil }
                fileType = .pdf
            case "all":
                guard fileType == nil, !sawAll else { return nil }
                sawAll = true
            case "skip":
                skipOptimisation = true
            case "hide":
                hideResult = true
            default:
                return nil
            }
        }

        return PipelineAddRequest(
            name: name,
            steps: split.steps,
            fileType: fileType,
            skipOptimisation: skipOptimisation,
            hideResult: hideResult
        )
    }

    static func guidanceIssue(for value: String) -> PipelineSyntax.GuidanceIssue? {
        let parts = value.components(separatedBy: "=>")
        guard parts.count >= 2 else {
            return nil
        }
        let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = parts.dropFirst().joined(separator: "=>")
        guard !name.isEmpty else {
            return PipelineSyntax.GuidanceIssue(
                title: "Name this pipeline",
                subtitle: "Use Name => steps ; img skip hide",
                detail: PipelineSyntax.syntaxReference(savedCreation: true)
            )
        }
        guard let split = PipelineSyntax.splitOptions(from: remainder) else {
            return PipelineSyntax.GuidanceIssue(
                title: "Add pipeline steps",
                subtitle: "Use Name => steps ; img skip hide",
                detail: PipelineSyntax.syntaxReference(savedCreation: true)
            )
        }

        if !split.options.isEmpty {
            let allowed = PipelineSyntax.optionNames.union([
                "img", "image", "vid", "video", "aud", "audio", "pdf", "all"
            ])
            if let invalid = split.options
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .first(where: { !allowed.contains($0.lowercased()) }) {
                return PipelineSyntax.GuidanceIssue(
                    title: "Unknown pipeline option \(invalid)",
                    subtitle: "Use img, vid, aud, pdf, all, skip, or hide",
                    detail: PipelineSyntax.syntaxReference(savedCreation: true)
                )
            }
        }

        return PipelineSyntax.guidanceIssue(for: split.steps)
    }
}
