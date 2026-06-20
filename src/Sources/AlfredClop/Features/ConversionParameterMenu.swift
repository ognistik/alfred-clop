import Foundation

enum ConversionParameterMenu {
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
        state.mode == .conversion || state.mode == .conversionPresetRemoval,
        let request = state.parameterRequest,
        request.step == "parameters",
        let media = mediaKind(for: request.action),
        !request.inputs.isEmpty else {
            return feedbackError(
                title: "Unable to open Convert",
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
            return feedbackError(
                title: "Unable to read saved presets",
                subtitle: error.localizedDescription
            )
        }

        if let action = state.presetAction {
            switch action.kind {
            case .confirmRemoval:
                return removalConfirmation(
                    action: action,
                    request: request,
                    format: state.configurationValue
                )
            case .save:
                do {
                    _ = try store.save(action.preset)
                } catch {
                    return feedbackError(
                        title: "Unable to save preset",
                        subtitle: error.localizedDescription
                    )
                }
            case .remove:
                do {
                    _ = try store.remove(action.preset)
                } catch {
                    return feedbackError(
                        title: "Unable to remove preset",
                        subtitle: error.localizedDescription
                    )
                }
            }
        }

        let selectedFormat = state.configurationValue.flatMap {
            ConversionCatalog.normalizedFormat($0, media: media)
        }
        return menuResponse(
            request: request,
            media: media,
            selectedFormat: selectedFormat,
            query: state.presetAction == nil ? query : "",
            store: store,
            environment: environment,
            fileManager: fileManager
        )
    }

    private static func menuResponse(
        request: ParameterStepRequest,
        media: ConversionMediaKind,
        selectedFormat: String?,
        query: String,
        store: PresetStore,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let presets: [ConversionActionPreset]
        do {
            presets = try store.load().presets.compactMap {
                guard case .conversion(let preset) = $0,
                      preset.choice.media == media else {
                    return nil
                }
                return preset
            }.sorted {
                $0.displayValue.localizedStandardCompare($1.displayValue)
                    == .orderedAscending
            }
        } catch {
            return feedbackError(
                title: "Unable to read saved presets",
                subtitle: error.localizedDescription
            )
        }

        if let selectedFormat {
            return controlsResponse(
                request: request,
                choice: ConversionChoice(
                    media: media,
                    format: selectedFormat
                ),
                query: query,
                presets: presets,
                environment: environment,
                fileManager: fileManager
            )
        }

        let leadingWhitespace = query.last?.isWhitespace == true
        let components = query.split(
            maxSplits: 1,
            whereSeparator: \.isWhitespace
        )
        if let first = components.first,
           let format = ConversionCatalog.normalizedFormat(
               String(first),
               media: media
           ),
           components.count > 1 || leadingWhitespace {
            let editorQuery = components.count > 1
                ? String(components[1])
                : ""
            return controlsResponse(
                request: request,
                choice: ConversionChoice(media: media, format: format),
                query: editorQuery,
                presets: presets,
                environment: environment,
                fileManager: fileManager
            )
        }

        let hiddenFormat = sameImageFormat(
            request: request,
            media: media
        )
        let availableFormats = ConversionCatalog.formats(for: media).filter {
            $0 != hiddenFormat
        }
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var items = availableFormats.map {
            formatItem(
                choice: ConversionChoice(media: media, format: $0),
                request: request,
                environment: environment,
                fileManager: fileManager
            )
        }
        items.append(contentsOf: presets.map {
            presetItem(
                preset: $0,
                request: request,
                environment: environment,
                fileManager: fileManager
            )
        })

        if !normalizedQuery.isEmpty {
            let search = FuzzySearch<ScriptFilterItem>(
                query: normalizedQuery,
                targetText: {
                    [$0.title, $0.match].compactMap(\.self)
                        .joined(separator: " ")
                }
            )
            items = search.sorted(items).map { items[$0.targetIndex] }
        }
        guard !items.isEmpty else {
            return feedbackError(
                title: "No matching conversion formats",
                subtitle: "Try another format or codec."
            )
        }
        return response(
            items: items,
            request: request,
            state: .conversion(request)
        )
    }

