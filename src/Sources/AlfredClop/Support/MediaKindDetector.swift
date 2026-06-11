import Foundation
import UniformTypeIdentifiers

struct MediaKindDetector {
    private let imageExtensions = Set([
        "png", "jpg", "jpeg", "webp", "avif", "heic", "jxl", "bmp",
        "tiff", "tif", "gif"
    ])
    private let videoExtensions = Set([
        "mov", "mp4", "webm", "mkv", "m2v", "avi", "m4v", "mpg", "mpeg"
    ])
    private let audioExtensions = Set([
        "wav", "aiff", "aif", "mp3", "flac", "m4a", "ogg"
    ])

    func kind(for url: URL) -> MediaKind {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           values.isDirectory == true {
            return .folder
        }

        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if contentType.conforms(to: .image) {
                return .image
            }
            if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
                return .video
            }
            if contentType.conforms(to: .audio) {
                return .audio
            }
            if contentType.conforms(to: .pdf) {
                return .pdf
            }
        }

        switch url.pathExtension.lowercased() {
        case let ext where imageExtensions.contains(ext):
            return .image
        case let ext where videoExtensions.contains(ext):
            return .video
        case let ext where audioExtensions.contains(ext):
            return .audio
        case "pdf":
            return .pdf
        default:
            return .unknown
        }
    }
}
