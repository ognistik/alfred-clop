struct OperationRequest: Codable, Equatable {
    var inputs: [String]
    var action: ActionRequest
    var execution: ExecutionOptions
}
