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
        let request = state.presetMigration,
        !request.inputs.isEmpty,
        !request.mediaKinds.isEmpty else {
            return error(
                title: "Unable to move presets",
                subtitle: "The preset migration state is invalid or incomplete."
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
        case .actions, .crop, .cropPresetRemoval:
            return error(
                title: "Unable to move presets",
                subtitle: "The preset migration state is invalid."
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
                    title: "Move presets?",
                    subtitle: "From \(request.sourcePath) to \(request.destinationPath). Press Return to confirm.",
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
                    title: "Unable to move presets",
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
