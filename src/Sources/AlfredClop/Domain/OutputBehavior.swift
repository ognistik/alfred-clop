enum OutputBehavior: Codable, Equatable {
    case inPlace
    case sameFolder(template: String)
    case specificFolder(folder: String, template: String)
}
