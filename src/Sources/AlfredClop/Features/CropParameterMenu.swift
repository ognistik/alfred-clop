import Foundation

enum CropSizeKind: Equatable {
    case exactDimensions(width: Int, height: Int)
    case aspectRatio(width: Int, height: Int)
    case longEdge(Int)
    case fixedWidth(Int)
    case fixedHeight(Int)
}

struct CropSize: Equatable {
    var value: String
    var longEdge: Bool
    var kind: CropSizeKind
}

enum CropSizeParser {
    static func parse(_ input: String) -> CropSize? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if value.allSatisfy(\.isNumber),
           let edge = Int(value),
           edge > 0 {
            return CropSize(
                value: String(edge),
                longEdge: true,
                kind: .longEdge(edge)
            )
        }

        if value.first == "w",
           let width = positiveInteger(String(value.dropFirst())) {
            return CropSize(
                value: "\(width)x0",
                longEdge: false,
                kind: .fixedWidth(width)
            )
        }

        if value.first == "h",
           let height = positiveInteger(String(value.dropFirst())) {
            return CropSize(
                value: "0x\(height)",
                longEdge: false,
                kind: .fixedHeight(height)
            )
        }

        if let dimensions = components(of: value, separator: "x"),
           dimensions.count == 2,
           let width = Int(dimensions[0]),
           let height = Int(dimensions[1]),
           width >= 0,
           height >= 0,
           width + height > 0 {
            let kind: CropSizeKind
            if height == 0 {
                kind = .fixedWidth(width)
            } else if width == 0 {
                kind = .fixedHeight(height)
            } else {
                kind = .exactDimensions(width: width, height: height)
            }
            return CropSize(
                value: "\(width)x\(height)",
                longEdge: false,
                kind: kind
            )
        }

        if let ratio = components(of: value, separator: ":"),
           ratio.count == 2,
           let width = Int(ratio[0]),
           let height = Int(ratio[1]),
           width > 0,
           height > 0 {
            let divisor = greatestCommonDivisor(width, height)
            let normalizedWidth = width / divisor
            let normalizedHeight = height / divisor
            return CropSize(
                value: "\(normalizedWidth):\(normalizedHeight)",
                longEdge: false,
                kind: .aspectRatio(
                    width: normalizedWidth,
                    height: normalizedHeight
                )
            )
        }

        return nil
    }

    private static func positiveInteger(_ value: String) -> Int? {
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber),
              let number = Int(value),
              number > 0 else {
            return nil
        }
        return number
    }

    private static func components(
        of value: String,
        separator: Character
    ) -> [Substring]? {
        guard value.allSatisfy({ $0.isNumber || $0 == separator }) else {
            return nil
        }
        let components = value.split(
            separator: separator,
            omittingEmptySubsequences: false
        )
        return components.allSatisfy({ !$0.isEmpty }) ? components : nil
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var first = lhs
        var second = rhs
        while second != 0 {
            (first, second) = (second, first % second)
        }
        return first
    }
}

enum CropParameterMenu {
    static func response(
        stateJSON: String,
        query: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter()
    ) -> ScriptFilterResponse {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ),
        state.mode == .crop || state.mode == .cropPresetRemoval,
        let request = state.parameterRequest,
        request.step == "parameters",
        request.action == .crop,
        !request.inputs.isEmpty else {
            return error(
                title: "Unable to open Crop / Resize",
                subtitle: "The parameter menu state is invalid or incomplete."
            )
        }

