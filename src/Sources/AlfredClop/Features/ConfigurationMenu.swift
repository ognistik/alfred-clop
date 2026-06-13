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
                    query: query,
                    store: store,
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer,
                    cache: cache ?? ClipboardImageCache(
                        environment: environment,
                        fileManager: fileManager
                    )
                )
            case .configurationSaveOutput:
                try store.updateOutputTemplate(state.configurationValue ?? "")
                return menu(
                    query: "",
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
                    query: "",
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
        query: String,
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

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let validation = OutputTemplateValidator.validate(trimmed) {
                return error("Invalid output template", validation.localizedDescription)
            }
            let stateJSON = encoded(.configuration(
                mode: .configurationSaveOutput,
                value: trimmed
            ))
            return ScriptFilterResponse(items: [
                ScriptFilterItem(
                    title: "Use output template \(trimmed)",
                    subtitle: "Example: \(OutputTemplateValidator.preview(template: trimmed) ?? trimmed)",
                    arg: stateJSON,
                    valid: true,
                    variables: transitionVariables(stateJSON)
                )
            ])
        }

        var items = [
            ScriptFilterItem(
                title: "Set output template",
                subtitle: "Current: \(document.outputTemplate) · Tokens: %P folder, %f name, %e extension",
                arg: "",
                valid: false,
                autocomplete: document.outputTemplate,
                match: "set output template preserve original tokens folder filename"
            ),
            resetItem(presetCount: document.presets.count)
        ]

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

    private static func resetItem(presetCount: Int) -> ScriptFilterItem {
        let resetState = encoded(.configuration(
            mode: .configurationResetOutputConfirmation
        ))
        let presetsState = encoded(.configuration(
            mode: .configurationResetPresetsConfirmation
        ))
        return ScriptFilterItem(
            title: "Reset output template",
            subtitle: "Restore \(SettingsDocument.builtInOutputTemplate)",
            arg: resetState,
            valid: true,
            variables: transitionVariables(resetState),
            mods: ScriptFilterMods(command: ScriptFilterModifier(
                arg: presetsState,
                subtitle: "Reset all action presets (\(presetCount))",
                valid: true,
                variables: transitionVariables(presetsState)
            ))
        )
    }

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
