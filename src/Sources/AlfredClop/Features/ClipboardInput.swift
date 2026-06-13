import AppKit
import CryptoKit
import Foundation

struct ClipboardImage: Equatable {
    enum Format: String {
        case png
        case tiff
    }

    var data: Data
    var format: Format
}

protocol ClipboardReading {
    func fileURLs() -> [URL]
    func string() -> String?
    func image() -> ClipboardImage?
}

extension ClipboardReading {
    func image() -> ClipboardImage? {
        nil
    }
}

protocol ClipboardImageMaterializing {
    func materialize(_ image: ClipboardImage) throws -> URL
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

    func image() -> ClipboardImage? {
        for (type, format) in [
            (NSPasteboard.PasteboardType.png, ClipboardImage.Format.png),
            (.tiff, .tiff)
        ] {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return ClipboardImage(data: data, format: format)
            }
        }
        return nil
    }
}

struct FoundationClipboardImageMaterializer: ClipboardImageMaterializing {
    static let workflowCacheEnvironmentKey = "alfred_workflow_cache"
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    var directoryURL: URL
    var fileManager: FileManager
    var now: () -> Date

    init(
        environment: Environment = Environment(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        let cachePath = environment[Self.workflowCacheEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let root: URL
        if let cachePath, !cachePath.isEmpty {
            root = URL(fileURLWithPath: cachePath, isDirectory: true)
        } else {
            root = fileManager.temporaryDirectory
                .appendingPathComponent("alfred-clop", isDirectory: true)
        }
        self.directoryURL = root
            .appendingPathComponent("clipboard-images", isDirectory: true)
        self.fileManager = fileManager
        self.now = now
    }

    init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.now = now
    }

    func materialize(_ image: ClipboardImage) throws -> URL {
        guard !image.data.isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
        removeExpiredFiles()

        let digest = SHA256.hash(data: image.data)
            .map { String(format: "%02x", $0) }
            .joined()
        let fileURL = directoryURL
            .appendingPathComponent("clipboard-\(digest)")
            .appendingPathExtension(image.format.rawValue)

        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        try image.data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        return fileURL
    }

    private func removeExpiredFiles() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = now().addingTimeInterval(-Self.retentionInterval)
        for file in files {
            guard file.lastPathComponent.hasPrefix("clipboard-"),
                  let values = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                  ),
                  let modified = values.contentModificationDate,
                  modified < cutoff else {
                continue
            }
            try? fileManager.removeItem(at: file)
        }
    }
}
