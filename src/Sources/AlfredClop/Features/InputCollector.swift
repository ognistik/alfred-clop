import Foundation

enum InputCollectionError: Error, Equatable {
    case invalidJSON
    case noPaths
    case missingPath(String)
}

struct InputCollector {
    var fileManager: FileManager = .default
    var detector = MediaKindDetector()

    func collect(clipboard: ClipboardReading) throws -> InputSelection {
        let fileURLs = clipboard.fileURLs()
        if !fileURLs.isEmpty {
            return try collect(paths: fileURLs.map(\.path))
        }

        guard let clipboardString = clipboard.string() else {
            throw InputCollectionError.noPaths
        }

        return try collect(paths: clipboardPaths(from: clipboardString))
    }

    func collect(json: String) throws -> InputSelection {
        guard let data = json.data(using: .utf8),
              let input = try? JSONDecoder().decode(MenuInput.self, from: data) else {
            throw InputCollectionError.invalidJSON
        }

        return try collect(paths: input.paths)
    }

    func collect(paths: [String]) throws -> InputSelection {
        let paths = expandedAlfredPaths(paths)
        guard !paths.isEmpty else {
            throw InputCollectionError.noPaths
        }

        var seen = Set<String>()
        var inputs: [String] = []
        var mediaKinds: [MediaKind] = []

        for rawPath in paths {
            let expanded = NSString(string: rawPath).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let path = url.path

            guard fileManager.fileExists(atPath: path) else {
                throw InputCollectionError.missingPath(rawPath)
            }
            guard seen.insert(path).inserted else {
                continue
            }

            inputs.append(path)
            mediaKinds.append(detector.kind(for: url))
        }

        guard !inputs.isEmpty else {
            throw InputCollectionError.noPaths
        }

        return InputSelection(inputs: inputs, mediaKinds: mediaKinds)
    }

    private func expandedAlfredPaths(_ paths: [String]) -> [String] {
        guard paths.count == 1, let value = paths.first else {
            return paths
        }
        if fileManager.fileExists(atPath: NSString(string: value).expandingTildeInPath) {
            return paths
        }
        if let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }

        let separated = value
            .split(whereSeparator: { $0 == "\n" || $0 == "\t" })
            .map(String.init)
        return separated.isEmpty ? paths : separated
    }

    private func clipboardPaths(from value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else {
                    return nil
                }
                if let url = URL(string: line), url.isFileURL {
                    return url.path
                }
                return line
            }
    }
}
