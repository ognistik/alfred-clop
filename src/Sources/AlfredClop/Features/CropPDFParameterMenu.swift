import Foundation

enum CropPDFParameterMenu {
    static func response(
        stateJSON: String,
        query: String,
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        writer: any AtomicDataWriting = FoundationAtomicDataWriter(),
        targetProvider: any CropPDFTargetProviding = CropPDFTargetProvider()
    ) -> ScriptFilterResponse {
        guard let state = try? JSONDecoder().decode(
            MenuState.self,
            from: Data(stateJSON.utf8)
        ),
        state.mode == .cropPDF || state.mode == .cropPDFPresetRemoval,
        let request = state.parameterRequest,
        request.step == "parameters",
        request.action == .cropPDF,
        !request.inputs.isEmpty else {
            return error(
                title: "Unable to open Crop PDF",
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
            return Self.error(
                title: "Unable to read saved presets",
                subtitle: error.localizedDescription
            )
        }

        if let action = state.presetAction {
            switch action.kind {
            case .confirmRemoval:
                return removalConfirmation(action: action, request: request)
            case .save:
                do {
                    _ = try store.save(action.preset)
                } catch {
                    return Self.error(
                        title: "Unable to save preset",
                        subtitle: error.localizedDescription
                    )
                }
            case .remove:
                do {
                    _ = try store.remove(action.preset)
                } catch {
                    return Self.error(
                        title: "Unable to remove preset",
                        subtitle: error.localizedDescription
                    )
                }
            }
        }

        return menuResponse(
            request: request,
            stateJSON: state.presetAction == nil
                ? stateJSON
                : encoded(.cropPDF(request)),
            query: state.presetAction == nil ? query : "",
            store: store,
            environment: environment,
            fileManager: fileManager,
            targetProvider: targetProvider
        )
    }

    private static func menuResponse(
        request: ParameterStepRequest,
        stateJSON: String,
        query: String,
        store: PresetStore,
        environment: Environment,
        fileManager: FileManager,
        targetProvider: any CropPDFTargetProviding
    ) -> ScriptFilterResponse {
        let affordance = ScriptFilterAffordance.processingInputs(
            request.inputs,
            itemKinds: request.itemKinds
        )
        let presets = cropPDFPresets(from: store)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if let branch = branchQuery(trimmed) {
            let response = branchResponse(
                branch,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager,
                targetProvider: targetProvider
            )
            return response.applying(affordance)
        }
        if !trimmed.isEmpty,
           let branch = inferredBranch(trimmed, targetProvider: targetProvider) {
            let response = branchResponse(
                branch,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager,
                targetProvider: targetProvider
            )
            return response.applying(affordance)
        }

        var items = [
            branchItem(
                title: "Custom Ratio / Resolution",
                subtitle: "Ratio or resolution",
                prefix: CropPDFTargetKind.ratio.prefix,
                request: request,
                stateJSON: stateJSON
            ),
            branchItem(
                title: "Apple Device",
                subtitle: "Clop's supported devices",
                prefix: CropPDFTargetKind.device.prefix,
                request: request,
                stateJSON: stateJSON
            ),
            branchItem(
                title: "Paper Size",
                subtitle: "Clop's supported paper sizes",
                prefix: CropPDFTargetKind.paper.prefix,
                request: request,
                stateJSON: stateJSON
            )
        ]
        items.append(contentsOf: presets.map {
            presetItem(
                $0,
                request: request,
                environment: environment,
                fileManager: fileManager
            )
        })

        if !trimmed.isEmpty {
            let search = FuzzySearch<ScriptFilterItem>(
                query: trimmed,
                targetText: {
                    [$0.title, $0.subtitle, $0.match, $0.autocomplete]
                        .compactMap(\.self)
                        .joined(separator: " ")
                }
            )
            items = search.sorted(items).map { items[$0.targetIndex] }
        }

        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func branchResponse(
        _ branch: (kind: CropPDFTargetKind, value: String),
        request: ParameterStepRequest,
        stateJSON: String,
        presets: [CropPDFActionPreset],
        environment: Environment,
        fileManager: FileManager,
        targetProvider: any CropPDFTargetProviding
    ) -> ScriptFilterResponse {
        switch branch.kind {
        case .ratio:
            return ratioResponse(
                value: branch.value,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager
            )
        case .device, .paper:
            return listResponse(
                kind: branch.kind,
                value: branch.value,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager,
                targetProvider: targetProvider
            )
        }
    }

    private static func ratioResponse(
        value: String,
        request: ParameterStepRequest,
        stateJSON: String,
        presets: [CropPDFActionPreset],
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let branchPresets = matchingPresets(
                presets,
                kind: .ratio,
                query: ""
            ).map {
                presetItem(
                    $0,
                    request: request,
                    environment: environment,
                    fileManager: fileManager
                )
            }
            return response(
                items: [ScriptFilterItem(
                    title: "Type a ratio or resolution",
                    subtitle: "\(inputDescription(for: request)) · Examples: 16:9 / 1200x630 · ⌘L Reference",
                    arg: "",
                    valid: false,
                    text: ScriptFilterText(
                        largetype: largeTypeReference(
                            ratioReference(),
                            request: request
                        )
                    )
                )] + branchPresets,
                request: request,
                stateJSON: stateJSON
            )
        }
        if let editor = controlsEditor(
            value: trimmed,
            kind: .ratio,
            knownValues: []
        ) {
            return controlsEditorResponse(
                editor,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager
            )
        }
        if let controls = CropPDFControlParser.parse(
            trimmed,
            targetKind: .ratio
        ) {
            return configuredResponse(
                controls.request,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager
            )
        }
        let matchingPresets = matchingPresets(
            presets,
            kind: .ratio,
            query: trimmed
        ).map {
            presetItem(
                $0,
                request: request,
                environment: environment,
                fileManager: fileManager
            )
        }
        return response(
            items: [invalidItem(
                title: "Invalid PDF crop ratio",
                request: request
            )] + matchingPresets,
            request: request,
            stateJSON: stateJSON
        )
    }

    private static func listResponse(
        kind: CropPDFTargetKind,
        value: String,
        request: ParameterStepRequest,
        stateJSON: String,
        presets: [CropPDFActionPreset],
        environment: Environment,
        fileManager: FileManager,
        targetProvider: any CropPDFTargetProviding
    ) -> ScriptFilterResponse {
        let values: [CropPDFTargetValue]
        do {
            values = try kind == .device
                ? targetProvider.devices()
                : targetProvider.paperSizes()
        } catch {
            return response(
                items: [ScriptFilterItem(
                    title: "Unable to load PDF crop \(kind == .device ? "devices" : "paper sizes")",
                    subtitle: error.localizedDescription,
                    arg: "",
                    valid: false
                )],
                request: request,
                stateJSON: stateJSON
            )
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let branchPresets = presets
                .filter { presetKind($0.request.target) == kind }
                .map {
                    presetItem(
                        $0,
                        request: request,
                        environment: environment,
                        fileManager: fileManager
                    )
                }
            let instruction = ScriptFilterItem(
                title: kind == .device
                    ? "Type to search Apple devices"
                    : "Type to search paper sizes",
                subtitle: [
                    inputDescription(for: request),
                    kind == .device
                        ? "Clop's supported devices"
                        : "Clop's supported paper sizes",
                    "⌘L Reference"
                ].joined(separator: " · "),
                arg: "",
                valid: false,
                text: ScriptFilterText(
                    largetype: largeTypeReference(
                        listReference(kind: kind, values: values),
                        request: request
                    )
                )
            )
            return response(
                items: [instruction] + branchPresets,
                request: request,
                stateJSON: stateJSON
            )
        }
        if let editor = controlsEditor(
            value: trimmed,
            kind: kind,
            knownValues: values
        ) {
            return controlsEditorResponse(
                editor,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager
            )
        }
        if isKnownTargetSelection(trimmed, values: values),
           let controls = CropPDFControlParser.parse(
            trimmed,
            targetKind: kind,
            knownValues: values
        ) {
            return configuredResponse(
                controls.request,
                request: request,
                stateJSON: stateJSON,
                presets: presets,
                environment: environment,
                fileManager: fileManager
            )
        }

        let candidates = trimmed.isEmpty
            ? values
            : values.filter {
                normalized($0.searchText).contains(normalized(trimmed))
            }
        let matching = trimmed.isEmpty
            ? candidates
            : FuzzySearch<CropPDFTargetValue>(
                query: trimmed,
                targetText: { $0.searchText }
            ).sorted(candidates).map { candidates[$0.targetIndex] }
        guard !matching.isEmpty else {
            return response(
                items: [ScriptFilterItem(
                    title: "No matching PDF crop \(kind == .device ? "devices" : "paper sizes")",
                    subtitle: "Try another search term.",
                    arg: "",
                    valid: false
                )],
                request: request,
                stateJSON: stateJSON
            )
        }

        var items = matching.map {
            targetItem(
                $0,
                kind: kind,
                request: request,
                stateJSON: stateJSON,
                environment: environment,
                fileManager: fileManager
            )
        }
        items.append(contentsOf: matchingPresets(
            presets,
            kind: kind,
            query: trimmed
        ).map {
                presetItem(
                    $0,
                    request: request,
                    environment: environment,
                    fileManager: fileManager
                )
            })
        return response(items: items, request: request, stateJSON: stateJSON)
    }

    private static func matchingPresets(
        _ presets: [CropPDFActionPreset],
        kind: CropPDFTargetKind,
        query: String
    ) -> [CropPDFActionPreset] {
        let normalizedQuery = normalized(query)
        return presets.filter {
            presetKind($0.request.target) == kind
                && (normalizedQuery.isEmpty
                    || normalized($0.displayValue).contains(normalizedQuery))
        }
    }

    private static func controlsEditorResponse(
        _ editor: (base: CropPDFRequest, query: String),
        request: ParameterStepRequest,
        stateJSON: String,
        presets: [CropPDFActionPreset],
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let choices = [
            ("Default", ""),
            ("Portrait", "p"),
            ("Landscape", "l"),
            ("Auto", "a"),
            ("Extend", "e"),
            ("Portrait + Extend", "p e"),
            ("Landscape + Extend", "l e"),
            ("Auto + Extend", "a e")
        ]
        let trimmed = editor.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = choices.compactMap { choice -> ScriptFilterItem? in
            guard trimmed.isEmpty
                || choice.0.localizedCaseInsensitiveContains(trimmed)
                || choice.1.localizedCaseInsensitiveContains(trimmed) else {
                return nil
            }
            guard let cropPDF = CropPDFControlParser.parseControlsOnly(
                choice.1,
                base: editor.base
            ) else {
                return nil
            }
            let exactPreset = presets.first { $0.request == cropPDF }
            return configuredItem(
                CropPDFActionPreset(request: cropPDF),
                savedPreset: exactPreset,
                request: request,
                environment: environment,
                fileManager: fileManager,
                autocomplete: "\(branchPrefix(for: editor.base.target))\(editor.base.target.value) controls: \(choice.1)",
                match: "\(choice.0) \(choice.1)",
                stateJSON: stateJSON
            )
        }
        if items.isEmpty {
            items.append(invalidItem(
                title: "Invalid PDF crop controls",
                request: request
            ))
        }
        return response(items: items, request: request, stateJSON: stateJSON)
    }

    private static func configuredResponse(
        _ cropPDF: CropPDFRequest,
        request: ParameterStepRequest,
        stateJSON: String,
        presets: [CropPDFActionPreset],
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let preset = CropPDFActionPreset(request: cropPDF)
        let exactPreset = presets.first { $0.request == cropPDF }
        let item = configuredItem(
            preset,
            savedPreset: exactPreset,
            request: request,
            environment: environment,
            fileManager: fileManager
        )
        return response(
            items: [item],
            request: request,
            stateJSON: stateJSON
        )
    }

    private static func branchItem(
        title: String,
        subtitle: String,
        prefix: String,
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: title,
            subtitle: "\(inputDescription(for: request)) · \(subtitle)",
            arg: prefix,
            valid: true,
            autocomplete: prefix,
            variables: queryTransitionVariables(
                stateJSON: stateJSON,
                request: request
            ),
            text: ScriptFilterText(
                largetype: largeTypeReference(
                    CropPDFControlParser.largeTypeReference,
                    request: request
                )
            )
        )
    }

