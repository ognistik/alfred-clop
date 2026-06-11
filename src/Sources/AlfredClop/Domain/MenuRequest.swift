struct MenuInput: Codable, Equatable {
    var paths: [String]
}

struct ParameterStepRequest: Codable, Equatable {
    var step: String
    var action: ClopAction
    var inputs: [String]

    init(action: ClopAction, inputs: [String]) {
        self.step = "parameters"
        self.action = action
        self.inputs = inputs
    }
}
