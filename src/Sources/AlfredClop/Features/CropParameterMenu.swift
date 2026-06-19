import Foundation

enum CropSizeKind: Equatable, Hashable {
    case exactDimensions(width: Int, height: Int)
    case aspectRatio(width: Int, height: Int)
    case longEdge(Int)
    case fixedWidth(Int)
    case fixedHeight(Int)
}

struct CropSize: Equatable, Hashable {
    var value: String
    var longEdge: Bool
    var kind: CropSizeKind
}

struct CropControls: Codable, Equatable, Hashable {
    var size: CropSize
    var smartCrop: Bool
    var adaptiveOptimisation: CropAdaptiveOptimisation?
    var removeAudio: Bool

    init(
        size: CropSize,
        smartCrop: Bool = false,
        adaptiveOptimisation: CropAdaptiveOptimisation? = nil,
        removeAudio: Bool = false
    ) {
        self.size = size
        self.smartCrop = smartCrop
        self.adaptiveOptimisation = adaptiveOptimisation
        self.removeAudio = removeAudio
    }

    enum CodingKeys: String, CodingKey {
        case size
        case longEdge
        case smartCrop
        case adaptiveOptimisation
        case removeAudio
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size.value, forKey: .size)
        try container.encode(size.longEdge, forKey: .longEdge)
        try container.encode(smartCrop, forKey: .smartCrop)
        try container.encodeIfPresent(
            adaptiveOptimisation,
            forKey: .adaptiveOptimisation
        )
        try container.encode(removeAudio, forKey: .removeAudio)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .size)
        let longEdge = try container.decode(Bool.self, forKey: .longEdge)
        guard let parsed = CropSizeParser.parse(value),
              parsed.value == value,
              parsed.longEdge == longEdge else {
            throw DecodingError.dataCorruptedError(
                forKey: .size,
                in: container,
                debugDescription: "Crop controls are not normalized or supported."
            )
        }
        size = parsed
        smartCrop = try container.decodeIfPresent(
            Bool.self,
            forKey: .smartCrop
        ) ?? false
        adaptiveOptimisation = try container.decodeIfPresent(
            CropAdaptiveOptimisation.self,
            forKey: .adaptiveOptimisation
        )
        removeAudio = try container.decodeIfPresent(
            Bool.self,
            forKey: .removeAudio
        ) ?? false
    }
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

enum CropControlParser {
    static func parse(_ input: String) -> CropControls? {
        let tokens = tokenize(input)
        guard !tokens.isEmpty else {
            return nil
        }

        var size: CropSize?
        var smartCrop = false
        var adaptiveOptimisation: CropAdaptiveOptimisation?
        var removeAudio = false
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            if let parsedSize = CropSizeParser.parse(token) {
                guard size == nil else { return nil }
                size = parsedSize
                index += 1
                continue
            }
            if token == "no", index + 1 < tokens.count,
               isAdaptiveToken(tokens[index + 1]) {
                guard adaptiveOptimisation == nil else { return nil }
                adaptiveOptimisation = .disabled
                index += 2
                continue
            }
            if token == "ad" || token == "adaptive" {
                guard adaptiveOptimisation == nil else { return nil }
                adaptiveOptimisation = .enabled
                index += 1
                continue
            }
            if token == "na" || token == "noad" || token == "no-ad"
                || token == "no-adaptive" || token == "noadaptive" {
                guard adaptiveOptimisation == nil else { return nil }
                adaptiveOptimisation = .disabled
                index += 1
                continue
            }
            if token == "smart", index + 1 < tokens.count,
               tokens[index + 1] == "crop" {
                guard !smartCrop else { return nil }
                smartCrop = true
                index += 2
                continue
            }
            if token == "sc" || token == "smart" || token == "smart-crop" {
                guard !smartCrop else { return nil }
                smartCrop = true
                index += 1
                continue
            }
            if token == "m" || token == "mu" || token == "mute" {
                guard !removeAudio else { return nil }
                removeAudio = true
                index += 1
                continue
            }
            return nil
        }

