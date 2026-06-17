enum ActionInputContext: String, Codable {
    case selected
    case clipboard
    case arguments

    var subtitlePrefix: String {
        "\(sourceLabel) input"
    }

    var sourceLabel: String {
        switch self {
        case .selected:
            return "Selected"
        case .clipboard:
            return "Copied"
        case .arguments:
            return "Passed"
        }
    }

    func inputDescription(
        inputs: [String],
        itemKinds: [InputItemKind]? = nil,
        ambiguousKinds: [AmbiguousInputKind] = [],
        processableItemCount: Int? = nil
    ) -> String {
        let kinds = itemKinds ?? Array(repeating: .localFile, count: inputs.count)
        let localCount = kinds.filter { $0 == .localFile }.count
        let folderCount = kinds.filter { $0 == .folder }.count
        let urlCount = kinds.filter { $0 == .remoteURL }.count
        let totalCount = max(inputs.count, kinds.count)

        if totalCount == 0 {
            if ambiguousKinds.contains(.folder) {
                return "\(sourceLabel) folder"
            }
            if ambiguousKinds.contains(.remoteURL) {
                return "\(sourceLabel) URL"
            }
            return subtitlePrefix
        }

        if folderCount == totalCount {
            if folderCount == 1 {
                if let processableItemCount {
                    return "\(sourceLabel) folder: \(processableItemCount) \(fileNoun(processableItemCount))"
                }
                return "\(sourceLabel) folder"
            }
            if let processableItemCount {
                return "\(sourceLabel) \(folderCount) folders: \(processableItemCount) \(fileNoun(processableItemCount))"
            }
            return "\(sourceLabel) \(folderCount) folders"
        }

        if urlCount == totalCount {
            return totalCount == 1
                ? "\(sourceLabel) URL"
                : "\(sourceLabel) \(totalCount) URLs"
        }

        if localCount == totalCount {
            return totalCount == 1
                ? "\(sourceLabel) file"
                : "\(sourceLabel) \(totalCount) files"
        }

        return totalCount == 1
            ? "\(sourceLabel) item"
            : "\(sourceLabel) \(totalCount) items"
    }

    private func fileNoun(_ count: Int) -> String {
        count == 1 ? "file" : "files"
    }
}

enum WorkflowRequestKind: String, Codable {
    case operation
    case parameterStep
    case parameterStepQuery
    case configurationMutation
    case configurationMutationReturn
    case revealSettingsFolder
    case workflowSettings
}

struct MenuInput: Codable, Equatable {
    var paths: [String]
    var mediaKinds: [MediaKind]?
    var itemKinds: [InputItemKind]?
    var ambiguousKinds: [AmbiguousInputKind]?
    var processableItemCount: Int?

    init(
        paths: [String],
        mediaKinds: [MediaKind]? = nil,
        itemKinds: [InputItemKind]? = nil,
        ambiguousKinds: [AmbiguousInputKind]? = nil,
        processableItemCount: Int? = nil
    ) {
        self.paths = paths
        self.mediaKinds = mediaKinds
        self.itemKinds = itemKinds
        self.ambiguousKinds = ambiguousKinds
        self.processableItemCount = processableItemCount
    }
}

struct ClopRequest: Codable, Equatable {
    var version: Int?
    var input: ClopInputRequest
    var route: ClopRouteRequest

    init(
        version: Int? = nil,
        input: ClopInputRequest,
        route: ClopRouteRequest
    ) {
        self.version = version
        self.input = input
        self.route = route
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case input
        case route
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = container.contains(.version)
            ? try container.decode(Int.self, forKey: .version)
            : nil
        input = try container.decode(ClopInputRequest.self, forKey: .input)
        route = try container.decode(ClopRouteRequest.self, forKey: .route)
    }
}

enum ClopInputRequest: Codable, Equatable {
    case clipboard
    case finderSelection
    case explicit(items: [String], extractText: Bool)

    private enum CodingKeys: String, CodingKey {
        case source
        case items
        case extractText
    }

