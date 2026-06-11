struct ClopDiagnostics: Codable, Equatable {
    var found: Bool
    var path: String?
    var source: String?
    var errors: [String]
}