        guard let size else {
            return nil
        }
        return CropControls(
            size: size,
            smartCrop: smartCrop,
            adaptiveOptimisation: adaptiveOptimisation,
            removeAudio: removeAudio
        )
    }

    static func isPossiblePrefix(_ input: String) -> Bool {
        let tokens = tokenize(input)
        guard !tokens.isEmpty else {
            return false
        }
        let last = tokens[tokens.count - 1]
        guard isProperPrefix(
            last,
            of: [
                "ad", "adaptive", "na", "noad", "no-ad",
                "no-adaptive", "noadaptive", "sc", "smart", "smart-crop",
                "m", "mu", "mute"
            ]
        ) || last == "no" else {
            return false
        }
        let priorTokens = tokens.dropLast()
        guard !priorTokens.isEmpty else {
            return false
        }
        let priorText = priorTokens.joined(separator: " ")
        return parse(priorText) != nil
            || priorTokens.contains { CropSizeParser.parse($0) != nil }
    }

    static func displayValue(for controls: CropControls) -> String {
        CropActionPreset(controls: controls).displayValue
    }

    static func compactControlTokens(for controls: CropControls) -> [String] {
        [
            controls.smartCrop ? "sc" : nil,
            controls.adaptiveOptimisation.map {
                $0 == .enabled ? "ad" : "no-ad"
            },
            controls.removeAudio ? "m" : nil
        ].compactMap(\.self)
    }

    static func controlDescriptions(for controls: CropControls) -> [String] {
        [
            controls.smartCrop ? "Smart Crop" : nil,
            controls.adaptiveOptimisation.map {
                $0 == .enabled ? "Adaptive" : "No Adaptive"
            },
            controls.removeAudio ? "Mute" : nil
        ].compactMap(\.self)
    }

    static var largeTypeReference: String {
        """
        Crop / Resize controls

        Use a size:
        1200x630 exact crop
        16:9 aspect ratio
        1920 long edge
        w128 fixed width
        h720 fixed height

        Add optional controls after the size:
        sc or smart-crop
        ad or adaptive
        m or mute

        Advanced:
        no-ad or no-adaptive explicitly disables adaptive optimization.

        Examples:
        1200x630 sc ad
        16:9 sc m
        w128 mute
        """
    }

    private static func tokenize(_ input: String) -> [String] {
        input
            .lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func isAdaptiveToken(_ token: String) -> Bool {
        token == "ad" || token == "adaptive"
    }

    private static func isProperPrefix(
        _ token: String,
        of candidates: [String]
    ) -> Bool {
        guard !candidates.contains(token) else {
            return false
        }
        return !token.isEmpty
            && candidates.contains { candidate in
                candidate.hasPrefix(token) && candidate != token
            }
    }
}

enum CropParameterMenu {
    private static let controlsPrefix = "controls: "

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
                do {
                    _ = try store.save(action.preset)
                    return menuResponse(
                        request: request,
                        stateJSON: try encodedState(.crop(request)),
                        query: "",
                        store: store,
                        environment: environment,
                        fileManager: fileManager
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
                        store: store,
                        environment: environment,
                        fileManager: fileManager
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
            store: store,
            environment: environment,
            fileManager: fileManager
        )
    }