        let store: PresetStore
        do {
            store = try PresetStore(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch {
            return storageErrorResponse(
                request: request,
                stateJSON: stateJSON,
                detail: storageErrorDetail(error)
            )
        }

        if let action = state.presetAction {
            switch action.kind {
            case .confirmRemoval:
                return removalConfirmation(
                    action: action,
                    request: request
                )
            case .save:
                let migrationStatus = PresetMigrationCoordinator(
                    environment: environment,
                    fileManager: fileManager,
                    writer: writer
                ).status()
                if migrationStatus.requiresResolutionBeforeSaving {
                    return pendingMigrationResponse(
                        request: request,
                        preset: action.preset,
                        migrationStatus: migrationStatus
                    )
                }
                do {
                    _ = try store.save(action.preset)
                    return menuResponse(
                        request: request,
                        stateJSON: try encodedState(.crop(request)),
                        query: presetDisplayValue(action.preset),
                        store: store
                    )
                } catch {
                    return storageErrorResponse(
                        request: request,
                        stateJSON: stateJSON,
                        detail: storageErrorDetail(error)
                    )
                }
            case .remove:
                do {
                    _ = try store.remove(action.preset)
                    return menuResponse(
                        request: request,
                        stateJSON: try encodedState(.crop(request)),
                        query: "",
                        store: store
                    )
                } catch {
                    return storageErrorResponse(
                        request: request,
                        stateJSON: stateJSON,
                        detail: storageErrorDetail(error)
                    )
                }
            }
        }

        return menuResponse(
            request: request,
            stateJSON: stateJSON,
            query: query,
            store: store
        )
    }

    private static func menuResponse(
        request: ParameterStepRequest,
        stateJSON: String,
        query: String,
        store: PresetStore
    ) -> ScriptFilterResponse {
        let presets: [CropActionPreset]
        do {
            presets = try store.load().presets
                .compactMap { preset in
                    guard case let .crop(crop) = preset else {
                        return nil
                    }
                    return crop
                }
                .sorted(by: presetDisplayOrder)
        } catch {
            return storageErrorResponse(
                request: request,
                stateJSON: stateJSON,
                detail: storageErrorDetail(error)
            )
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return ScriptFilterResponse(
                items: [instructionItem] + presets.compactMap {
                    presetItem(for: $0, request: request)
                },
                variables: preservedVariables(
                    for: request,
                    stateJSON: stateJSON
                ),
                skipKnowledge: true
            )
        }

        let matchingPresets = presets.filter {
            presetMatchesQuery($0, query: trimmedQuery)
        }
        var items = [ScriptFilterItem]()

        if let size = CropSizeParser.parse(trimmedQuery) {
            let candidate = CropActionPreset(size: size)
            if let exactPreset = presets.first(where: { $0 == candidate }) {
                if let item = interpretedItem(
                    for: size,
                    request: request,
                    savedPreset: exactPreset
                ) {
                    items.append(item)
                }
            } else if matchingPresets.isEmpty {
                if let item = interpretedItem(
                    for: size,
                    request: request,
                    savedPreset: nil
                ) {
                    items.append(item)
                }
            }
        } else if matchingPresets.isEmpty {
            items.append(ScriptFilterItem(
                title: "Invalid crop or resize value",
                subtitle: "Use 1200x630, 16:9, 1920, w128, or h720.",
                arg: "",
                valid: false
            ))
        }

        if items.isEmpty {
            items.append(contentsOf: matchingPresets.compactMap {
                presetItem(for: $0, request: request)
            })
        }

        return ScriptFilterResponse(
            items: items,
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func presetMatchesQuery(
        _ preset: CropActionPreset,
        query: String
    ) -> Bool {
        let normalizedQuery = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        return [preset.displayValue, preset.size].contains { value in
            value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            ).contains(normalizedQuery)
        }
    }

    private static func interpretedItem(
        for size: CropSize,
        request: ParameterStepRequest,
        savedPreset: CropActionPreset?
    ) -> ScriptFilterItem? {
        let preset = CropActionPreset(size: size)
        guard let argument = operationArgument(for: preset, request: request) else {
            return nil
        }

        let title: String
        let interpretation: String
        switch size.kind {
        case let .exactDimensions(width, height):
            title = "Use \(width)x\(height)"
            interpretation = "Crop / resize to exact dimensions \(width)x\(height)"
        case let .aspectRatio(width, height):
            title = "Use \(width):\(height)"
            interpretation = "Crop to aspect ratio \(width):\(height)"
        case let .longEdge(edge):
            title = "Use long edge \(edge)"
            interpretation = "Resize the long edge to \(edge)"
        case let .fixedWidth(width):
            title = "Width \(width), auto height"
            interpretation = "Resize to fixed width \(width) with calculated height"
        case let .fixedHeight(height):
            title = "Height \(height), auto width"
            interpretation = "Resize to fixed height \(height) with calculated width"
        }

        return ScriptFilterItem(
            uid: savedPreset?.stableUID,
            title: title,
            subtitle: [
                "\(request.inputContext.subtitlePrefix): \(interpretation)",
                savedPreset == nil ? nil : "Saved preset"
            ].compactMap(\.self).joined(separator: " - "),
            arg: argument,
            valid: true,
            autocomplete: preset.displayValue,
            match: "\(preset.displayValue) \(preset.size)",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            mods: ScriptFilterMods(
                control: presetModifier(
                    kind: savedPreset == nil ? .save : .confirmRemoval,
                    preset: preset,
                    request: request
                )
            )
        )
    }

    private static func presetItem(
        for preset: CropActionPreset,
        request: ParameterStepRequest
    ) -> ScriptFilterItem? {
        guard let argument = operationArgument(for: preset, request: request) else {
            return nil
        }

        return ScriptFilterItem(
            uid: preset.stableUID,
            title: preset.displayValue,
            subtitle: "\(request.inputContext.subtitlePrefix): \(interpretation(for: preset.cropSize)) - Saved preset",
            arg: argument,
            valid: true,
            autocomplete: preset.displayValue,
            match: "\(preset.displayValue) \(preset.size)",
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            mods: ScriptFilterMods(
                control: presetModifier(
                    kind: .confirmRemoval,
                    preset: preset,
                    request: request
                )
            )
        )
    }

    private static func removalConfirmation(
        action: PresetMenuAction,
        request: ParameterStepRequest
    ) -> ScriptFilterResponse {
        let state = MenuState.crop(
            request,
            action: PresetMenuAction(
                kind: .remove,
                preset: action.preset
            )
        )
        let stateJSON = (try? encodedState(state)) ?? ""

        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Remove saved preset \(presetDisplayValue(action.preset))?",
                    subtitle: "Press Return to confirm removal. This cannot be undone.",
                    arg: stateJSON,
                    valid: true,
                    variables: transitionVariables(
                        stateJSON: stateJSON,
                        request: request
                    )
                )
            ],
            variables: preservedVariables(
                for: request,
                stateJSON: stateJSON
            ),
            skipKnowledge: true
        )
    }

    private static func operationArgument(
        for preset: CropActionPreset,
        request: ParameterStepRequest
    ) -> String? {
        try? JSONOutput.string(
            for: OperationRequest(
                inputs: request.inputs,
                action: .crop(
                    size: preset.size,
                    smartCrop: false,
                    longEdge: preset.longEdge
                ),
                execution: defaultExecutionOptions
            ),
            prettyPrinted: false
        )
    }

    private static func presetModifier(
        kind: PresetMenuActionKind,
        preset: CropActionPreset,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let state = MenuState.crop(
            request,
            action: PresetMenuAction(
                kind: kind,
                preset: .crop(preset)
            )
        )
        let stateJSON = (try? encodedState(state)) ?? ""
        let subtitle = kind == .save
            ? "Save \(preset.displayValue) as a preset"
            : "Remove saved preset \(preset.displayValue)"

        return ScriptFilterModifier(
            arg: stateJSON,
            subtitle: subtitle,
            valid: true,
            variables: transitionVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
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

    private static var instructionItem: ScriptFilterItem {
        ScriptFilterItem(
            title: "Type crop or resize parameters",
            subtitle: "Examples: 1200x630, 16:9, 1920, w128, h720",
            arg: "",
            valid: false
        )
    }

    private static func interpretation(for size: CropSize) -> String {
        switch size.kind {
        case let .exactDimensions(width, height):
            return "Crop / resize to exact dimensions \(width)x\(height)"
        case let .aspectRatio(width, height):
            return "Crop to aspect ratio \(width):\(height)"
        case let .longEdge(edge):
            return "Resize the long edge to \(edge)"
        case let .fixedWidth(width):
            return "Resize to fixed width \(width) with calculated height"
        case let .fixedHeight(height):
            return "Resize to fixed height \(height) with calculated width"
        }
    }

    private static func presetDisplayValue(_ preset: ActionPreset) -> String {
        switch preset {
        case let .crop(crop):
            return crop.displayValue
        }
    }

    private static func presetDisplayOrder(
        _ lhs: CropActionPreset,
        _ rhs: CropActionPreset
    ) -> Bool {
        let comparison = lhs.displayValue.localizedStandardCompare(
            rhs.displayValue
        )
        if comparison == .orderedSame {
            return lhs.size < rhs.size
        }
        return comparison == .orderedAscending
    }

    private static func encodedState(_ state: MenuState) throws -> String {
        try JSONOutput.string(for: state, prettyPrinted: false)
    }

    private static func preservedVariables(
        for request: ParameterStepRequest,
        stateJSON: String
    ) -> [String: String] {
        [
            ActionMenu.inputJSONVariable: (try? JSONOutput.string(
                for: MenuInput(paths: request.inputs),
                prettyPrinted: false
            )) ?? "",
            ActionMenu.inputContextVariable: request.inputContext.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func storageErrorResponse(
        request: ParameterStepRequest,
        stateJSON: String,
        detail: String
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(
            items: [
                instructionItem,
                ScriptFilterItem(
                    title: "Unable to read saved presets",
                    subtitle: detail,
                    arg: "",
                    valid: false
                )
            ],
            variables: preservedVariables(
                for: request,
                stateJSON: stateJSON
            ),
            skipKnowledge: true
        )
    }

    private static func pendingMigrationResponse(
        request: ParameterStepRequest,
        preset: ActionPreset,
        migrationStatus: PresetMigrationStatus
    ) -> ScriptFilterResponse {
        guard case let .available(migration) = migrationStatus else {
            return ScriptFilterResponse(
                items: [
                    ScriptFilterItem(
                        title: "Resolve the settings location first",
                        subtitle: "Settings exist in both locations. No new preset was saved.",
                        arg: "",
                        valid: false
                    )
                ],
                variables: preservedVariables(
                    for: request,
                    stateJSON: (try? encodedState(.crop(request))) ?? ""
                ),
                skipKnowledge: true
            )
        }

        let migrationRequest = PresetMigrationRequest(
            sourcePath: migration.sourceURL.path,
            destinationPath: migration.destinationURL.path,
            inputs: request.inputs,
            mediaKinds: [],
            inputContext: request.inputContext,
            presetSaveContinuation: PresetSaveContinuation(
                request: request,
                preset: preset,
                query: presetDisplayValue(preset)
            )
        )
        let state = MenuState.presetMigration(migrationRequest)
        let stateJSON = (try? encodedState(state)) ?? ""
        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Move existing settings",
                    subtitle: "Move them now, then save \(presetDisplayValue(preset)) as a preset.",
                    arg: stateJSON,
                    valid: true,
                    variables: ActionMenu.migrationVariables(
                        stateJSON: stateJSON,
                        request: migrationRequest
                    )
                )
            ],
            variables: ActionMenu.migrationVariables(
                stateJSON: stateJSON,
                request: migrationRequest
            ),
            skipKnowledge: true
        )
    }

    private static func storageErrorDetail(_ error: Error) -> String {
        switch error {
        case PresetStoreError.missingWorkflowDataDirectory:
            return "Alfred did not provide a workflow data directory."
        case PresetStoreError.unsupportedVersion:
            return "presets.json uses an unsupported schema version."
        case PresetStoreError.invalidFile:
            return "presets.json is malformed or contains unsupported presets."
        default:
            return error.localizedDescription
        }
    }

    private static var defaultExecutionOptions: ExecutionOptions {
        ExecutionOptions(
            showClopUI: true,
            copyResult: false,
            output: .inPlace,
            backup: .trustClop,
            adaptiveOptimisation: nil,
            pdfDPI: nil
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

private extension PresetMigrationStatus {
    var requiresResolutionBeforeSaving: Bool {
        switch self {
        case .available, .conflict:
            return true
        case .none, .sourceMissing, .sourceInvalid, .metadataInvalid:
            return false
        }
    }

}
