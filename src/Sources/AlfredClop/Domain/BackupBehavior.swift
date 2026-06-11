enum BackupBehavior: Codable, Equatable {
    case trustClop
    case none
    case workflowCopy(folder: String?)
}
