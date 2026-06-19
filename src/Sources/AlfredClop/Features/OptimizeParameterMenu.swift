import Foundation

enum OptimizeParameterMenu {
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
        state.mode == .optimise || state.mode == .optimisePresetRemoval,
        let request = state.parameterRequest,
        request.step == "parameters",
        request.action == .optimise,
        !request.inputs.isEmpty else {
            return error(
                title: "Unable to open Optimize",
                subtitle: "The controls menu state is invalid or incomplete."
            )
        }

        let store: PresetStore?
        do {
            store = try PresetStore(
                environment: environment,
                fileManager: fileManager,
                writer: writer
            )
        } catch {
            store = nil
        }

        if let action = state.presetAction {
            guard let store else {
                return Self.error(
                    title: "Unable to save preset",
                    subtitle: PresetStoreError
                        .missingWorkflowDataDirectory
                        .localizedDescription
                )
            }
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

        let cleanStateJSON = encoded(MenuState.optimise(request))
        return menuResponse(
            request: request,
            stateJSON: state.presetAction == nil ? stateJSON : cleanStateJSON,
            query: state.presetAction == nil ? query : "",
            store: store,
            environment: environment,
            fileManager: fileManager
        )
    }

    private static func menuResponse(
        request: ParameterStepRequest,
        stateJSON: String,
        query: String,
        store: PresetStore?,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let controls = controlsQuery(
            for: request,
            query: query
        ) {
            return controlsResponse(
                request: request,
                controlsQuery: controls,
                store: store,
                environment: environment,
                fileManager: fileManager
            )
        }
        if isBareControlsQuery(trimmedQuery) {
            return controlsBranchReference(
                request: request,
                stateJSON: stateJSON
            )
        }
        if !trimmedQuery.isEmpty,
           let media = homogeneousOptimizeMedia(for: request) {
            return controlsResponse(
                request: request,
                controlsQuery: ControlsQuery(
                    media: media,
                    prefix: "",
                    value: query
                ),
                store: store,
                environment: environment,
                fileManager: fileManager
            )
        }

        let affordance = ScriptFilterAffordance.processingInputs(
            request.inputs,
            itemKinds: request.itemKinds
        )

        var items = [ScriptFilterItem]()
        if let item = defaultItem(
            for: request,
            stateJSON: stateJSON,
            environment: environment,
            fileManager: fileManager
        ) {
            items.append(item)
        } else {
            items.append(ScriptFilterItem(
                title: "Unable to prepare Optimize",
                subtitle: "The operation request could not be encoded.",
                arg: "",
                valid: false
            ))
        }

        if shouldShowMediaBranches(for: request) {
            items.append(contentsOf: mediaBranches(
                for: request,
                stateJSON: stateJSON
            ))
        }
        items.append(contentsOf: rootPresetItems(
            for: request,
            store: store,
            environment: environment,
            fileManager: fileManager
        ))

        if !trimmedQuery.isEmpty {
            let search = FuzzySearch<ScriptFilterItem>(
                query: trimmedQuery,
                targetText: {
                    [$0.title, $0.subtitle, $0.match, $0.autocomplete]
                        .compactMap(\.self)
                        .joined(separator: " ")
                }
            )
            items = search.sorted(items).map { items[$0.targetIndex] }
        }
        guard !items.isEmpty else {
            return Self.error(
                title: "No matching Optimize options",
                subtitle: "Try controls or a saved preset."
            )
        }

        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func controlsResponse(
        request: ParameterStepRequest,
        controlsQuery: ControlsQuery,
        store: PresetStore?,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterResponse {
        let presets: [OptimizeActionPreset]
        if let store {
            do {
            presets = try store.load().presets.compactMap {
                guard case .optimize(let preset) = $0,
                      preset.request.media == controlsQuery.media else {
                    return nil
                }
                return preset
            }.sorted {
                $0.displayValue.localizedStandardCompare($1.displayValue)
                    == .orderedAscending
            }
            } catch {
                return Self.error(
                    title: "Unable to read saved presets",
                    subtitle: error.localizedDescription
                )
            }
        } else {
            presets = []
        }

        let trimmed = controlsQuery.value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var items = [ScriptFilterItem]()

        if trimmed.isEmpty {
            items.append(instructionItem(
                media: controlsQuery.media,
                request: request
            ))
            items.append(contentsOf: presets.map {
                presetItem(
                    preset: $0,
                    request: request,
                    environment: environment,
                    fileManager: fileManager
                )
            })
        } else if let optimize = OptimizeControlParser.parse(
            trimmed,
            media: controlsQuery.media
        ), !OptimizeControlParser.controlDescriptions(for: optimize).isEmpty {
            let exactPreset = presets.first { $0.request == optimize }
            items.append(configuredItem(
                optimize: optimize,
                savedPreset: exactPreset,
                request: request,
                environment: environment,
                fileManager: fileManager
            ))
            items.append(contentsOf: presets
                .filter { $0.request != optimize }
                .matching(trimmed)
                .map {
                    presetItem(
                        preset: $0,
                        request: request,
                        environment: environment,
                        fileManager: fileManager
                    )
                })
        } else {
            let matching = presets.matching(trimmed)
            if OptimizeControlParser.isPossiblePrefix(
                trimmed,
                media: controlsQuery.media
            ) {
                items.append(partialControlItem(
                    media: controlsQuery.media,
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
                items.append(invalidControlItem(
                    media: controlsQuery.media,
                    request: request
                ))
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
            state: .optimise(request)
        )
    }

    private static func defaultItem(
        for request: ParameterStepRequest,
        stateJSON: String,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem? {
        guard let arg = broadOperationArgument(
            for: request,
            aggressive: environment.aggressiveByDefault,
            preserveOriginal: nil,
            environment: environment,
            fileManager: fileManager
        ) else {
            return nil
        }

        return ScriptFilterItem(
            uid: "optimise.defaults",
            title: defaultTitle(for: request),
            subtitle: defaultSubtitle(for: request),
            arg: arg,
            valid: true,
            autocomplete: controlsPrefix(for: request),
            variables: operationVariables(
                request: request,
                stateJSON: stateJSON
            ),
            mods: defaultModifiers(
                for: request,
                stateJSON: stateJSON,
                environment: environment,
                fileManager: fileManager
            )
        )
    }

    private static func partialControlItem(
        media: OptimizeMediaKind,
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: emptyControlTitle(for: media),
            subtitle: [
                inputDescription(for: request),
                acceptedControlSubtitle(for: media),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: media, request: request)
            )
        )
    }

    private static func instructionItem(
        media: OptimizeMediaKind,
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        return ScriptFilterItem(
            title: emptyControlTitle(for: media),
            subtitle: [
                inputDescription(for: request),
                emptyControlSubtitle(for: media),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: media, request: request)
            )
        )
    }

    private static func configuredItem(
        optimize: OptimizeRequest,
        savedPreset: OptimizeActionPreset?,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterItem {
        let preset = OptimizeActionPreset(request: optimize)
        return ScriptFilterItem(
            uid: savedPreset?.stableUID,
            title: "Optimize \(OptimizeControlParser.displayValue(for: optimize))",
            subtitle: [
                Optional(inputDescription(for: request)),
                Optional(savedPreset == nil ? "⌃↩ Save Preset" : "Saved Preset"),
                savedPreset == nil ? Optional<String>.none : "⌃↩ Remove Preset",
                "⌘L Reference"
            ].compactMap(\.self).joined(separator: " · "),
            arg: operationArgument(
                optimize: optimize,
                request: request,
                environment: environment,
                fileManager: fileManager
            ),
            valid: true,
            autocomplete: controlQuery(for: optimize),
            match: OptimizeControlParser.displayValue(for: optimize),
            icon: savedPreset == nil ? nil : WorkflowIcon.preset,
            variables: operationVariables,
            mods: operationModifiers(
                optimize: optimize,
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
                largetype: largeTypeReference(
                    for: optimize.media,
                    request: request
                )
            )
        )
    }

    private static func presetItem(
        preset: OptimizeActionPreset,
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
            ].joined(separator: " · "),
            arg: operationArgument(
                optimize: preset.request,
                request: request,
                environment: environment,
                fileManager: fileManager
            ),
            valid: true,
            autocomplete: controlQuery(for: preset.request),
            match: preset.displayValue,
            icon: WorkflowIcon.preset,
            variables: operationVariables,
            mods: operationModifiers(
                optimize: preset.request,
                request: request,
                environment: environment,
                fileManager: fileManager,
                control: presetModifier(
                    kind: .confirmRemoval,
                    preset: preset,
                    request: request
                )
            ),
            text: ScriptFilterText(
                largetype: largeTypeReference(
                    for: preset.request.media,
                    request: request
                )
            )
        )
    }

    private static func rootPresetItems(
        for request: ParameterStepRequest,
        store: PresetStore?,
        environment: Environment,
        fileManager: FileManager
    ) -> [ScriptFilterItem] {
        let visibleMedia = Set(mediaBranchKinds(for: request).compactMap {
            OptimizeMediaKind(mediaKind: $0)
        })
        guard !visibleMedia.isEmpty,
              let store,
              let document = try? store.load() else {
            return []
        }

        return document.presets.compactMap {
            guard case .optimize(let preset) = $0,
                  visibleMedia.contains(preset.request.media) else {
                return nil
            }
            return preset
        }
        .sorted {
            $0.displayValue.localizedStandardCompare($1.displayValue)
                == .orderedAscending
        }
        .map {
            presetItem(
                preset: $0,
                request: request,
                environment: environment,
                fileManager: fileManager
            )
        }
    }

    private static func defaultModifiers(
        for request: ParameterStepRequest,
        stateJSON: String,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterMods {
        let preserve = environment.preserveOriginal
        let invertedPreserve = !preserve
        let preserveText = preserve ? "Replace Originals" : "Output Template"

        return ScriptFilterMods(
            command: broadOperationModifier(
                for: request,
                aggressive: !environment.aggressiveByDefault,
                preserveOriginal: preserve,
                subtitle: environment.aggressiveByDefault
                    ? "Standard"
                    : "Aggressive",
                environment: environment,
                fileManager: fileManager
            ),
            control: controlsModifier(request: request, stateJSON: stateJSON),
            shift: broadOperationModifier(
                for: request,
                aggressive: environment.aggressiveByDefault,
                preserveOriginal: invertedPreserve,
                subtitle: preserveText,
                environment: environment,
                fileManager: fileManager
            ),
            commandShift: broadOperationModifier(
                for: request,
                aggressive: !environment.aggressiveByDefault,
                preserveOriginal: invertedPreserve,
                subtitle: environment.aggressiveByDefault
                    ? "Standard · \(preserveText)"
                    : "Aggressive · \(preserveText)",
                environment: environment,
                fileManager: fileManager
            )
        )
    }

    private static func controlsModifier(
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterModifier {
        ScriptFilterModifier(
            arg: controlsPrefix(for: request),
            subtitle: "Controls",
            valid: true,
            variables: queryTransitionVariables(
                stateJSON: stateJSON,
                request: request
            )
        )
    }

    private static func operationModifiers(
        optimize: OptimizeRequest,
        request: ParameterStepRequest,
        environment: Environment,
        fileManager: FileManager,
        control: ScriptFilterModifier?
    ) -> ScriptFilterMods {
        let preserve = environment.preserveOriginal
        let subtitle = preserve ? "Replace Originals" : "Output Template"
        return ScriptFilterMods(
            control: control,
            shift: ScriptFilterModifier(
                arg: operationArgument(
                    optimize: optimize,
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

    private static func broadOperationModifier(
        for request: ParameterStepRequest,
        aggressive: Bool,
        preserveOriginal: Bool,
        subtitle: String,
        environment: Environment,
        fileManager: FileManager
    ) -> ScriptFilterModifier? {
        guard let arg = broadOperationArgument(
            for: request,
            aggressive: aggressive,
            preserveOriginal: preserveOriginal,
            environment: environment,
            fileManager: fileManager
        ) else {
            return nil
        }
        return ScriptFilterModifier(
            arg: arg,
            subtitle: "\(inputDescription(for: request)) · \(subtitle)",
            valid: true,
            variables: operationVariables
        )
    }

    private static func presetModifier(
        kind: PresetMenuActionKind,
        preset: OptimizeActionPreset,
        request: ParameterStepRequest
    ) -> ScriptFilterModifier {
        let action = PresetMenuAction(kind: kind, preset: .optimize(preset))
        let state = MenuState.optimise(request, action: action)
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
        request: ParameterStepRequest
    ) -> ScriptFilterResponse {
        let state = MenuState.optimise(
            request,
            action: PresetMenuAction(kind: .remove, preset: action.preset)
        )
        let stateJSON = encoded(state)
        let cancelStateJSON = encoded(.optimise(request))
        let name: String
        if case .optimize(let preset) = action.preset {
            name = preset.displayValue
        } else {
            name = "Optimize preset"
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
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func mediaBranches(
        for request: ParameterStepRequest,
        stateJSON: String
    ) -> [ScriptFilterItem] {
        mediaBranchKinds(for: request).compactMap { kind in
            guard let media = OptimizeMediaKind(mediaKind: kind) else {
                return nil
            }
            return ScriptFilterItem(
                uid: "optimise.controls.\(media.rawValue)",
                title: "\(media.displayName) Optimize Controls",
                subtitle: "\(inputDescription(for: request)) · Open \(media.displayName.lowercased()) controls · ⌘L Reference",
                arg: "",
                valid: false,
                autocomplete: "\(media.rawValue) controls: ",
                variables: preservedVariables(for: request, stateJSON: stateJSON),
                text: ScriptFilterText(
                    largetype: largeTypeReference(for: media, request: request)
                )
            )
        }
    }

    private static func controlsBranchReference(
        request: ParameterStepRequest,
        stateJSON: String
    ) -> ScriptFilterResponse {
        ScriptFilterResponse(
            items: mediaBranchKinds(for: request).compactMap { kind in
                guard let media = OptimizeMediaKind(mediaKind: kind) else {
                    return nil
                }
                return ScriptFilterItem(
                    title: "\(media.displayName) Optimize Controls",
                    subtitle: OptimizeControlParser.grammarHint(for: media),
                    arg: "",
                    valid: false,
                    autocomplete: "\(media.rawValue) controls: ",
                    icon: WorkflowIcon.guide,
                    text: ScriptFilterText(
                        largetype: largeTypeReference(
                            for: media,
                            request: request
                        )
                    )
                )
            },
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func broadOperationArgument(
        for request: ParameterStepRequest,
        aggressive: Bool,
        preserveOriginal: Bool?,
        environment: Environment,
        fileManager: FileManager
    ) -> String? {
        guard let execution = try? environment.resolvedExecutionOptions(
            fileManager: fileManager,
            preserveOriginal: preserveOriginal
        ) else {
            return nil
        }
        return try? JSONOutput.string(
            for: OperationRequest(
                inputs: request.inputs,
                action: .optimise(aggressive: aggressive),
                execution: execution
            ),
            prettyPrinted: false
        )
    }

    private static func operationArgument(
        optimize: OptimizeRequest,
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
                inputs: mediaInputs(for: optimize.media, request: request),
                action: .optimiseMedia(optimize),
                execution: environment.executionOptions(
                    outputTemplate: template,
                    preserveOriginal: preserveOriginal
                )
            ),
            prettyPrinted: false
        )) ?? ""
    }

    private static func mediaInputs(
        for media: OptimizeMediaKind,
        request: ParameterStepRequest
    ) -> [String] {
        if !(request.ambiguousKinds ?? []).isEmpty {
            return request.inputs
        }
        let kinds = request.itemKinds
            ?? Array(repeating: .localFile, count: request.inputs.count)
        let detector = MediaKindDetector()
        let filtered = request.inputs.enumerated().compactMap { index, input in
            let kind = index < kinds.count ? kinds[index] : .localFile
            switch kind {
            case .folder:
                return input
            case .remoteURL:
                guard let url = URL(string: input) else { return nil }
                return detector.kind(for: url) == media.mediaKind ? input : nil
            case .localFile:
                return detector.kind(for: URL(fileURLWithPath: input))
                    == media.mediaKind ? input : nil
            }
        }
        return filtered.isEmpty ? request.inputs : filtered
    }

    private static func isBareControlsQuery(_ query: String) -> Bool {
        query.lowercased().hasPrefix("controls:")
    }

    private static func controlsQuery(
        for request: ParameterStepRequest,
        query: String
    ) -> ControlsQuery? {
        let lowercased = query.lowercased()
        for media in OptimizeMediaKind.allCases {
            let prefix = "\(media.rawValue) controls: "
            let prefixWithoutSpace = "\(media.rawValue) controls:"
            if lowercased.hasPrefix(prefixWithoutSpace) {
                let value = String(query.dropFirst(prefixWithoutSpace.count))
                    .trimmingCharacters(in: .whitespaces)
                return ControlsQuery(
                    media: media,
                    prefix: prefix,
                    value: value
                )
            }
        }
        guard lowercased.hasPrefix("controls:"),
              let media = homogeneousOptimizeMedia(for: request) else {
            return nil
        }
        let prefix = "controls: "
        let prefixWithoutSpace = "controls:"
        let value = String(query.dropFirst(prefixWithoutSpace.count))
            .trimmingCharacters(in: .whitespaces)
        return ControlsQuery(media: media, prefix: prefix, value: value)
    }

    private static func controlsPrefix(
        for request: ParameterStepRequest
    ) -> String {
        guard shouldShowMediaBranches(for: request) else {
            return "controls: "
        }
        return "controls: "
    }

    private static func mediaBranchKinds(
        for request: ParameterStepRequest
    ) -> [MediaKind] {
        let known = Set(request.mediaKinds ?? [])
        let ordered: [MediaKind] = [.image, .video, .pdf, .audio]
        if !known.isEmpty {
            return ordered.filter(known.contains)
        }
        return ordered
    }

    private static func shouldShowMediaBranches(
        for request: ParameterStepRequest
    ) -> Bool {
        if !(request.ambiguousKinds ?? []).isEmpty {
            return true
        }
        return Set(request.mediaKinds ?? []).count > 1
    }

    private static func homogeneousOptimizeMedia(
        for request: ParameterStepRequest
    ) -> OptimizeMediaKind? {
        guard let kind = homogeneousKind(for: request) else {
            return nil
        }
        return OptimizeMediaKind(mediaKind: kind)
    }

    private static func homogeneousKind(
        for request: ParameterStepRequest
    ) -> MediaKind? {
        let kinds = Set(request.mediaKinds ?? [])
        return kinds.count == 1 ? kinds.first : nil
    }

    private static func defaultTitle(for request: ParameterStepRequest) -> String {
        let singular = request.inputs.count == 1
            && request.itemKinds?.first != .folder
            && request.ambiguousKinds?.isEmpty != false
        switch homogeneousKind(for: request) {
        case .image:
            return singular
                ? "Optimize Image with Defaults"
                : "Optimize Images with Defaults"
        case .video:
            return singular
                ? "Optimize Video with Defaults"
                : "Optimize Videos with Defaults"
        case .pdf:
            return singular
                ? "Optimize PDF with Defaults"
                : "Optimize PDFs with Defaults"
        case .audio:
            return "Optimize Audio with Defaults"
        case .folder, .unknown, nil:
            return "Optimize All with Defaults"
        }
    }

    private static func defaultSubtitle(
        for request: ParameterStepRequest
    ) -> String {
        var parts = [inputDescription(for: request)]
        if let media = homogeneousOptimizeMedia(for: request) {
            parts.append(controlHint(for: media))
        }
        parts.append("⏎ Run Defaults")
        parts.append("⇥ Controls")
        return parts.joined(separator: " · ")
    }

    private static func defaultTypingPrompt(
        for media: OptimizeMediaKind
    ) -> String {
        controlHint(for: media)
    }

    private static func controlHint(
        for media: OptimizeMediaKind
    ) -> String {
        switch media {
        case .image:
            return "Use compression 5-100 / ad"
        case .video:
            return "Use 5-100 / au + encoder + m + 2x"
        case .pdf:
            return "Use DPI 300 / 250 / 150 / ad"
        case .audio:
            return "Use compression 5-100 / bitrate (e.g. b128)"
        }
    }

    private static func controlQuery(for request: OptimizeRequest) -> String {
        "\(request.media.rawValue) controls: \(controlSyntax(for: request))"
    }

    private static func controlSyntax(for request: OptimizeRequest) -> String {
        switch request.controls {
        case .image(let controls):
            switch controls.compression {
            case .value(let value):
                return "\(value)"
            case .adaptive:
                return "ad"
            case nil:
                return ""
            }
        case .video(let controls):
            var parts = [String]()
            switch controls.compression {
            case .value(let value):
                parts.append("\(value)")
            case .automatic:
                parts.append("au")
            case nil:
                break
            }
            if let encoder = controls.encoder {
                switch encoder {
                case .hardware:
                    parts.append("hw")
                case .software:
                    parts.append("sw")
                case .lossless:
                    parts.append("ll")
                case .adaptive:
                    parts.append("ad")
                }
            }
            if controls.removeAudio {
                parts.append("m")
            }
            if let speed = controls.playbackSpeed {
                parts.append("\(OptimizeControlParser.displayNumber(speed))x")
            }
            return parts.joined(separator: " ")
        case .pdf(let controls):
            switch controls.dpi {
            case .value(let value):
                return "\(value)"
            case .adaptive:
                return "ad"
            case nil:
                return ""
            }
        case .audio(let controls):
            if let compression = controls.compression {
                return "\(compression)"
            }
            if let bitrate = controls.bitrate {
                return "b\(bitrate)"
            }
            return ""
        }
    }

    private static func emptyControlTitle(for media: OptimizeMediaKind) -> String {
        switch media {
        case .image:
            return "Type a number from 5 to 100"
        case .video:
            return "Type video controls"
        case .pdf:
            return "Type a DPI value"
        case .audio:
            return "Type a number or bitrate"
        }
    }

    private static func emptyControlSubtitle(
        for media: OptimizeMediaKind
    ) -> String {
        switch media {
        case .image:
            return controlHint(for: media)
        case .video:
            return controlHint(for: media)
        case .pdf:
            return controlHint(for: media)
        case .audio:
            return controlHint(for: media)
        }
    }

    private static func invalidControlItem(
        media: OptimizeMediaKind,
        request: ParameterStepRequest
    ) -> ScriptFilterItem {
        ScriptFilterItem(
            title: "Invalid Optimize controls",
            subtitle: [
                inputDescription(for: request),
                emptyControlSubtitle(for: media),
                "⌘L Reference"
            ].joined(separator: " · "),
            arg: "",
            valid: false,
            icon: WorkflowIcon.guide,
            text: ScriptFilterText(
                largetype: largeTypeReference(for: media, request: request)
            )
        )
    }

    private static func largeTypeReference(
        for media: OptimizeMediaKind,
        request: ParameterStepRequest
    ) -> String {
        let inputReference = ScriptFilterAffordance.inputLargeType(request.inputs)
            .map { "\n\nInputs\n\($0)" }
            ?? ""
        return "\(OptimizeControlParser.largeTypeReference(for: media))\(inputReference)"
    }

    private static func acceptedControlSubtitle(
        for media: OptimizeMediaKind
    ) -> String {
        switch media {
        case .image:
            return controlHint(for: media)
        case .video:
            return controlHint(for: media)
        case .pdf:
            return controlHint(for: media)
        case .audio:
            return controlHint(for: media)
        }
    }

    private static var operationVariables: [String: String] {
        [
            ActionMenu.requestKindVariable:
                WorkflowRequestKind.operation.rawValue
        ]
    }

    private static func operationVariables(
        request: ParameterStepRequest,
        stateJSON: String
    ) -> [String: String] {
        var variables = preservedVariables(for: request, stateJSON: stateJSON)
        variables[ActionMenu.requestKindVariable] =
            WorkflowRequestKind.operation.rawValue
        return variables
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

    private static func response(
        items: [ScriptFilterItem],
        request: ParameterStepRequest,
        state: MenuState
    ) -> ScriptFilterResponse {
        let stateJSON = encoded(state)
        let affordance = ScriptFilterAffordance.processingInputs(
            request.inputs,
            itemKinds: request.itemKinds
        )
        return ScriptFilterResponse(
            items: items.map(affordance.apply),
            variables: preservedVariables(for: request, stateJSON: stateJSON),
            skipKnowledge: true
        )
    }

    private static func inputDescription(for request: ParameterStepRequest) -> String {
        request.inputContext.inputDescription(
            inputs: request.inputs,
            itemKinds: request.itemKinds,
            ambiguousKinds: request.ambiguousKinds ?? [],
            processableItemCount: request.processableItemCount
        )
    }

    private static func preservedVariables(
        for request: ParameterStepRequest,
        stateJSON: String
    ) -> [String: String] {
        [
            ActionMenu.inputJSONVariable: menuInputJSON(for: request),
            ActionMenu.inputContextVariable: request.inputContext.rawValue,
            ActionMenu.menuStateVariable: stateJSON
        ]
    }

    private static func menuInputJSON(for request: ParameterStepRequest) -> String {
        (try? JSONOutput.string(
            for: MenuInput(
                paths: request.inputs,
                mediaKinds: request.mediaKinds,
                itemKinds: request.itemKinds,
                ambiguousKinds: request.ambiguousKinds,
                processableItemCount: request.processableItemCount
            ),
            prettyPrinted: false
        )) ?? ""
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

private struct ControlsQuery {
    var media: OptimizeMediaKind
    var prefix: String
    var value: String
}

private extension Array where Element == OptimizeActionPreset {
    func matching(_ query: String) -> [OptimizeActionPreset] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return self
        }
        let search = FuzzySearch<OptimizeActionPreset>(
            query: normalized,
            targetText: { $0.displayValue }
        )
        return search.sorted(self).map { self[$0.targetIndex] }
    }
}

private extension OptimizeMediaKind {
    init?(mediaKind kind: MediaKind) {
        switch kind {
        case .image:
            self = .image
        case .video:
            self = .video
        case .pdf:
            self = .pdf
        case .audio:
            self = .audio
        case .folder, .unknown:
            return nil
        }
    }
}
