import Foundation

enum ConfigurationMenu {
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
            let resolution = PresetMigrationCoordinator(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            ).resolution()
            if isSettingsMutation(state.mode),
               case .fallback = resolution {
                return error(
                    "Resolve the settings location first",
                    "Move existing settings or start with new settings in Configuration."
                )
            }
            switch state.mode {
            case .configuration:
                return menu(
                    store: store,
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    )
                )
            case .configurationStartFreshConfirmation:
                return confirmation(
                    title: "Start with new settings?",
                    subtitle: "Create defaults here and leave the previous file unchanged.",
                    nextMode: .configurationStartFresh
                )
            case .configurationStartFresh:
                try PresetMigrationCoordinator(
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer
                ).startFresh()
                return menu(
                    store: store,
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    )
                )
            case .configurationOutputTemplate:
                return outputTemplateMenu(
                    query: query,
                    store: store
                )
            case .configurationSaveOutput:
                try store.updateOutputTemplate(state.configurationValue ?? "")
                return menu(
                    store: store,
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    )
                )
            case .configurationResetOutputConfirmation:
                return confirmation(
                    title: "Reset output template?",
                    subtitle: "Restore \(SettingsDocument.builtInOutputTemplate). Presets and Alfred preferences are unchanged.",
                    nextMode: .configurationResetOutput
                )
            case .configurationResetOutput:
                try store.updateOutputTemplate(SettingsDocument.builtInOutputTemplate)
                return menu(
                    store: store,
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    )
                )
            case .configurationResetPresetsConfirmation:
                let count = try store.load().presets.count
                return confirmation(
                    title: "Remove all \(count) saved action presets?",
                    subtitle: "Press Return to confirm global removal. This cannot be undone.",
                    nextMode: .configurationResetPresets
                )
            case .configurationResetPresets:
                let count = try store.removeAllPresets()
                return message(
                    title: "Removed \(count) action presets",
                    subtitle: "The output template and Alfred preferences were unchanged."
                )
            case .configurationCacheCleanupConfirmation:
                let activeCache = cache ?? ClipboardImageCache(
                    environment: environment,
                    fileManager: fileManager
                )
                let summary = activeCache.summary()
                return confirmation(
                    title: "Remove \(summary.fileCount) cached clipboard images?",
                    subtitle: "Reclaim \(formattedBytes(summary.byteCount)). Press Return to confirm.",
                    nextMode: .configurationCacheCleanup
                )
            case .configurationCacheCleanup:
                let removed = (cache ?? ClipboardImageCache(
                    environment: environment,
                    fileManager: fileManager
                )).removeAll()
                return message(
                    title: "Removed \(removed.fileCount) cached clipboard images",
                    subtitle: "Reclaimed \(formattedBytes(removed.byteCount))."
                )
            default:
                return error(
                    "Unable to open Configuration",
                    "The menu state does not belong to Configuration."
                )
            }
        } catch let caughtError {
            return error(
                "Unable to update settings",
                caughtError.localizedDescription
            )
        }
    }

    static var actionItem: ScriptFilterItem {
        let stateJSON = encoded(.configuration())
        return ScriptFilterItem(
            uid: "action.configuration",
            title: "Configuration",
            subtitle: "Output template, presets, and maintenance · ⌘⏎ Workflow settings",
            arg: stateJSON,
            valid: true,
            autocomplete: "Configuration",
            match: "configuration settings output template cache cleanup migrate",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.parameterStep.rawValue,
                ActionMenu.menuStateVariable: stateJSON
            ],
            mods: ScriptFilterMods(command: ScriptFilterModifier(
                arg: "",
                subtitle: "Open workflow settings",
                valid: true,
                variables: [
                    ActionMenu.requestKindVariable:
                        WorkflowRequestKind.workflowSettings.rawValue
                ]
            ))
        )
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
            let resolution = PresetMigrationCoordinator(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            ).resolution()
            if isSettingsMutation(state.mode),
               case .fallback = resolution {
                return environment.errorNotifications
                    ? "Unable to update settings: Resolve the settings location first."
                    : nil
            }
            let message: String
            switch state.mode {
            case .configurationStartFresh:
                try PresetMigrationCoordinator(
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer
                ).startFresh()
                message = "Started with new settings"
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
        environment: Environment,
        fileManager: FileManager,
        writer: any AtomicDataWriting,
        cache: ClipboardImageCache
    ) -> ScriptFilterResponse {
        let coordinator = PresetMigrationCoordinator(
            environment: environment,
            fileManager: fileManager,
            writer: writer
        )
        let resolution = coordinator.resolution()
        if case .failure(let caughtError) = resolution {
            return error(
                "Unable to read settings",
                caughtError.localizedDescription
            )
        }
        let document = resolution.documentForExecution ?? SettingsDocument()

        if case .fallback(_, let migration) = resolution {
            var items = [
                moveItem(
                    migration: migration,
                    selection: InputSelection(inputs: [], mediaKinds: []),
                    context: .arguments
                ),
                startFreshItem(),
                ScriptFilterItem(
                    title: "Output Template",
                    subtitle: "Using previous settings until this location is resolved",
                    arg: "",
                    valid: false
                )
            ]
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
                    variables: transitionVariables(stateJSON)
                ))
            }
            return ScriptFilterResponse(items: items)
        }

        let outputState = encoded(.configuration(
            mode: .configurationOutputTemplate
        ))
        var items = [
            ScriptFilterItem(
                title: "Output Template",
                subtitle: templateExample(document.outputTemplate),
                arg: outputState,
                valid: true,
                match: "output template preserve original path filename",
                variables: transitionVariables(outputState)
            )
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
                variables: transitionVariables(stateJSON)
            ))
        }
        return ScriptFilterResponse(items: items)
    }

    private static func moveItem(
        migration: PresetMigration,
        selection: InputSelection,
        context: ActionInputContext
    ) -> ScriptFilterItem {
        ActionMenu.presetMigrationItem(
            status: .available(migration),
            selection: selection,
            context: context,
            requiresConfirmation: false
        )!
    }

    private static func startFreshItem() -> ScriptFilterItem {
        let stateJSON = encoded(.configuration(
            mode: .configurationStartFreshConfirmation
        ))
        return ScriptFilterItem(
            title: "Start with new settings",
            subtitle: "Create default settings here and keep the previous file",
            arg: stateJSON,
            valid: true,
            variables: transitionVariables(stateJSON)
        )
    }

    private static func isSettingsMutation(_ mode: MenuMode) -> Bool {
        switch mode {
        case .configurationSaveOutput, .configurationResetOutput,
             .configurationResetPresets:
            return true
        default:
            return false
        }
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
            variables: mutationVariables(stateJSON)
        )
    }

    private static func templateReferenceItem(
        title: String,
        subtitle: String,
        arg: String? = "",
        valid: Bool = false,
        variables: [String: String]? = nil
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: title,
            subtitle: subtitle,
            arg: arg,
            valid: valid,
            variables: variables,
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
            variables: transitionVariables(resetState)
        )
    }

    private static func removePresetsItem(count: Int) -> ScriptFilterItem {
        let stateJSON = encoded(.configuration(
            mode: .configurationResetPresetsConfirmation
        ))
        return ScriptFilterItem(
            title: "Remove all action presets",
            subtitle: "\(count) saved \(count == 1 ? "preset" : "presets") across all action menus",
            arg: stateJSON,
            valid: true,
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
                variables: mutationVariables(stateJSON)
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

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
