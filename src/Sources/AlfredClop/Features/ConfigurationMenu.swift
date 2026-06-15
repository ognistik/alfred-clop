import Foundation

enum ConfigurationMenu {
    static let namespacePrefix = ":"
    static let templatePrefix = ":template "

    static func namespaceResponse(
        query: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter(),
        cache: ClipboardImageCache? = nil
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
            return withSettingsAffordance(
                menu(
                    store: store,
                    query: namespaceQuery,
                    environment: environment,
                    fileManager: fileManager,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    )
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
        cache: ClipboardImageCache? = nil
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
                    )
                )
            case .configurationOutputTemplate:
                response = outputTemplateMenu(
                    query: query,
                    store: store
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
                    )
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
                    )
                )
            case .configurationResetPresetsConfirmation:
                let count = try store.load().presets.count
                response = confirmation(
                    title: "Remove all \(count) saved action presets?",
                    subtitle: "Return confirms · Cannot be undone",
                    nextMode: .configurationResetPresets
                )
            case .configurationResetPresets:
                let count = try store.removeAllPresets()
                response = message(
                    title: "Removed \(count) action presets",
                    subtitle: "Output template and Alfred preferences unchanged"
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
        cache: ClipboardImageCache? = nil
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
            case .configurationCacheCleanup:
                let removed = (cache ?? ClipboardImageCache(
                    environment: environment,
                    fileManager: fileManager
                )).removeAll()
                message = "Cleared \(removed.fileCount) cached clipboard \(removed.fileCount == 1 ? "image" : "images")"
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

    private static func menu(
        store: PresetStore,
        query: String,
        environment: Environment,
        fileManager: FileManager,
        cache: ClipboardImageCache
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
            items.append(removePresetsItem(count: document.presets.count))
        }

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
            subtitle: "\(templateExample(template)) · ⌘L reference",
            arg: stateJSON,
            valid: true,
            variables: mutationVariables(stateJSON),
            mods: stayOpenModifier(stateJSON)
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
                subtitle: "\(subtitle) · ⌘L reference"
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

    private static func removePresetsItem(count: Int) -> ScriptFilterItem {
        let stateJSON = encoded(.configuration(
            mode: .configurationResetPresetsConfirmation
        ))
        return ScriptFilterItem(
            title: "Remove all action presets",
            subtitle: "\(count) Saved \(count == 1 ? "Preset" : "Presets") across all action menus",
            arg: stateJSON,
            valid: true,
            autocomplete: ":remove presets",
            match: "remove reset delete action presets",
            variables: transitionVariables(stateJSON)
        )
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

    private static func confirmation(
        title: String,
        subtitle: String,
        nextMode: MenuMode
    ) -> ScriptFilterResponse {
        let stateJSON = encoded(.configuration(mode: nextMode))
        return ScriptFilterResponse(items: [
            ScriptFilterItem(
                title: title,
                subtitle: subtitle,
                arg: stateJSON,
                valid: true,
                variables: mutationVariables(stateJSON),
                mods: stayOpenModifier(stateJSON)
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
        let affordance = ScriptFilterAffordance.settingsFile(store.fileURL.path)
        var response = response
        response.items = response.items.map(affordance.apply)
        return response
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

    private static func mutationVariables(_ stateJSON: String) -> [String: String] {
        [
            ActionMenu.requestKindVariable:
                WorkflowRequestKind.configurationMutation.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func stayOpenModifier(
        _ stateJSON: String
    ) -> ScriptFilterMods {
        ScriptFilterMods(command: ScriptFilterModifier(
            arg: stateJSON,
            subtitle: "Apply · Return to Configuration",
            valid: true,
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.configurationMutationReturn.rawValue,
                ActionMenu.menuStateVariable: stateJSON
            ]
        ))
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
