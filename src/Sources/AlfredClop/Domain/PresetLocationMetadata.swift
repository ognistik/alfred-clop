struct PresetLocationMetadata: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var lastActiveDirectoryPath: String

    init(
        version: Int = currentVersion,
        lastActiveDirectoryPath: String
    ) {
        self.version = version
        self.lastActiveDirectoryPath = lastActiveDirectoryPath
    }
}
