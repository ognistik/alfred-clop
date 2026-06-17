import Foundation

struct DownscaleFactor: Equatable {
    var factor: Double
    var displayValue: String
    var factorValue: String
}

enum DownscaleFactorParser {
    static func parse(_ input: String) -> DownscaleFactor? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        let factor: Double
        if value.hasSuffix("%") {
            let percentText = String(value.dropLast())
            guard let percent = Double(percentText),
                  percent > 0,
                  percent < 100 else {
                return nil
            }
            factor = percent / 100
        } else if value.allSatisfy(\.isNumber),
                  let percent = Int(value),
                  percent > 1,
                  percent < 100 {
            factor = Double(percent) / 100
        } else if value.contains("."),
                  let parsed = Double(value),
                  isSupported(parsed) {
            factor = parsed
        } else {
            return nil
        }

        guard isSupported(factor) else {
            return nil
        }

        return DownscaleFactor(
            factor: factor,
            displayValue: displayValue(for: factor),
            factorValue: factorValue(for: factor)
        )
    }

    static func isSupported(_ factor: Double) -> Bool {
        factor.isFinite && factor > 0 && factor < 1
    }

    static func displayValue(for factor: Double) -> String {
        let percent = factor * 100
        return "\(trimmed(percent))%"
    }

    static func factorValue(for factor: Double) -> String {
        trimmed(factor)
    }

    private static func trimmed(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct DownscaleControls: Equatable {
    var factor: DownscaleFactor
    var adaptiveOptimisation: CropAdaptiveOptimisation?
    var removeAudio: Bool
}

enum DownscaleControlParser {
    static func parse(_ input: String) -> DownscaleControls? {
        let tokens = tokenize(input)
        guard !tokens.isEmpty else {
            return nil
        }

        var factor: DownscaleFactor?
        var adaptiveOptimisation: CropAdaptiveOptimisation?
        var removeAudio = false
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            if let parsedFactor = DownscaleFactorParser.parse(token) {
                guard factor == nil else { return nil }
                factor = parsedFactor
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
            if token == "m" || token == "mu" || token == "mute" {
                guard !removeAudio else { return nil }
                removeAudio = true
                index += 1
                continue
            }
            return nil
        }

        guard let factor else {
            return nil
        }
        return DownscaleControls(
            factor: factor,
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
                "no-adaptive", "noadaptive", "m", "mu", "mute"
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
            || priorTokens.contains {
                DownscaleFactorParser.parse($0) != nil
            }
    }

    static func compactControlTokens(
        for controls: DownscaleControls
    ) -> [String] {
        [
            controls.adaptiveOptimisation.map {
                $0 == .enabled ? "ad" : "no-ad"
            },
            controls.removeAudio ? "m" : nil
        ].compactMap(\.self)
    }

    static func controlDescriptions(
        for controls: DownscaleControls
    ) -> [String] {
        [
            controls.adaptiveOptimisation.map {
                $0 == .enabled ? "Adaptive" : "No Adaptive"
            },
            controls.removeAudio ? "Mute Video" : nil
        ].compactMap(\.self)
    }

    static var largeTypeReference: String {
        """
        Downscale controls

        Use a factor or percentage:
        50
        50%
        0.5
        75%
        0.75

        Add optional controls after the factor:
        ad or adaptive
        m or mute

        Advanced:
        no-ad or no-adaptive explicitly disables adaptive optimization.

        Examples:
        50 ad
        75% mute
        0.5 no-ad
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

enum DownscaleParameterMenu {
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
        state.mode == .downscale || state.mode == .downscalePresetRemoval,
        let request = state.parameterRequest,
        request.step == "parameters",
        request.action == .downscale,
        !request.inputs.isEmpty else {
            return error(
                title: "Unable to open Downscale",
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
                return removalConfirmation(action: action, request: request)
            case .save:
                do {
                    _ = try store.save(action.preset)
                    return menuResponse(
                        request: request,
                        stateJSON: try encodedState(.downscale(request)),
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
                        stateJSON: try encodedState(.downscale(request)),
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
        let presets: [DownscaleActionPreset]
        do {
            presets = try store.load().presets.compactMap { preset in
                guard case let .downscale(downscale) = preset else { return nil }
                return downscale
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
                variables: preservedVariables(for: request, stateJSON: stateJSON),
                skipKnowledge: true
            )
        }

        let matchingPresets = presets.filter {
            presetMatchesQuery($0, query: trimmedQuery)
        }
        var items = [ScriptFilterItem]()

        if let controls = DownscaleControlParser.parse(trimmedQuery) {
            guard supportsControls(controls, request: request) else {
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
            let candidate = DownscaleActionPreset(controls: controls)
            let exactPreset = presets.first(where: { $0 == candidate })
            items.append(interpretedItem(
                for: controls,
                request: request,
                savedPreset: exactPreset,
                environment: environment
            ))
            items.append(contentsOf: matchingPresets
                .filter { $0 != exactPreset }
                .map {
                    presetItem(
                        for: $0,
                        request: request,
                        environment: environment
                    )
                })
        } else if DownscaleControlParser.isPossiblePrefix(trimmedQuery),
                  matchingPresets.isEmpty {
            items.append(partialControlsItem(request: request))
        } else if matchingPresets.isEmpty {
            items.append(ScriptFilterItem(
                title: "Invalid downscale factor",
                subtitle: [
                    inputDescription(for: request),
                    "Use 50 / 50% / 0.5",
                    "⌘L Reference"
                ].joined(separator: " · "),
                arg: "",
                valid: false,
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
        presets: [DownscaleActionPreset],
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
            items.append(contentsOf: matchingPresets.map {
                presetItem(
                    for: $0,
                    request: request,
                    environment: environment,
                    autocompletePrefix: controlsPrefix
                )
            })
        } else if let controls = DownscaleControlParser.parse(trimmedQuery) {
            guard supportsControls(controls, request: request) else {
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
            let candidate = DownscaleActionPreset(controls: controls)
            let exactPreset = presets.first(where: { $0 == candidate })
            items.append(interpretedItem(
                for: controls,
                request: request,
                savedPreset: exactPreset,
                environment: environment,
                autocompletePrefix: controlsPrefix
            ))
            items.append(contentsOf: matchingPresets
                .filter { $0 != exactPreset }
                .map {
                    presetItem(
                        for: $0,
                        request: request,
                        environment: environment,
                        autocompletePrefix: controlsPrefix
                    )
                })
        } else if DownscaleControlParser.isPossiblePrefix(trimmedQuery),
                  matchingPresets.isEmpty {
            items.append(partialControlsItem(request: request))
        } else if matchingPresets.isEmpty {
            items.append(invalidControlsItem(request: request))
        }

        if items.isEmpty && !matchingPresets.isEmpty {
            items.append(contentsOf: matchingPresets.map {
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

    private static func interpretedItem(
        for controls: DownscaleControls,
        request: ParameterStepRequest,
        savedPreset: DownscaleActionPreset?,
        environment: Environment,
        autocompletePrefix: String = ""
    ) -> ScriptFilterItem {
        let preset = DownscaleActionPreset(controls: controls)
        return ScriptFilterItem(
            uid: savedPreset?.stableUID,
            title: actionTitle(for: controls),
            subtitle: [
                inputDescription(for: request),
                savedPreset == nil ? "⌃↩ Save Preset" : "Saved Preset",
                savedPreset == nil ? nil : Optional("⌃↩ Remove Preset")
            ].compactMap(\.self).joined(separator: " · "),
            arg: operationArgument(
                for: preset,
                request: request,
                environment: environment
            ),
            valid: true,
            autocomplete: autocompletePrefix + preset.displayValue,
            match: "\(preset.displayValue) \(preset.stableFactor)",
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
            text: ScriptFilterText(largetype: largeTypeReference(for: request))
        )
    }

    private static func presetItem(
        for preset: DownscaleActionPreset,
        request: ParameterStepRequest,
        environment: Environment,
        autocompletePrefix: String = ""
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            uid: preset.stableUID,
            title: presetTitle(for: preset),
            subtitle: [
                inputDescription(for: request),
                "Saved Preset",
                "⌃↩ Remove Preset"
            ].joined(separator: " · "),
            arg: operationArgument(
                for: preset,
                request: request,
                environment: environment
            ),
            valid: true,
            autocomplete: autocompletePrefix + preset.displayValue,
            match: "\(preset.displayValue) \(preset.stableFactor)",
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
        let state = MenuState.downscale(
            request,
            action: PresetMenuAction(
                kind: .remove,
                preset: action.preset
            )
        )
        let stateJSON = (try? encodedState(state)) ?? ""
        let cancelStateJSON = (try? encodedState(.downscale(request))) ?? ""

        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Remove Preset \(presetDisplayValue(action.preset))?",
                    subtitle: "Return confirms · Cannot be undone",
                    arg: stateJSON,
                    valid: true,
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
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func operationArgument(
        for preset: DownscaleActionPreset,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager = .default,
        preserveOriginal: Bool? = nil
    ) -> String {
        let template = (try? PresetStore(
            environment: environment,
            fileManager: fileManager
        ).load().outputTemplate)
            ?? SettingsDocument.builtInOutputTemplate
        let execution = environment.executionOptions(
            outputTemplate: template,
            preserveOriginal: preserveOriginal
        )
        return (try? JSONOutput.string(
            for: OperationRequest(
                inputs: request.inputs,
                action: .downscale(
                    factor: preset.factor,
                    adaptiveOptimisation: preset.adaptiveOptimisation,
                    removeAudio: preset.removeAudio
                ),
                execution: execution
            ),
            prettyPrinted: false
        )) ?? ""
    }

    private static func operationModifiers(
        for preset: DownscaleActionPreset,
        request: ParameterStepRequest,
        environment: Environment,
        control: ScriptFilterModifier
    ) -> ScriptFilterMods {
        let preserve = environment.preserveOriginal
        let preserveText = preserve
            ? "Replace Originals"
            : "Output Template"

        func modifier(preserve: Bool, subtitle: String) -> ScriptFilterModifier {
            ScriptFilterModifier(
                arg: operationArgument(
                    for: preset,
                    request: request,
                    environment: environment,
                    preserveOriginal: preserve
                ),
                subtitle: "\(inputDescription(for: request)) · \(subtitle)",
                valid: true,
                variables: [
                    ActionMenu.requestKindVariable:
                        WorkflowRequestKind.operation.rawValue
                ]
            )
        }

        return ScriptFilterMods(
            control: control,
            shift: modifier(
                preserve: !preserve,
                subtitle: preserveText
            )
        )
    }

    private static func presetModifier(
        kind: PresetMenuActionKind,
        preset: DownscaleActionPreset,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let state = MenuState.downscale(
            request,
            action: PresetMenuAction(
                kind: kind,
                preset: .downscale(preset)
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

    private static func presetMatchesQuery(
        _ preset: DownscaleActionPreset,
        query: String
    ) -> Bool {
        let normalizedQuery = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        let haystack = [
            preset.displayValue,
            preset.stableFactor,
            DownscaleControlParser.compactControlTokens(for: preset.controls)
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
        return [preset.displayValue, preset.stableFactor].contains { value in
            value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            ).contains(normalizedQuery)
        }
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

    private static func instructionItem(
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Type a downscale factor",
            subtitle: "Examples: 50 / 50% / 0.5 / 75% / 0.75 · ⇥ Controls, ⌃↩ Save Preset",
            arg: "",
            valid: false,
            autocomplete: controlsPrefix,
            mods: ScriptFilterMods(
                control: controlsModifier(
                    request: request,
                    stateJSON: stateJSON
                )
            )
        )
    }

    private static func controlsInstructionItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Type downscale controls",
            subtitle: [
                inputDescription(for: request),
                controlsHelp(for: request),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func partialControlsItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Type downscale controls",
            subtitle: [
                inputDescription(for: request),
                controlsHelp(for: request),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func invalidControlsItem(
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Invalid downscale controls",
            subtitle: [
                inputDescription(for: request),
                controlsHelp(for: request),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
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
            text: ScriptFilterText(
                largetype: largeTypeReference(for: request)
            )
        )
    }

    private static func actionTitle(for controls: DownscaleControls) -> String {
        (["Downscale to \(controls.factor.displayValue)"]
            + DownscaleControlParser.controlDescriptions(for: controls))
            .joined(separator: " · ")
    }

    private static func presetTitle(
        for preset: DownscaleActionPreset
    ) -> String {
        actionTitle(for: preset.controls)
    }

    private static func controlsHelp(
        for request: ParameterStepRequest
    ) -> String {
        supportsMuteControl(for: request)
            ? "Use factor + ad + m"
            : "Use factor + ad"
    }

    private static var downscaleReference: String {
        """
        Downscale controls

        Use a factor or percentage:
        50
        50%
        0.5
        75%
        0.75

        Add optional controls after the factor:
        ad or adaptive
        m or mute

        Advanced:
        no-ad or no-adaptive explicitly disables adaptive optimization.

        Examples:
        50 ad
        75% mute
        0.5 no-ad

        Values must be greater than 0 and less than 100%.
        """
    }

    private static func largeTypeReference(
        for request: ParameterStepRequest
    ) -> String {
        ScriptFilterAffordance.referenceLargeType(
            downscaleReference,
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
        _ preset: DownscaleActionPreset,
        request: ParameterStepRequest
    ) -> Bool {
        guard preset.removeAudio else {
            return true
        }
        return supportsMuteControl(for: request)
    }

    private static func supportsControls(
        _ controls: DownscaleControls,
        request: ParameterStepRequest
    ) -> Bool {
        guard controls.removeAudio else {
            return true
        }
        return supportsMuteControl(for: request)
    }

    private static func controlsQueryValue(from query: String) -> String? {
        let marker = "controls:"
        guard query.lowercased().hasPrefix(marker) else {
            return nil
        }
        return String(query.dropFirst(marker.count))
    }

    private static func presetDisplayValue(_ preset: ActionPreset) -> String {
        switch preset {
        case let .crop(crop):
            return crop.displayValue
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

    private static func presetDisplayOrder(
        _ lhs: DownscaleActionPreset,
        _ rhs: DownscaleActionPreset
    ) -> Bool {
        lhs.factor < rhs.factor
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
            variables: preservedVariables(for: request, stateJSON: stateJSON),
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