    private static func targetItem(
        _ target: CropPDFTargetValue,
        kind: CropPDFTargetKind,
        request: ParameterStepRequest,
        stateJSON: String,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem {
        let cropPDF = CropPDFRequest(
            target: kind == .device
                ? .device(target.value)
                : .paperSize(target.value)
        )
        let preset = CropPDFActionPreset(request: cropPDF)
        return configuredItem(
            preset,
            savedPreset: nil,
            request: request,
            environment: environment,
            fileManager: fileManager,
            autocomplete: "\(kind.prefix)\(target.value) controls: ",
            match: target.searchText,
            stateJSON: stateJSON
        )
    }

    private static func configuredItem(
        _ preset: CropPDFActionPreset,
        savedPreset: CropPDFActionPreset?,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager,
        autocomplete: String? = nil,
        match: String? = nil,
        stateJSON: String? = nil
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            uid: savedPreset?.stableUID,
            title: title(for: preset.request),
            subtitle: ([
                inputDescription(for: request),
                savedPreset == nil
                    ? targetDescription(for: preset.request.target)
                    : nil,
                savedPreset == nil
                    ? controlsDescription(for: preset.request)
                    : nil,
                rowHint(
                    for: preset.request,
                    savedPreset: savedPreset != nil,
                    opensControls: stateJSON != nil
                ),
                savedPreset == nil ? Optional<String>.none : "⌃↩ Remove Preset"
            ] as [String?]).compactMap(\.self).joined(separator: " · "),
            arg: operationArgument(
                for: preset.request,
                request: request,
                environment: environment,
                fileManager: fileManager
            ),
            valid: true,
            autocomplete: autocomplete ?? "\(branchPrefix(for: preset.request.target))\(preset.request.target.value) ",
            match: match ?? preset.displayValue,
            variables: [
                ActionMenu.requestKindVariable:
                    WorkflowRequestKind.operation.rawValue
            ],
            mods: ScriptFilterMods(
                control: presetModifier(
                    kind: savedPreset == nil ? .save : .confirmRemoval,
                    preset: preset,
                    request: request
                ),
                function: stateJSON.map {
                    controlsModifier(
                        cropPDF: preset.request,
                        request: request,
                        stateJSON: $0
                    )
                }
            ),
            text: ScriptFilterText(
                largetype: largeTypeReference(
                    CropPDFControlParser.largeTypeReference,
                    request: request
                )
            )
        )
    }