    private static func menuResponse(
        request: ParameterStepRequest,
        stateJSON: String,
        query: String,
        store: PresetStore,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let presets: [CropActionPreset]
        do {
            presets = try store.load().presets.compactMap { preset in
                guard case let .crop(crop) = preset else { return nil }
                return crop
            }
            .filter { supportsPreset($0, request: request) }
            .sorted(by: presetDisplayOrder)
        } catch {
            return storageErrorResponse(
                request: request,
                stateJSON: stateJSON,
                detail: storageErrorDetail(error)
            )
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let affordance = ScriptFilterAffordance.processingInputs(
            request.inputs,
            itemKinds: request.itemKinds
        )
        if let controlsQuery = controlsQueryValue(from: trimmedQuery) {
            return controlsResponse(
                request: request,
                stateJSON: stateJSON,
                query: controlsQuery,
                presets: presets,
                environment: environment,
                affordance: affordance
            )
        }
        guard !trimmedQuery.isEmpty else {
            let items = ([instructionItem(
                request: request,
                stateJSON: stateJSON
            )] + presets.compactMap {
                presetItem(for: $0, request: request, environment: environment)
            }).map(affordance.apply)
            return ScriptFilterResponse(
                items: items,
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

        if let controls = CropControlParser.parse(trimmedQuery) {
            guard supportsSmartCrop(for: controls) else {
                items.append(unsupportedSmartCropItem(request: request))
                return ScriptFilterResponse(
                    items: items.map(affordance.apply),
                    variables: preservedVariables(
                        for: request,
                        stateJSON: stateJSON
                    ),
                    skipKnowledge: true
                )
            }
            guard supportsMuteControl(for: controls, request: request) else {
                items.append(unsupportedMuteItem(request: request))
                return ScriptFilterResponse(
                    items: items.map(affordance.apply),
                    variables: preservedVariables(
                        for: request,
                        stateJSON: stateJSON
                    ),
                    skipKnowledge: true
                )
            }
            let candidate = CropActionPreset(controls: controls)
            let exactPreset = presets.first(where: { $0 == candidate })
            if let item = interpretedItem(
                for: controls,
                request: request,
                savedPreset: exactPreset,
                environment: environment
            ) {
                items.append(item)
            }
            items.append(contentsOf: matchingPresets
                .filter { $0 != exactPreset }
                .compactMap {
                    presetItem(
                        for: $0,
                        request: request,
                        environment: environment
                    )
                })
        } else if CropControlParser.isPossiblePrefix(trimmedQuery),
                  matchingPresets.isEmpty {
            items.append(ScriptFilterItem(
                title: "Type crop controls",
                subtitle: [
                    inputDescription(for: request),
                    controlsHelp(for: request),
                    "⌘L Reference"
                ].joined(separator: " · "),
                arg: "",
                valid: false,
                icon: WorkflowIcon.guide,
                text: ScriptFilterText(
                    largetype: largeTypeReference(for: request)
                )
            ))
        } else if matchingPresets.isEmpty {
            items.append(ScriptFilterItem(
                title: "Invalid crop or resize value",
                subtitle: [
                    inputDescription(for: request),
                    "Use 1200x630 / 16:9 / 1920 / w128 / h720",
                    "⌘L Reference"
                ].joined(separator: " · "),
                arg: "",
                valid: false,
                icon: WorkflowIcon.guide,
                text: ScriptFilterText(
                    largetype: largeTypeReference(for: request)
                )
            ))
        }

        if items.isEmpty && !matchingPresets.isEmpty {
            items.append(contentsOf: matchingPresets.compactMap {
                presetItem(for: $0, request: request, environment: environment)
            })
        }

        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func controlsResponse(
        request: ParameterStepRequest,
        stateJSON: String,
        query: String,
        presets: [CropActionPreset],
        environment: Environment,
        affordance: ScriptFilterAffordance
    ) -> ScriptFilterResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingPresets = trimmedQuery.isEmpty
            ? presets
            : presets.filter { presetMatchesQuery($0, query: trimmedQuery) }
        var items = [ScriptFilterItem]()

        if trimmedQuery.isEmpty {
            items.append(controlsInstructionItem(request: request))
            items.append(contentsOf: matchingPresets.compactMap {
                presetItem(
                    for: $0,
                    request: request,
                    environment: environment,
                    autocompletePrefix: controlsPrefix
                )
            })
        } else if let controls = CropControlParser.parse(trimmedQuery) {
            guard supportsSmartCrop(for: controls) else {
                items.append(unsupportedSmartCropItem(request: request))
                return ScriptFilterResponse(
                    items: items.map(affordance.apply),
                    variables: preservedVariables(
                        for: request,
                        stateJSON: stateJSON
                    ),
                    skipKnowledge: true
                )
            }
            guard supportsMuteControl(for: controls, request: request) else {
                items.append(unsupportedMuteItem(request: request))
                return ScriptFilterResponse(
                    items: items.map(affordance.apply),
                    variables: preservedVariables(
                        for: request,
                        stateJSON: stateJSON
                    ),
                    skipKnowledge: true
                )
            }
            let candidate = CropActionPreset(controls: controls)
            let exactPreset = presets.first(where: { $0 == candidate })
            if let item = interpretedItem(
                for: controls,
                request: request,
                savedPreset: exactPreset,
                environment: environment,
                autocompletePrefix: controlsPrefix
            ) {
                items.append(item)
            }
            items.append(contentsOf: matchingPresets
                .filter { $0 != exactPreset }
                .compactMap {
                    presetItem(
                        for: $0,
                        request: request,
                        environment: environment,
                        autocompletePrefix: controlsPrefix
                    )
                })
        } else if CropControlParser.isPossiblePrefix(trimmedQuery),
                  matchingPresets.isEmpty {
            items.append(partialControlsItem(request: request))
        } else if matchingPresets.isEmpty {
            items.append(invalidControlsItem(request: request))
        }

        if items.isEmpty && !matchingPresets.isEmpty {
            items.append(contentsOf: matchingPresets.compactMap {
                presetItem(
                    for: $0,
                    request: request,
                    environment: environment,
                    autocompletePrefix: controlsPrefix
                )
            })
        }

        return ScriptFilterResponse(
            items: items.map(affordance.apply),
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
        let haystack = [
            preset.displayValue,
            preset.size,
            CropControlParser.compactControlTokens(for: preset.controls)
                .joined(separator: " ")
        ].joined(separator: " ").folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        let queryTokens = normalizedQuery
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
        if queryTokens.count > 1 {
            return queryTokens.allSatisfy { haystack.contains($0) }
        }
        return [preset.displayValue, preset.size].contains { value in
            value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            ).contains(normalizedQuery)
        }
    }

    private static func interpretedItem(
        for controls: CropControls,
        request: ParameterStepRequest,
        savedPreset: CropActionPreset?,
        environment: Environment,
        autocompletePrefix: String = ""
    ) -> ScriptFilterItem? {
        let preset = CropActionPreset(controls: controls)
        guard let argument = operationArgument(
            for: preset,
            request: request,
            environment: environment
        ) else {
            return nil
        }

        let baseTitle: String
        switch controls.size.kind {
        case let .exactDimensions(width, height):
            baseTitle = "Crop to \(width)x\(height)"
        case let .aspectRatio(width, height):
            baseTitle = "Crop to \(width):\(height)"
        case let .longEdge(edge):
            baseTitle = "Long edge \(edge)"
        case let .fixedWidth(width):
            baseTitle = "Width \(width), auto height"
        case let .fixedHeight(height):
            baseTitle = "Height \(height), auto width"
        }
        let hints = rowHints(
            for: preset.cropSize,
            savedPreset: savedPreset != nil
        )
        let isSavedPreset = savedPreset != nil

        return ScriptFilterItem(
            uid: savedPreset?.stableUID,
            title: actionTitle(baseTitle: baseTitle, controls: controls),
            subtitle: [
                inputDescription(for: request),
                isSavedPreset ? "Saved Preset" : hints,
                isSavedPreset ? Optional("⌃↩ Remove Preset") : nil,
                "⌘L Reference"
            ].compactMap(\.self).joined(separator: " · "),
            arg: argument,
            valid: true,
            autocomplete: autocompletePrefix + preset.displayValue,
            match: "\(preset.displayValue) \(preset.size)",
            icon: savedPreset == nil ? nil : WorkflowIcon.preset,
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            mods: operationModifiers(
                for: preset,
                request: request,
                environment: environment,
                control: presetModifier(
                    kind: savedPreset == nil ? .save : .confirmRemoval,
                    preset: preset,
                    request: request
                )
            ),
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func presetItem(
        for preset: CropActionPreset,
        request: ParameterStepRequest,
        environment: Environment,
        autocompletePrefix: String = ""
    ) -> ScriptFilterItem? {
        guard let argument = operationArgument(
            for: preset,
            request: request,
            environment: environment
        ) else {
            return nil
        }

        return ScriptFilterItem(
            uid: preset.stableUID,
            title: presetTitle(for: preset),
            subtitle: [
                inputDescription(for: request),
                "Saved Preset",
                "⌃↩ Remove Preset"
            ].joined(separator: " · "),
            arg: argument,
            valid: true,
            autocomplete: autocompletePrefix + preset.displayValue,
            match: "\(preset.displayValue) \(preset.size)",
            icon: WorkflowIcon.preset,
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            mods: operationModifiers(
                for: preset,
                request: request,
                environment: environment,
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
        let cancelStateJSON = (try? encodedState(.crop(request))) ?? ""

        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Remove Preset \(presetDisplayValue(action.preset))?",
                    subtitle: "Return confirms · Cannot be undone",
                    arg: stateJSON,
                    valid: true,
                    icon: WorkflowIcon.destructive,
                    variables: transitionVariables(
                        stateJSON: stateJSON,
                        request: request
                    )
                ),
                ScriptFilterItem(
                    title: "Cancel",
                    subtitle: "Return keeps preset",
                    arg: cancelStateJSON,
                    valid: true,
                    variables: transitionVariables(
                        stateJSON: cancelStateJSON,
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
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager = .default,
        aggressive: Bool? = nil,
        preserveOriginal: Bool? = nil,
        smartCrop: Bool? = nil
    ) -> String? {
        let template = (try? PresetStore(
            environment: environment,
            fileManager: fileManager
        ).load().outputTemplate)
            ?? SettingsDocument.builtInOutputTemplate
        var execution = environment.executionOptions(
            outputTemplate: template,
            preserveOriginal: preserveOriginal
        )
        execution.aggressiveProcessing = aggressive ?? environment.aggressiveByDefault
        return try? JSONOutput.string(
            for: OperationRequest(
                inputs: request.inputs,
                action: .crop(
                    size: preset.size,
                    smartCrop: smartCrop ?? preset.smartCrop,
                    longEdge: preset.longEdge,
                    adaptiveOptimisation: preset.adaptiveOptimisation,
                    removeAudio: preset.removeAudio
                ),
                execution: execution
            ),
            prettyPrinted: false
        )
    }

    private static func operationModifiers(
        for preset: CropActionPreset,
        request: ParameterStepRequest,
        environment: Environment,
        control: ScriptFilterModifier
    ) -> ScriptFilterMods {
        let aggressive = environment.aggressiveByDefault
        let preserve = environment.preserveOriginal
        let commandText = aggressive
            ? "Standard"
            : "Aggressive"
        let preserveText = preserve
            ? "Replace Originals"
            : "Output Template"

        func modifier(
            aggressive: Bool,
            preserve: Bool,
            subtitle: String
        ) -> ScriptFilterModifier? {
            guard let arg = operationArgument(
                for: preset,
                request: request,
                environment: environment,
                aggressive: aggressive,
                preserveOriginal: preserve
            ) else {
                return nil
            }
            var operation = try? JSONDecoder().decode(
                OperationRequest.self,
                from: Data(arg.utf8)
            )
            operation?.execution.aggressiveProcessing = aggressive
            let resolvedArg = operation.flatMap {
                try? JSONOutput.string(for: $0, prettyPrinted: false)
            } ?? arg
            return ScriptFilterModifier(
                arg: resolvedArg,
                subtitle: "\(inputDescription(for: request)) · \(subtitle)",
                valid: true,
                variables: [
                    ActionMenu.requestKindVariable:
                        WorkflowRequestKind.operation.rawValue
                ]
            )
        }

        let command = modifier(
            aggressive: !aggressive,
            preserve: preserve,
            subtitle: commandText
        )
        let shift = modifier(
            aggressive: aggressive,
            preserve: !preserve,
            subtitle: preserveText
        )
        return ScriptFilterMods(
            command: command,
            option: nil,
            control: control,
            shift: shift,
            commandOption: nil,
            commandShift: modifier(
                aggressive: !aggressive,
                preserve: !preserve,
                subtitle: "\(commandText) · \(preserveText)"
            ),
            optionShift: nil,
            commandOptionShift: nil
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
        let title = presetTitle(for: preset)
        let subtitle = kind == .save
            ? "Save Preset \(title)"
            : "Remove Preset \(title)"

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

    private static func controlsModifier(
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterModifier {
        ScriptFilterModifier(
            arg: controlsPrefix,
            subtitle: "Save Preset",
            valid: true,
            variables: queryTransitionVariables(
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

    private static func instructionItem(
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Type crop or resize parameters",
            subtitle: "\(inputDescription(for: request)) · Examples: 1200x630 / 16:9 / 1920 / w128 / h720 · ⇥ Controls · ⌃↩ Save Preset",
            arg: "",
            valid: false,
            autocomplete: controlsPrefix,
            icon: WorkflowIcon.guide,
            mods: ScriptFilterMods(
                command: nil,
                option: nil,
                control: controlsModifier(
                    request: request,
                    stateJSON: stateJSON
                ),
                shift: nil,
                function: nil,
                commandOption: nil,
                commandShift: nil,
                optionShift: nil,
                commandOptionShift: nil
            )
        )
    }

    private static func controlsInstructionItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Type crop controls",
            subtitle: [
                inputDescription(for: request),
                controlsHelp(for: request),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func partialControlsItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Type crop controls",
            subtitle: [
                inputDescription(for: request),
                controlsHelp(for: request),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func invalidControlsItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Invalid crop controls",
            subtitle: [
                inputDescription(for: request),
                controlsHelp(for: request),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func unsupportedMuteItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Mute only applies to video",
            subtitle: [
                inputDescription(for: request),
                controlsHelp(for: request),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func unsupportedSmartCropItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Smart Crop needs dimensions or ratio",
            subtitle: [
                inputDescription(for: request),
                "Use 1200x630 sc / 16:9 sc",
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func interpretation(for size: CropSize) -> String {
        switch size.kind {
        case let .exactDimensions(width, height):
            return "Crop to \(width)x\(height)"
        case let .aspectRatio(width, height):
            return "Crop to \(width):\(height)"
        case let .longEdge(edge):
            return "Long edge \(edge)"
        case let .fixedWidth(width):
            return "Fixed width \(width)"
        case let .fixedHeight(height):
            return "Fixed height \(height)"
        }
    }

    private static func rowHints(
        for size: CropSize,
        savedPreset: Bool
    ) -> String {
        if savedPreset {
            return "⌃↩ Remove Preset"
        }
        switch size.kind {
        case .exactDimensions, .aspectRatio:
            return "⌃↩ Save Preset"
        case .longEdge, .fixedWidth, .fixedHeight:
            return "⌃↩ Save Preset"
        }
    }

    private static func presetDisplayValue(_ preset: ActionPreset) -> String {
        switch preset {
        case let .crop(crop):
            return presetTitle(for: crop)
        case let .downscale(downscale):
            return downscale.displayValue
        case let .conversion(conversion):
            return conversion.displayValue
        case let .optimize(optimize):
            return optimize.displayValue
        case let .cropPDF(cropPDF):
            return cropPDF.displayValue
        }
    }

    private static func presetTitle(for preset: CropActionPreset) -> String {
        actionTitle(
            baseTitle: actionDisplayValue(for: preset.cropSize),
            controls: preset.controls
        )
    }

    private static func actionTitle(
        baseTitle: String,
        controls: CropControls
    ) -> String {
        ([baseTitle] + titleControlDescriptions(for: controls))
            .joined(separator: " · ")
    }

    private static func titleControlDescriptions(
        for controls: CropControls
    ) -> [String] {
        [
            controls.smartCrop ? "Smart Crop" : nil,
            controls.adaptiveOptimisation.map {
                $0 == .enabled ? "Adaptive" : "No Adaptive"
            },
            controls.removeAudio ? "Mute Video" : nil
        ].compactMap(\.self)
    }

    private static func actionDisplayValue(for size: CropSize) -> String {
        switch size.kind {
        case let .exactDimensions(width, height):
            return "Crop to \(width)x\(height)"
        case let .aspectRatio(width, height):
            return "Crop to \(width):\(height)"
        case let .longEdge(edge):
            return "Long edge \(edge)"
        case let .fixedWidth(width):
            return "Width \(width), auto height"
        case let .fixedHeight(height):
            return "Height \(height), auto width"
        }
    }

    private static func controlsHelp(
        for request: ParameterStepRequest
    ) -> String {
        supportsMuteControl(for: request)
            ? "Use size + sc + ad + m"
            : "Use size + sc + ad"
    }

    private static var acceptedSizeSubtitle: String {
        "Examples: 1200x630 / 16:9 / 1920 / w128 / h720"
    }

    private static func largeTypeReference(
        for request: ParameterStepRequest
    ) -> String {
        ScriptFilterAffordance.referenceLargeType(
            CropControlParser.largeTypeReference,
            inputs: request.inputs
        )
    }

    private static func supportsMuteControl(
        for request: ParameterStepRequest
    ) -> Bool {
        if request.mediaKinds?.contains(.video) == true {
            return true
        }
        if request.ambiguousKinds?.isEmpty == false {
            return true
        }
        if request.itemKinds?.contains(where: {
            $0 == .folder || $0 == .remoteURL
        }) == true {
            return true
        }
        return request.mediaKinds == nil
    }

    private static func supportsPreset(
        _ preset: CropActionPreset,
        request: ParameterStepRequest
    ) -> Bool {
        guard !preset.smartCrop || supportsSmartCrop(for: preset.cropSize) else {
            return false
        }
        guard preset.removeAudio else {
            return true
        }
        return supportsMuteControl(for: request)
    }

    private static func supportsControls(
        _ controls: CropControls,
        request: ParameterStepRequest
    ) -> Bool {
        supportsSmartCrop(for: controls)
            && supportsMuteControl(for: controls, request: request)
    }

    private static func supportsSmartCrop(for controls: CropControls) -> Bool {
        guard controls.smartCrop else {
            return true
        }
        return supportsSmartCrop(for: controls.size)
    }

    private static func supportsMuteControl(
        for controls: CropControls,
        request: ParameterStepRequest
    ) -> Bool {
        guard controls.removeAudio else {
            return true
        }
        return supportsMuteControl(for: request)
    }

    private static func supportsSmartCrop(for size: CropSize) -> Bool {
        switch size.kind {
        case .exactDimensions, .aspectRatio:
            return true
        case .longEdge, .fixedWidth, .fixedHeight:
            return false
        }
    }

    private static func controlsQueryValue(from query: String) -> String? {
        let marker = "controls:"
        guard query.lowercased().hasPrefix(marker) else {
            return nil
        }
        return String(query.dropFirst(marker.count))
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
                for: MenuInput(
                    paths: request.inputs,
                    mediaKinds: request.mediaKinds,
                    itemKinds: request.itemKinds,
                    ambiguousKinds: request.ambiguousKinds,
                    processableItemCount: request.processableItemCount
                ),
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
                instructionItem(request: request, stateJSON: stateJSON),
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

    private static func storageErrorDetail(_ error: Error) -> String {
        switch error {
        case PresetStoreError.missingWorkflowDataDirectory:
            return "Alfred did not provide a workflow data directory."
        case PresetStoreError.unsupportedVersion:
            return "settings.json uses an unsupported schema version."
        case PresetStoreError.invalidFile:
            return "settings.json is malformed or contains unsupported data."
        default:
            return error.localizedDescription
        }
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

    private static func inputDescription(
        for request: ParameterStepRequest
    ) -> String {
        request.inputContext.inputDescription(
            inputs: request.inputs,
            itemKinds: request.itemKinds,
            ambiguousKinds: request.ambiguousKinds ?? [],
            processableItemCount: request.processableItemCount
        )
    }
}
