import Foundation

enum PresetMigrationMenu {
    static func response(
        stateJSON: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ),
        let request = state.presetMigration else {
            return error(
                title: "Unable to move existing settings",
                subtitle: "The settings migration state is invalid or incomplete."
            )
        }

        switch state.mode {
        case .presetMigrationConfirmation:
            return confirmation(request)
        case .presetMigration:
            return performMove(
                request,
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        case .actions, .crop, .cropPresetRemoval,
             .configurationStartFreshConfirmation, .configurationStartFresh,
             .configuration, .configurationOutputTemplate,
             .configurationSaveOutput,
             .configurationResetOutputConfirmation, .configurationResetOutput,
             .configurationResetPresetsConfirmation, .configurationResetPresets,
             .configurationCacheCleanupConfirmation, .configurationCacheCleanup:
            return error(
                title: "Unable to move existing settings",
                subtitle: "The settings migration state is invalid."
            )
        }
    }

    private static func confirmation(
        _ request: PresetMigrationRequest
    ) -> ScriptFilterResponse {
        let moveState = MenuState.presetMigration(request)
        let stateJSON = (try? JSONOutput.string(
            for: moveState,
            prettyPrinted: false
        )) ?? ""
        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Move existing settings?",
                    subtitle: "Move them to the newly configured location. Press Return to confirm.",
                    arg: stateJSON,
                    valid: true,
                    variables: ActionMenu.migrationVariables(
                        stateJSON: stateJSON,
                        request: request
                    )
                )
            ],
            variables: ActionMenu.migrationVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
    }

    private static func performMove(
        _ request: PresetMigrationRequest,
        environment: Environment,
        fileManager: FileManager,
        writer: any AtomicDataWriting
    ) -> ScriptFilterResponse {
        let coordinator = PresetMigrationCoordinator(
            environment: environment,
            fileManager: fileManager,
            writer: writer
        )
        do {
            try coordinator.move(PresetMigration(
                sourceURL: URL(fileURLWithPath: request.sourcePath),
                destinationURL: URL(fileURLWithPath: request.destinationPath)
            ))
            if let continuation = request.presetSaveContinuation {
                let saveState = MenuState.crop(
                    continuation.request,
                    action: PresetMenuAction(
                        kind: .save,
                        preset: continuation.preset
                    )
                )
                return CropParameterMenu.response(
                    stateJSON: (try? JSONOutput.string(
                        for: saveState,
                        prettyPrinted: false
                    )) ?? "",
                    query: continuation.query,
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer
                )
            }
            guard !request.inputs.isEmpty else {
                let message: (String, String)
                switch request.inputContext {
                case .clipboard:
                    message = (
                        "No supported clipboard content",
                        "Copy a supported file, folder, URL, or image and try again."
                    )
                case .arguments:
                    message = (
                        "No file paths provided",
                        "Pass one or more file paths to the external trigger."
                    )
                case .selected:
                    message = (
                        "No files selected",
                        "Run Clop from Universal Actions on one or more files."
                    )
                }
                return ActionMenu.responseWithoutInputs(
                    context: request.inputContext,
                    title: message.0,
                    subtitle: message.1,
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer
                )
            }
            return ActionMenu.response(
                for: InputSelection(
                    inputs: request.inputs,
                    mediaKinds: request.mediaKinds
                ),
                query: "",
                context: request.inputContext,
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch let error as PresetMigrationError {
            return failedMove(request, detail: ActionMenu.migrationErrorDetail(error))
        } catch {
            return failedMove(request, detail: error.localizedDescription)
        }
    }

    private static func failedMove(
        _ request: PresetMigrationRequest,
        detail: String
    ) -> ScriptFilterResponse {
        let state = MenuState.presetMigrationConfirmation(request)
        let stateJSON = (try? JSONOutput.string(
            for: state,
            prettyPrinted: false
        )) ?? ""
        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Unable to move existing settings",
                    subtitle: detail,
                    arg: "",
                    valid: false
                )
            ],
            variables: ActionMenu.migrationVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
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
