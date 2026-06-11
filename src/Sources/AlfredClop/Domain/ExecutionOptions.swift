struct ExecutionOptions: Codable, Equatable {
    var showClopUI: Bool
    var copyResult: Bool
    var output: OutputBehavior
    var backup: BackupBehavior
    var adaptiveOptimisation: String?
    var pdfDPI: String?
}