    private static func presetItem(
        _ preset: CropPDFActionPreset,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem {
        configuredItem(
            preset,
            savedPreset: preset,
            request: request,
            environment: environment,
            fileManager: fileManager
        )
    }

    private static func invalidItem(
        title: String,
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: title,
            subtitle: "\(inputDescription(for: request)) · Use 16:9 / 1200x630 · Use target + p / l / a / e · ⌘L Reference",
            arg: "",
            valid: false,
            text: ScriptFilterText(
                largetype: largeTypeReference(
                    CropPDFControlParser.largeTypeReference,
                    request: request
                )
            )
        )
    }

    private static func removalConfirmation(
        action: PresetMenuAction,
        request: ParameterStepRequest
    ) -> ScriptFilterResponse {
        let removeState = MenuState.cropPDF(
            request,
            action: PresetMenuAction(kind: .remove, preset: action.preset)
        )
        let removeJSON = encoded(removeState)
        let cancelJSON = encoded(.cropPDF(request))
        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Remove Preset \(presetDisplayValue(action.preset))?",
                    subtitle: "Return confirms · Cannot be undone",
                    arg: removeJSON,
                    valid: true,
                    variables: transitionVariables(
                        stateJSON: removeJSON,
                        request: request
                    )
                ),
                ScriptFilterItem(
                    title: "Cancel",
                    subtitle: "Return keeps preset",
                    arg: cancelJSON,
                    valid: true,
                    variables: transitionVariables(
                        stateJSON: cancelJSON,
                        request: request
                    )
                )
            ],
            variables: preservedVariables(for: request, stateJSON: removeJSON),
            skipKnowledge: true
        )
    }

    private static func operationArgument(
        for cropPDF: CropPDFRequest,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> String {
        let template = (try? PresetStore(
            environment: environment,
            fileManager: fileManager
        ).load().outputTemplate)
            ?? SettingsDocument.builtInOutputTemplate
        return (try? JSONOutput.string(
            for: OperationRequest(
                inputs: request.inputs,
                action: .cropPDF(cropPDF),
                execution: environment.executionOptions(
                    outputTemplate: template
                )
            ),
            prettyPrinted: false
        )) ?? ""
    }

    private static func cropPDFPresets(
        from store: PresetStore
    ) -> [CropPDFActionPreset] {
        (try? store.load().presets.compactMap {
            guard case .cropPDF(let preset) = $0 else { return nil }
            return preset
        }.sorted {
            $0.displayValue.localizedStandardCompare($1.displayValue)
                == .orderedAscending
        }) ?? []
    }

    private static func branchQuery(
        _ query: String
    ) -> (kind: CropPDFTargetKind, value: String)? {
        for kind in [CropPDFTargetKind.ratio, .device, .paper] {
            let compactPrefix = kind.prefix
                .trimmingCharacters(in: .whitespaces)
            if query.lowercased().hasPrefix(kind.prefix) {
                return (
                    kind,
                    String(query.dropFirst(kind.prefix.count))
                )
            } else if query.lowercased() == compactPrefix {
                return (kind, "")
            }
        }
        return nil
    }

    private static func inferredBranch(
        _ query: String,
        targetProvider: any CropPDFTargetProviding
    ) -> (kind: CropPDFTargetKind, value: String)? {
        if looksLikeRatioEntry(query) {
            return (.ratio, query)
        }
        let normalizedQuery = normalized(query)
        let deviceMatches = (try? targetProvider.devices()).map {
            matchingValues(query: normalizedQuery, values: $0)
        } ?? []
        let paperMatches = (try? targetProvider.paperSizes()).map {
            matchingValues(query: normalizedQuery, values: $0)
        } ?? []

        if !deviceMatches.isEmpty && paperMatches.isEmpty {
            return (.device, query)
        }
        if !paperMatches.isEmpty && deviceMatches.isEmpty {
            return (.paper, query)
        }
        return nil
    }

    private static func matchingValues(
        query: String,
        values: [CropPDFTargetValue]
    ) -> [CropPDFTargetValue] {
        values.filter { normalized($0.searchText).contains(query) }
    }

    private static func looksLikeRatioEntry(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return trimmed.contains(":")
            || trimmed.lowercased().contains("x")
            || trimmed.first?.isNumber == true
    }

    private static func controlsEditor(
        value: String,
        kind: CropPDFTargetKind,
        knownValues: [CropPDFTargetValue]
    ) -> (base: CropPDFRequest, query: String)? {
        guard let range = value.range(
            of: CropPDFControlParser.controlsPrefix,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let targetText = String(value[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let controlsText = String(value[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = CropPDFControlParser.parse(
            targetText,
            targetKind: kind,
            knownValues: knownValues
        )?.request else {
            return nil
        }
        return (base, controlsText)
    }

    private static func ratioReference() -> String {
        """
        Custom Ratio / Resolution

        Type a ratio or resolution:
        16:9
        4:3
        1200x630

        Optional layout controls:
        a or auto
        p or portrait
        l or landscape
        e or extend

        Page layout is Clop's page-orientation hint for the PDF crop target.

        Examples:
        16:9 l
        1200x630 p e
        """
    }

    private static func largeTypeReference(
        _ reference: String,
        request: ParameterStepRequest
    ) -> String {
        ScriptFilterAffordance.referenceLargeType(
            reference,
            inputs: request.inputs
        )
    }

    private static func listReference(
        kind: CropPDFTargetKind,
        values: [CropPDFTargetValue]
    ) -> String {
        let heading = kind == .device
            ? "Apple Device Crop PDF"
            : "Paper Size Crop PDF"
        let noun = kind == .device ? "device" : "paper size"
        let categories = Array(Set(values.compactMap(\.category))).sorted()
        let categoryText = categories.isEmpty
            ? "Clop list"
            : categories.prefix(8).joined(separator: "\n")
        let examples = values.prefix(6).map(\.value)
        let exampleText = examples.isEmpty
            ? "Type to search"
            : examples.joined(separator: "\n")
        return """
        \(heading)

        Type to search Clop's current \(noun) list.

        Groups include:
        \(categoryText)

        Examples:
        \(exampleText)

        Optional controls:
        a or auto
        p or portrait
        l or landscape
        e or extend
        """
    }

    private static func isKnownTargetSelection(
        _ value: String,
        values: [CropPDFTargetValue]
    ) -> Bool {
        let normalizedValue = normalized(value)
        return values.contains { candidate in
            let normalizedCandidate = normalized(candidate.value)
            return normalizedValue == normalizedCandidate
                || normalizedValue.hasPrefix(normalizedCandidate + " ")
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func title(for request: CropPDFRequest) -> String {
        ([request.target.value] + CropPDFControlParser.controlDescriptions(for: request))
            .joined(separator: " · ")
    }

    private static func controlsDescription(for request: CropPDFRequest) -> String {
        let controls = CropPDFControlParser.controlDescriptions(for: request)
        return controls.isEmpty ? "Auto layout" : controls.joined(separator: ", ")
    }

    private static func rowHint(
        for request: CropPDFRequest,
        savedPreset: Bool,
        opensControls: Bool
    ) -> String {
        if savedPreset {
            return "Saved Preset"
        }
        if opensControls && CropPDFControlParser
            .controlDescriptions(for: request).isEmpty {
            return "⇥ Controls, ⌃↩ Save Preset"
        }
        return "⌃↩ Save Preset"
    }

    private static func targetDescription(for target: CropPDFTarget) -> String {
        switch target {
        case .aspectRatio:
            return "Ratio / resolution"
        case .device:
            return "Device"
        case .paperSize:
            return "Paper size"
        }
    }

    private static func branchPrefix(for target: CropPDFTarget) -> String {
        switch target {
        case .aspectRatio:
            return CropPDFTargetKind.ratio.prefix
        case .device:
            return CropPDFTargetKind.device.prefix
        case .paperSize:
            return CropPDFTargetKind.paper.prefix
        }
    }

    private static func presetKind(_ target: CropPDFTarget) -> CropPDFTargetKind {
        switch target {
        case .aspectRatio:
            return .ratio
        case .device:
            return .device
        case .paperSize:
            return .paper
        }
    }

    private static func presetModifier(
        kind: PresetMenuActionKind,
        preset: CropPDFActionPreset,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let state = MenuState.cropPDF(
            request,
            action: PresetMenuAction(kind: kind, preset: .cropPDF(preset))
        )
        let stateJSON = encoded(state)
        return ScriptFilterModifier(
            arg: stateJSON,
            subtitle: kind == .save
                ? "Save Preset \(preset.displayValue)"
                : "Remove Preset \(preset.displayValue)",
            valid: true,
            variables: transitionVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
    }

    private static func controlsModifier(
        cropPDF: CropPDFRequest,
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterModifier {
        ScriptFilterModifier(
            arg: "\(branchPrefix(for: cropPDF.target))\(cropPDF.target.value) controls: ",
            subtitle: "Controls",
            valid: true,
            variables: queryTransitionVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
    }

    private static func response(
        items: [ScriptFilterItem],
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(
            items: items,
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
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
            ActionMenu.menuStateVariable: stateJSON,
            ActionMenu.publicRequestVariable: ""
        ]
    }

    private static func transitionVariables(
        stateJSON: String,
        request: ParameterStepRequest
    ) -> [String: String] {
        var variables = preservedVariables(for: request, stateJSON: stateJSON)
        variables[ActionMenu.requestKindVariable] =
            WorkflowRequestKind.parameterStep.rawValue
        return variables
    }

    private static func queryTransitionVariables(
        stateJSON: String,
        request: ParameterStepRequest
    ) -> [String: String] {
        var variables = preservedVariables(for: request, stateJSON: stateJSON)
        variables[ActionMenu.requestKindVariable] =
            WorkflowRequestKind.parameterStepQuery.rawValue
        return variables
    }

    private static func inputDescription(for request: ParameterStepRequest) -> String {
        request.inputContext.inputDescription(
            inputs: request.inputs,
            itemKinds: request.itemKinds,
            ambiguousKinds: request.ambiguousKinds ?? [],
            processableItemCount: request.processableItemCount
        )
    }

    private static func presetDisplayValue(_ preset: ActionPreset) -> String {
        switch preset {
        case .crop(let crop):
            return crop.displayValue
        case .downscale(let downscale):
            return downscale.displayValue
        case .conversion(let conversion):
            return conversion.displayValue
        case .optimize(let optimize):
            return optimize.displayValue
        case .cropPDF(let cropPDF):
            return cropPDF.displayValue
        }
    }

    private static func encoded(_ state: MenuState) -> String {
        (try? JSONOutput.string(for: state, prettyPrinted: false)) ?? ""
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

private extension ScriptFilterResponse {
    func applying(_ affordance: ScriptFilterAffordance) -> ScriptFilterResponse {
        var copy = self
        copy.items = items.map(affordance.apply)
        return copy
    }
}