    private enum Source: String, Codable {
        case clipboard
        case finderSelection
        case explicit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clipboard:
            try container.encode(Source.clipboard, forKey: .source)
        case .finderSelection:
            try container.encode(Source.finderSelection, forKey: .source)
        case let .explicit(items, extractText):
            try container.encode(Source.explicit, forKey: .source)
            try container.encode(items, forKey: .items)
            if extractText {
                try container.encode(true, forKey: .extractText)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Source.self, forKey: .source) {
        case .clipboard:
            self = .clipboard
        case .finderSelection:
            self = .finderSelection
        case .explicit:
            self = .explicit(
                items: try container.decode([String].self, forKey: .items),
                extractText: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .extractText
                ) ?? false
            )
        }
    }
}

enum ClopRouteRequest: Codable, Equatable {
    case menu(action: ClopAction?)
    case configuration
    case execute(action: ActionRequest, overrides: ExecutionOverrides? = nil)

    private enum CodingKeys: String, CodingKey {
        case type
        case action
        case destination
        case overrides
    }

    private enum RouteType: String, Codable {
        case menu
        case execute
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .menu(action):
            try container.encode(RouteType.menu, forKey: .type)
            try container.encodeIfPresent(action, forKey: .action)
        case .configuration:
            try container.encode(RouteType.menu, forKey: .type)
            try container.encode("configuration", forKey: .destination)
        case let .execute(action, overrides):
            try container.encode(RouteType.execute, forKey: .type)
            try container.encode(action, forKey: .action)
            try container.encodeIfPresent(overrides, forKey: .overrides)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(RouteType.self, forKey: .type) {
        case .menu:
            if try container.decodeIfPresent(
                String.self,
                forKey: .destination
            ) == "configuration" {
                self = .configuration
                return
            }
            self = .menu(
                action: try? container.decode(ClopAction.self, forKey: .action)
            )
        case .execute:
            self = .execute(
                action: try container.decode(ActionRequest.self, forKey: .action),
                overrides: try container.decodeIfPresent(
                    ExecutionOverrides.self,
                    forKey: .overrides
                )
            )
        }
    }
}

struct ExecutionOverrides: Codable, Equatable {
    var output: OutputOverride?

    init(output: OutputOverride? = nil) {
        self.output = output
    }
}

enum OutputOverride: Codable, Equatable {
    case `default`
    case template
    case customTemplate(String)
    case disabled

    private enum CodingKeys: String, CodingKey {
        case mode
        case template
    }

    private enum Mode: String, Codable {
        case `default`
        case template
        case disabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .default:
            try container.encode(Mode.default, forKey: .mode)
        case .template:
            try container.encode(Mode.template, forKey: .mode)
        case let .customTemplate(template):
            try container.encode(Mode.template, forKey: .mode)
            try container.encode(template, forKey: .template)
        case .disabled:
            try container.encode(Mode.disabled, forKey: .mode)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .default:
            self = .default
        case .template:
            if let template = try container.decodeIfPresent(
                String.self,
                forKey: .template
            ) {
                self = .customTemplate(template)
            } else {
                self = .template
            }
        case .disabled:
            self = .disabled
        }
    }
}

struct ParameterStepRequest: Codable, Equatable {
    var step: String
    var action: ClopAction
    var inputs: [String]
    var inputContext: ActionInputContext
    var mediaKinds: [MediaKind]?
    var itemKinds: [InputItemKind]?
    var ambiguousKinds: [AmbiguousInputKind]?
    var processableItemCount: Int?

    init(
        action: ClopAction,
        inputs: [String],
        inputContext: ActionInputContext = .selected,
        mediaKinds: [MediaKind]? = nil,
        itemKinds: [InputItemKind]? = nil,
        ambiguousKinds: [AmbiguousInputKind]? = nil,
        processableItemCount: Int? = nil
    ) {
        self.step = "parameters"
        self.action = action
        self.inputs = inputs
        self.inputContext = inputContext
        self.mediaKinds = mediaKinds
        self.itemKinds = itemKinds
        self.ambiguousKinds = ambiguousKinds
        self.processableItemCount = processableItemCount
    }
}

