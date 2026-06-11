import Foundation
import Testing
@testable import AlfredClop

struct MediaKindDetectorTests {
    private let detector = MediaKindDetector()

    @Test(arguments: [
        ("image.png", MediaKind.image),
        ("movie.mkv", MediaKind.video),
        ("sound.flac", MediaKind.audio),
        ("document.pdf", MediaKind.pdf),
        ("archive.bin", MediaKind.unknown)
    ])
    func detectsFileKindsByExtension(name: String, expected: MediaKind) throws {
        let file = try temporaryFile(named: name)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(detector.kind(for: file) == expected)
    }

    @Test
    func detectsDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(detector.kind(for: directory) == .folder)
    }
}
