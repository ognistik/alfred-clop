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
            subtitle: "Output template, settings migration, and cache maintenance",
            arg: stateJSON,
            valid: true,
            autocomplete: "Configuration",
            match: "configuration settings output template cache cleanup migrate",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.parameterStep.rawValue,
                ActionMenu.menuStateVariable: stateJSON
            ]
        )
    }

    private static func menu(
        store: PresetStore,
        environment: Environment,
        fileManager: FileManager,
        writer: any AtomicDataWriting,
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

        let migrationStatus = PresetMigrationCoordinator(
            environment: environment,
            fileManager: fileManager,
            writer: writer
        ).status()
        if let migration = ActionMenu.presetMigrationItem(
            status: migrationStatus,
            selection: InputSelection(inputs: [], mediaKinds: []),
            context: .arguments,
            requiresConfirmation: false
        ) {
            items.insert(migration, at: 0)
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
                ScriptFilterItem(
                    title: "Current template",
                    subtitle: templateExample(document.outputTemplate),
                    arg: "",
                    valid: false
                ),
                ScriptFilterItem(
                    title: "Template token reference",
                    subtitle: "Press Command-L to view available tokens",
                    arg: "",
                    valid: false,
                    text: ScriptFilterText(
                        copy: tokenReference,
                        largetype: tokenReference
                    )
                ),
                ScriptFilterItem(
                    title: "Type a suffix, prefix, or advanced template",
                    subtitle: "Examples: optimized or %P/Processed/%f",
                    arg: "",
                    valid: false
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
            return error(
                "Enter a name",
                "Type a suffix such as optimized or an advanced template."
            )
        }
        let suffix = "%P/%f-\(name)"
        let prefix = "%P/\(name)-%f"
        if let validation = OutputTemplateValidator.validate(suffix) {
            return error("Invalid output name", validation.localizedDescription)
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
            return error("Invalid output template", validation.localizedDescription)
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
        return ScriptFilterItem(
            title: title,
            subtitle: templateExample(template),
            arg: stateJSON,
            valid: true,
            variables: transitionVariables(stateJSON)
        )
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
            homeDirectory: "/Users/me"
        ) ?? template
        let friendly = preview.replacingOccurrences(
            of: "/Users/me",
            with: "~"
        )
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
                variables: transitionVariables(stateJSON)
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

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
