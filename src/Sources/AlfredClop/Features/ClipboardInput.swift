import AppKit
import Foundation

protocol ClipboardReading {
    func fileURLs() -> [URL]
    func string() -> String?
}

struct SystemClipboardReader: ClipboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func fileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []
        return objects.compactMap { object in
            (object as? NSURL) as URL?
        }
    }

    func string() -> String? {
        pasteboard.string(forType: .string)
    }
}
