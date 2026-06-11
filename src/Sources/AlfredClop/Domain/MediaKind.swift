enum MediaKind: String, Codable, CaseIterable, Equatable {
    case image
    case video
    case audio
    case pdf
    case folder
    case unknown
}
