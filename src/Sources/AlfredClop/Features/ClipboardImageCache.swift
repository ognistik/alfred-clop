import Foundation

struct ClipboardImageCacheSummary: Equatable {
    var fileCount: Int
    var byteCount: Int64
}

struct ClipboardImageCache {
    var directories: [URL]
    var fileManager: FileManager

    init(
        environment: Environment = Environment(),
        fileManager: FileManager = .default
    ) {
        var directories = [URL]()
        if let cache = environment[
            FoundationClipboardImageMaterializer.workflowCacheEnvironmentKey
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cache.isEmpty {
            directories.append(
                URL(fileURLWithPath: cache, isDirectory: true)
                    .appendingPathComponent("clipboard-images", isDirectory: true)
            )
        }
        directories.append(
            fileManager.temporaryDirectory
                .appendingPathComponent("alfred-clop", isDirectory: true)
                .appendingPathComponent("clipboard-images", isDirectory: true)
        )
        self.directories = directories
            .map(\.standardizedFileURL)
            .reduce(into: []) { result, directory in
                if !result.contains(directory) {
                    result.append(directory)
                }
            }
        self.fileManager = fileManager
    }

    init(directories: [URL], fileManager: FileManager = .default) {
        self.directories = directories
        self.fileManager = fileManager
    }

    var preferredDirectory: URL? {
        directories.first
    }

    func summary() -> ClipboardImageCacheSummary {
        matchingFiles().reduce(
            into: ClipboardImageCacheSummary(fileCount: 0, byteCount: 0)
        ) { summary, file in
            summary.fileCount += 1
            let values = try? file.resourceValues(forKeys: [.fileSizeKey])
            summary.byteCount += Int64(values?.fileSize ?? 0)
        }
    }

    func removeAll() -> ClipboardImageCacheSummary {
        let files = matchingFiles()
        let summary = files.reduce(
            into: ClipboardImageCacheSummary(fileCount: 0, byteCount: 0)
        ) { result, file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey])
            guard (try? fileManager.removeItem(at: file)) != nil else {
                return
            }
            result.fileCount += 1
            result.byteCount += Int64(values?.fileSize ?? 0)
        }
        return summary
    }

    private func matchingFiles() -> [URL] {
        directories.flatMap { directory in
            (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ))?.filter {
                $0.lastPathComponent.hasPrefix("clipboard-")
                    && ["png", "tiff"].contains($0.pathExtension.lowercased())
            } ?? []
        }
    }
}
