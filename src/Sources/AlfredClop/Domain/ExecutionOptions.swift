struct ExecutionOptions: Codable, Equatable {
    var showClopUI: Bool
    var copyResult: Bool
    var output: OutputBehavior
    var backup: BackupBehavior
    var adaptiveOptimisation: String?
    var pdfDPI: String?
    var recursiveFolders: Bool
    var aggressiveProcessing: Bool?

    init(
        showClopUI: Bool,
        copyResult: Bool,
        output: OutputBehavior,
        backup: BackupBehavior,
        adaptiveOptimisation: String?,
        pdfDPI: String?,
        recursiveFolders: Bool = false,
        aggressiveProcessing: Bool? = nil
    ) {
        self.showClopUI = showClopUI
        self.copyResult = copyResult
        self.output = output
        self.backup = backup
        self.adaptiveOptimisation = adaptiveOptimisation
        self.pdfDPI = pdfDPI
        self.recursiveFolders = recursiveFolders
        self.aggressiveProcessing = aggressiveProcessing
    }
}