enum MenuMode: String, Codable, Equatable {
    case actions
    case optimise
    case optimisePresetRemoval
    case crop
    case cropPresetRemoval
    case downscale
    case downscalePresetRemoval
    case conversion
    case conversionPresetRemoval
    case cropPDF
    case cropPDFPresetRemoval
    case configuration
    case configurationOutputTemplate
    case configurationPresets
    case configurationPresetCategory
    case configurationPresetRemovalConfirmation
    case configurationRemovePreset
    case configurationSaveOutput
    case configurationResetOutputConfirmation
    case configurationResetOutput
    case configurationResetPresetsConfirmation
    case configurationResetPresets
    case configurationCacheCleanupConfirmation
    case configurationCacheCleanup
}

enum PresetMenuActionKind: String, Codable, Equatable {
    case save
    case confirmRemoval
    case remove
}

struct PresetMenuAction: Codable, Equatable {
    var kind: PresetMenuActionKind
    var preset: ActionPreset
}

struct MenuState: Codable, Equatable {
    var mode: MenuMode
    var parameterRequest: ParameterStepRequest?
    var presetAction: PresetMenuAction?
    var configurationValue: String?

    init(
        mode: MenuMode,
        parameterRequest: ParameterStepRequest? = nil,
        presetAction: PresetMenuAction? = nil,
        configurationValue: String? = nil
    ) {
        self.mode = mode
        self.parameterRequest = parameterRequest
        self.presetAction = presetAction
        self.configurationValue = configurationValue
    }

    static let actions = MenuState(
        mode: .actions
    )

    static func optimise(_ request: ParameterStepRequest) -> MenuState {
        MenuState(
            mode: .optimise,
            parameterRequest: request
        )
    }

    static func optimise(
        _ request: ParameterStepRequest,
        action: PresetMenuAction
    ) -> MenuState {
        MenuState(
            mode: action.kind == .confirmRemoval
                ? .optimisePresetRemoval
                : .optimise,
            parameterRequest: request,
            presetAction: action
        )
    }

    static func crop(_ request: ParameterStepRequest) -> MenuState {
        MenuState(
            mode: .crop,
            parameterRequest: request
        )
    }

    static func crop(
        _ request: ParameterStepRequest,
        action: PresetMenuAction
    ) -> MenuState {
        MenuState(
            mode: action.kind == .confirmRemoval
                ? .cropPresetRemoval
                : .crop,
            parameterRequest: request,
            presetAction: action
        )
    }

    static func downscale(_ request: ParameterStepRequest) -> MenuState {
        MenuState(
            mode: .downscale,
            parameterRequest: request
        )
    }

    static func downscale(
        _ request: ParameterStepRequest,
        action: PresetMenuAction
    ) -> MenuState {
        MenuState(
            mode: action.kind == .confirmRemoval
                ? .downscalePresetRemoval
                : .downscale,
            parameterRequest: request,
            presetAction: action
        )
    }

    static func conversion(
        _ request: ParameterStepRequest,
        format: String? = nil
    ) -> MenuState {
        MenuState(
            mode: .conversion,
            parameterRequest: request,
            configurationValue: format
        )
    }

    static func conversion(
        _ request: ParameterStepRequest,
        format: String?,
        action: PresetMenuAction
    ) -> MenuState {
        MenuState(
            mode: action.kind == .confirmRemoval
                ? .conversionPresetRemoval
                : .conversion,
            parameterRequest: request,
            presetAction: action,
            configurationValue: format
        )
    }

    static func cropPDF(_ request: ParameterStepRequest) -> MenuState {
        MenuState(
            mode: .cropPDF,
            parameterRequest: request
        )
    }

    static func cropPDF(
        _ request: ParameterStepRequest,
        action: PresetMenuAction
    ) -> MenuState {
        MenuState(
            mode: action.kind == .confirmRemoval
                ? .cropPDFPresetRemoval
                : .cropPDF,
            parameterRequest: request,
            presetAction: action
        )
    }

    static func configuration(
        mode: MenuMode = .configuration,
        value: String? = nil
    ) -> MenuState {
        MenuState(mode: mode, configurationValue: value)
    }

}
