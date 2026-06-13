import Foundation

enum OutputBehavior: Codable, Equatable {
    case inPlace
    case sameFolder(template: String)
    case specificFolder(folder: String, template: String)

    var template: String? {
        switch self {
        case .inPlace:
            return nil
        case let .sameFolder(template):
            return template
        case let .specificFolder(folder, template):
            return URL(fileURLWithPath: folder, isDirectory: true)
                .appendingPathComponent(template)
                .path
        }
    }
}
