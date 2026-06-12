enum ActionInputContext: String, Codable {
    case selected
    case clipboard
    case arguments

    var subtitlePrefix: String {
        switch self {
        case .selected:
            return "Selected files"
        case .clipboard:
            return "Copied files"
        case .arguments:
            return "Passed files"
        }
    }
}

enum WorkflowRequestKind: String, Codable {
    case operation
    case parameterStep
}

struct MenuInput: Codable, Equatable {
    var paths: [String]
}

struct ParameterStepRequest: Codable, Equatable {
    var step: String
    var action: ClopAction
    var inputs: [String]
    var inputContext: ActionInputContext

    init(
        action: ClopAction,
        inputs: [String],
        inputContext: ActionInputContext = .selected
    ) {
        self.step = "parameters"
        self.action = action
        self.inputs = inputs
        self.inputContext = inputContext
    }
}

enum MenuMode: String, Codable, Equatable {
    case actions
    case crop
    case cropPresetRemoval
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

    static let actions = MenuState(
        mode: .actions,
        parameterRequest: nil,
        presetAction: nil
    )

    static func crop(_ request: ParameterStepRequest) -> MenuState {
        MenuState(
            mode: .crop,
            parameterRequest: request,
            presetAction: nil
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
}