    private static func controlsResponse(
        request: ParameterStepRequest,
        choice: ConversionChoice,
        query: String,
        presets: [ConversionActionPreset],
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        guard ConversionCatalog.supportsControls(choice) else {
            return response(
                items: [
                    formatItem(
                        choice: choice,
                        request: request,
                        environment: environment,
                        fileManager: fileManager
                    )
                ],
                request: request,
                state: .conversion(request)
            )
        }

        let relatedPresets = presets.filter {
            $0.choice.format == choice.format
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = [ScriptFilterItem]()

        if trimmed.isEmpty {
            items.append(defaultChoiceItem(
                choice: choice,
                request: request,
                environment: environment,
                fileManager: fileManager
            ))
            items.append(contentsOf: relatedPresets.map {
                presetItem(
                    preset: $0,
                    request: request,
                    environment: environment,
                    fileManager: fileManager
                )
            })
        } else if let setting = parseSetting(trimmed, for: choice) {
            let configured = ConversionChoice(
                media: choice.media,
                format: choice.format,
                setting: setting
            )
            let exactPreset = relatedPresets.first {
                $0.choice == configured
            }
            items.append(configuredChoiceItem(
                choice: configured,
                savedPreset: exactPreset,
                request: request,
                environment: environment,
                fileManager: fileManager
            ))
            items.append(contentsOf: relatedPresets
                .filter { $0.choice != configured }
                .filter {
                    $0.displayValue.localizedCaseInsensitiveContains(trimmed)
                }
                .map {
                    presetItem(
                        preset: $0,
                        request: request,
                        environment: environment,
                        fileManager: fileManager
                    )
                })
        } else {
            let matching = relatedPresets.filter {
                $0.displayValue.localizedCaseInsensitiveContains(trimmed)
            }
            if isPossibleControlPrefix(trimmed, for: choice) {
                items.append(partialControlItem(
                    for: choice,
                    request: request
                ))
                items.append(contentsOf: matching.map {
                    presetItem(
                        preset: $0,
                        request: request,
                        environment: environment,
                        fileManager: fileManager
                    )
                })
            } else if matching.isEmpty {
                items.append(invalidControlItem(for: choice, request: request))
            } else {
                items.append(contentsOf: matching.map {
                    presetItem(
                        preset: $0,
                        request: request,
                        environment: environment,
                        fileManager: fileManager
                    )
                })
            }
        }

        return response(
            items: items,
            request: request,
            state: .conversion(request)
        )
    }

    private static func formatItem(
        choice: ConversionChoice,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem {
        let hasControls = ConversionCatalog.supportsControls(choice)
        return ScriptFilterItem(
            uid: "convert.format.\(choice.media.rawValue).\(choice.format)",
            title: "Convert to \(choice.displayFormat)",
            subtitle: [
                inputDescription(for: request),
                hasControls
                    ? Optional("⇥ Controls")
                    : nil
            ].compactMap(\.self).joined(separator: " · "),
            arg: operationArgument(
                choice: choice,
                request: request,
                environment: environment,
                fileManager: fileManager
            ),
            valid: true,
            autocomplete: hasControls ? "\(choice.format) " : choice.format,
            match: "\(choice.format) \(choice.displayFormat) convert",
            variables: operationVariables,
            mods: operationModifiers(
                choice: choice,
                request: request,
                environment: environment,
                fileManager: fileManager,
                control: hasControls
                    ? controlsModifier(choice: choice, request: request)
                    : nil
            )
        )
    }

    private static func defaultChoiceItem(
        choice: ConversionChoice,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Convert to \(choice.displayFormat)",
            subtitle: [
                inputDescription(for: request),
                controlHint(for: choice),
                "⏎ Run Defaults",
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: operationArgument(
                choice: choice,
                request: request,
                environment: environment,
                fileManager: fileManager
            ),
            valid: true,
            variables: operationVariables,
            mods: operationModifiers(
                choice: choice,
                request: request,
                environment: environment,
                fileManager: fileManager,
                control: nil
            ),
            text: ScriptFilterText(
                largetype: largeTypeReference(for: choice, request: request)
            )
        )
    }

    private static func configuredChoiceItem(
        choice: ConversionChoice,
        savedPreset: ConversionActionPreset?,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem {
        let preset = ConversionActionPreset(choice: choice)
        return ScriptFilterItem(
            uid: savedPreset?.stableUID,
            title: "Convert to \(choice.displayValue)",
            subtitle: ([
                inputDescription(for: request),
                savedPreset == nil ? "⌃↩ Save Preset" : "Saved Preset",
                savedPreset == nil ? Optional<String>.none : "⌃↩ Remove Preset",
                "⌘L Reference"
            ] as [String?]).compactMap(\.self).joined(separator: " · "),
            arg: operationArgument(
                choice: choice,
                request: request,
                environment: environment,
                fileManager: fileManager
            ),
            valid: true,
            autocomplete: controlQuery(for: choice),
            match: choice.displayValue,
            icon: savedPreset == nil ? nil : WorkflowIcon.preset,
            variables: operationVariables,
            mods: operationModifiers(
                choice: choice,
                request: request,
                environment: environment,
                fileManager: fileManager,
                control: presetModifier(
                    kind: savedPreset == nil ? .save : .confirmRemoval,
                    preset: preset,
                    request: request
                )
            ),
            text: ScriptFilterText(
                largetype: largeTypeReference(for: choice, request: request)
            )
        )
    }

    private static func presetItem(
        preset: ConversionActionPreset,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            uid: preset.stableUID,
            title: preset.displayValue,
            subtitle: [
                inputDescription(for: request),
                "Saved Preset",
                "⌃↩ Remove Preset"
            ].compactMap(\.self).joined(separator: " · "),
            arg: operationArgument(
                choice: preset.choice,
                request: request,
                environment: environment,
                fileManager: fileManager
            ),
            valid: true,
            autocomplete: controlQuery(for: preset.choice),
            match: preset.displayValue,
            icon: WorkflowIcon.preset,
            variables: operationVariables,
            mods: operationModifiers(
                choice: preset.choice,
                request: request,
                environment: environment,
                fileManager: fileManager,
                control: presetModifier(
                    kind: .confirmRemoval,
                    preset: preset,
                    request: request
                )
            )
        )
    }

    private static func operationModifiers(
        choice: ConversionChoice,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager,
        control: ScriptFilterModifier?
    ) -> ScriptFilterMods {
        let preserve = environment.preserveOriginal
        let subtitle = preserve
            ? "Replace Originals"
            : "Output Template"
        return ScriptFilterMods(
            control: control,
            shift: ScriptFilterModifier(
                arg: operationArgument(
                    choice: choice,
                    request: request,
                    environment: environment,
                    fileManager: fileManager,
                    preserveOriginal: !preserve
                ),
                subtitle: "\(inputDescription(for: request)) · \(subtitle)",
                valid: true,
                variables: operationVariables
            )
        )
    }

    private static func controlsModifier(
        choice: ConversionChoice,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let state = MenuState.conversion(request)
        let stateJSON = encoded(state)
        return ScriptFilterModifier(
            arg: "\(choice.format) ",
            subtitle: "Controls",
            valid: true,
            variables: queryTransitionVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
    }

    private static func presetModifier(
        kind: PresetMenuActionKind,
        preset: ConversionActionPreset,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let action = PresetMenuAction(kind: kind, preset: .conversion(preset))
        let state = kind == .save
            ? MenuState.conversion(request, format: nil, action: action)
            : MenuState.conversion(
                request,
                format: preset.choice.format,
                action: action
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

    private static func removalConfirmation(
        action: PresetMenuAction,
        request: ParameterStepRequest,
        format: String?
    ) -> ScriptFilterResponse {
        let state = MenuState.conversion(
            request,
            format: nil,
            action: PresetMenuAction(kind: .remove, preset: action.preset)
        )
        let stateJSON = encoded(state)
        let cancelStateJSON = encoded(.conversion(request, format: format))
        let name: String
        if case .conversion(let preset) = action.preset {
            name = preset.displayValue
        } else {
            name = "conversion preset"
        }
        return ScriptFilterResponse(
            items: [
                ScriptFilterItem(
                    title: "Remove Preset \(name)?",
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
                request: request,
                stateJSON: stateJSON
            ),
            skipKnowledge: true
        )
    }

    private static func parseSetting(
        _ value: String,
        for choice: ConversionChoice
    ) -> ConversionSetting? {
        let normalized = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if choice.media == .video, normalized == "auto" {
            return .automaticCompression
        }
        if choice.media == .audio {
            if let number = prefixedNumber(
                normalized,
                prefixes: ["c", "compression "]
            ), (5...100).contains(number) {
                return .compression(number)
            }
            if let number = prefixedNumber(
                normalized,
                prefixes: ["b", "bitrate "]
            ), number > 0 {
                return .bitrate(number)
            }
            return nil
        }
        guard let number = Int(normalized), (5...100).contains(number) else {
            return nil
        }
        return .compression(number)
    }

    private static func prefixedNumber(
        _ value: String,
        prefixes: [String]
    ) -> Int? {
        for prefix in prefixes where value.hasPrefix(prefix) {
            return Int(value.dropFirst(prefix.count))
        }
        return nil
    }

    private static func invalidControlItem(
        for choice: ConversionChoice,
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Invalid conversion control",
            subtitle: [
                inputDescription(for: request),
                controlHint(for: choice),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: choice, request: request)
            )
        )
    }

    private static func partialControlItem(
        for choice: ConversionChoice,
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: partialControlTitle(for: choice),
            subtitle: [
                inputDescription(for: request),
                controlHint(for: choice),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: choice, request: request)
            )
        )
    }

    private static func isPossibleControlPrefix(
        _ value: String,
        for choice: ConversionChoice
    ) -> Bool {
        let normalized = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }
        switch choice.media {
        case .image:
            guard normalized.allSatisfy(\.isNumber) else {
                return false
            }
            return Int(normalized).map { $0 <= 100 } ?? false
        case .video:
            if normalized.allSatisfy(\.isNumber) {
                return Int(normalized).map { $0 <= 100 } ?? false
            }
            return "auto".hasPrefix(normalized)
        case .audio:
            return normalized == "c"
                || normalized == "b"
                || "compression".hasPrefix(normalized)
                || "bitrate".hasPrefix(normalized)
        }
    }

    private static func controlQuery(for choice: ConversionChoice) -> String? {
        guard let setting = choice.setting else {
            return nil
        }
        let value: String
        switch setting {
        case .compression(let number):
            value = choice.media == .audio ? "c\(number)" : "\(number)"
        case .automaticCompression:
            value = "auto"
        case .bitrate(let number):
            value = "b\(number)"
        }
        return "\(choice.format) \(value)"
    }

    private static func largeTypeReference(
        for choice: ConversionChoice,
        request: ParameterStepRequest?
    ) -> String {
        let heading = "\(choice.displayFormat) Conversion controls"
        let body: String
        switch choice.media {
        case .image:
            body = """
            Type a compression value from 5 to 100.

            Examples:
            70
            85
            """
        case .video:
            body = """
            Type a compression value from 5 to 100, or auto.

            Examples:
            70
            auto
            """
        case .audio:
            body = """
            Use c-number for compression or b-number for bitrate.

            Examples:
            c70
            b128
            bitrate 128
            """
        }
        let reference = "\(heading)\n\n\(body)"
        return ScriptFilterAffordance.referenceLargeType(
            reference,
            inputs: request?.inputs ?? [],
            pixelDimensions: request?.pixelDimensions
        )
    }

    private static func controlHelp(for choice: ConversionChoice) -> String {
        controlHint(for: choice)
    }

    private static func controlHint(for choice: ConversionChoice) -> String {
        switch choice.media {
        case .image:
            return "Use compression 5-100"
        case .video:
            return "Use compression 5-100 / auto"
        case .audio:
            return "Use compression (e.g. c70) / bitrate (e.g. b128)"
        }
    }

    private static func partialControlTitle(
        for choice: ConversionChoice
    ) -> String {
        switch choice.media {
        case .image, .video:
            return "Type compression value"
        case .audio:
            return "Type audio conversion control"
        }
    }

    private static func settingDescription(
        _ setting: ConversionSetting?
    ) -> String? {
        switch setting {
        case .compression(let value):
            return "Compression \(value)"
        case .automaticCompression:
            return "Automatic compression"
        case .bitrate(let value):
            return "Target bitrate \(value) kbps"
        case nil:
            return nil
        }
    }

    private static func conciseSettingDescription(
        _ setting: ConversionSetting?
    ) -> String? {
        switch setting {
        case .compression(let value):
            return "Compression \(value)"
        case .automaticCompression:
            return "Automatic compression"
        case .bitrate(let value):
            return "\(value) kbps"
        case nil:
            return nil
        }
    }

    private static func indefiniteArticle(for value: String) -> String {
        guard let first = value.first?.lowercased() else {
            return "a"
        }
        return ["a", "e", "i", "o", "u"].contains(first) ? "an" : "a"
    }

    private static func sameImageFormat(
        request: ParameterStepRequest,
        media: ConversionMediaKind
    ) -> String? {
        guard media == .image,
              request.ambiguousKinds?.isEmpty != false,
              !request.inputs.isEmpty else {
            return nil
        }
        let kinds = request.itemKinds
            ?? Array(repeating: .localFile, count: request.inputs.count)
        var formats = Set<String>()
        for (index, input) in request.inputs.enumerated() {
            guard index < kinds.count, kinds[index] != .folder else {
                return nil
            }
            let ext: String
            if kinds[index] == .remoteURL {
                guard let url = URL(string: input) else { return nil }
                ext = url.pathExtension
            } else {
                ext = URL(fileURLWithPath: input).pathExtension
            }
            guard let format = ConversionCatalog.normalizedFormat(
                ext,
                media: .image
            ) else {
                return nil
            }
            formats.insert(format)
        }
        return formats.count == 1 ? formats.first : nil
    }

    private static func operationArgument(
        choice: ConversionChoice,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager,
        preserveOriginal: Bool? = nil
    ) -> String {
        let template = (try? PresetStore(
            environment: environment,
            fileManager: fileManager
        ).load().outputTemplate)
            ?? SettingsDocument.builtInOutputTemplate
        return (try? JSONOutput.string(
            for: OperationRequest(
                inputs: request.inputs,
                action: .convert(choice),
                execution: environment.executionOptions(
                    outputTemplate: template,
                    preserveOriginal: preserveOriginal
                )
            ),
            prettyPrinted: false
        )) ?? ""
    }

    private static func mediaKind(
        for action: ClopAction
    ) -> ConversionMediaKind? {
        switch action {
        case .convertImage:
            return .image
        case .convertVideo:
            return .video
        case .convertAudio:
            return .audio
        default:
            return nil
        }
    }

    private static var operationVariables: [String: String] {
        [
            ActionMenu.requestKindVariable:
                WorkflowRequestKind.operation.rawValue
        ]
    }

    private static func response(
        items: [ScriptFilterItem],
        request: ParameterStepRequest,
        state: MenuState
    ) -> ScriptFilterResponse {
        let stateJSON = encoded(state)
        let affordance = ScriptFilterAffordance.processingInputs(
            request.inputs,
            itemKinds: request.itemKinds,
            pixelDimensions: request.pixelDimensions
        )
        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(
                request: request,
                stateJSON: stateJSON
            ),
            skipKnowledge: true
        )
    }

    private static func transitionVariables(
        stateJSON: String,
        request: ParameterStepRequest
    ) -> [String: String] {
        var variables = preservedVariables(
            request: request,
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
            request: request,
            stateJSON: stateJSON
        )
        variables[ActionMenu.requestKindVariable] =
            WorkflowRequestKind.parameterStepQuery.rawValue
        return variables
    }

    private static func preservedVariables(
        request: ParameterStepRequest,
        stateJSON: String
    ) -> [String: String] {
        [
            ActionMenu.inputJSONVariable: (try? JSONOutput.string(
                for: MenuInput(
                    paths: request.inputs,
                mediaKinds: request.mediaKinds,
                itemKinds: request.itemKinds,
                pixelDimensions: request.pixelDimensions,
                ambiguousKinds: request.ambiguousKinds,
                    processableItemCount: request.processableItemCount
                ),
                prettyPrinted: false
            )) ?? "",
            ActionMenu.inputContextVariable: request.inputContext.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func encoded(_ state: MenuState) -> String {
        (try? JSONOutput.string(for: state, prettyPrinted: false)) ?? ""
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

    private static func feedbackError(
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
