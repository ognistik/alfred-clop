enum ActionInputContext: String, Codable {
    case selected
    case clipboard
    case arguments

    var subtitlePrefix: String {
        switch self {
        case .selected:
            return "Selected input"
        case .clipboard:
            return "Copied input"
        case .arguments:
            return "Passed input"
        }
    }
}

enum WorkflowRequestKind: String, Codable {
    case operation
    case parameterStep
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
    case execute(action: ActionRequest)

    private enum CodingKeys: String, CodingKey {
        case type
        case action
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
        case let .execute(action):
            try container.encode(RouteType.execute, forKey: .type)
            try container.encode(action, forKey: .action)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(RouteType.self, forKey: .type) {
        case .menu:
            self = .menu(
                action: try? container.decode(ClopAction.self, forKey: .action)
            )
        case .execute:
            self = .execute(
                action: try container.decode(ActionRequest.self, forKey: .action)
            )
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

    init(
        action: ClopAction,
        inputs: [String],
        inputContext: ActionInputContext = .selected,
        mediaKinds: [MediaKind]? = nil,
        itemKinds: [InputItemKind]? = nil,
        ambiguousKinds: [AmbiguousInputKind]? = nil
    ) {
        self.step = "parameters"
        self.action = action
        self.inputs = inputs
        self.inputContext = inputContext
        self.mediaKinds = mediaKinds
        self.itemKinds = itemKinds
        self.ambiguousKinds = ambiguousKinds
    }
}

enum MenuMode: String, Codable, Equatable {
    case actions
    case crop
    case cropPresetRemoval
    case presetMigrationConfirmation
    case presetMigration
    case configuration
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

struct PresetMigrationRequest: Codable, Equatable {
    var sourcePath: String
    var destinationPath: String
    var inputs: [String]
    var mediaKinds: [MediaKind]
    var inputContext: ActionInputContext
    var presetSaveContinuation: PresetSaveContinuation? = nil
}

struct PresetSaveContinuation: Codable, Equatable {
    var request: ParameterStepRequest
    var preset: ActionPreset
    var query: String
}

struct MenuState: Codable, Equatable {
    var mode: MenuMode
    var parameterRequest: ParameterStepRequest?
    var presetAction: PresetMenuAction?
    var presetMigration: PresetMigrationRequest?
    var configurationValue: String?

    init(
        mode: MenuMode,
        parameterRequest: ParameterStepRequest? = nil,
        presetAction: PresetMenuAction? = nil,
        presetMigration: PresetMigrationRequest? = nil,
        configurationValue: String? = nil
    ) {
        self.mode = mode
        self.parameterRequest = parameterRequest
        self.presetAction = presetAction
        self.presetMigration = presetMigration
        self.configurationValue = configurationValue
    }

    static let actions = MenuState(
        mode: .actions
    )

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

    static func presetMigrationConfirmation(
        _ request: PresetMigrationRequest
    ) -> MenuState {
        MenuState(
            mode: .presetMigrationConfirmation,
            presetMigration: request
        )
    }

    static func presetMigration(_ request: PresetMigrationRequest) -> MenuState {
        MenuState(
            mode: .presetMigration,
            presetMigration: request
        )
    }

    static func configuration(
        mode: MenuMode = .configuration,
        value: String? = nil
    ) -> MenuState {
        MenuState(mode: mode, configurationValue: value)
    }
}
