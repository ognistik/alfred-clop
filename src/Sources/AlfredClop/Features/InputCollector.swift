import AppKit
import Foundation

enum InputCollectionError: Error, Equatable {
    case invalidJSON
    case noInputs
    case missingPath(String)
    case unsupportedURL(String)
    case credentialedURL(String)
    case emptyFolder(String)
    case unsupportedFolder(String)
    case recursionDisabledFolder(String)
    case unreadableFolder(String)
    case finderSelectionUnavailable
    case emptyFinderSelection
}

struct FolderInspection: Equatable {
    var mediaKinds: [MediaKind]
    var visibleEntryCount: Int
    var supportedItemCount: Int
    var isAmbiguous: Bool
    var foundVisibleEntry: Bool
    var containsSupportedNestedMedia: Bool
}

protocol FolderInspecting {
    func inspect(
        folder: URL,
        recursive: Bool,
        budget: Int
    ) throws -> FolderInspection
}

struct FoundationFolderInspector: FolderInspecting {
    var fileManager: FileManager = .default
    var detector = MediaKindDetector()

    func inspect(
        folder: URL,
        recursive: Bool,
        budget: Int
    ) throws -> FolderInspection {
        var pending = [folder]
        var kinds = [MediaKind]()
        var count = 0
        var supportedItemCount = 0
        var foundVisibleEntry = false
        var skippedDirectories = [URL]()

        while let directory = pending.popLast() {
            let entries: [URL]
            do {
                entries = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isHiddenKey,
                        .isPackageKey,
                        .isSymbolicLinkKey
                    ],
                    options: []
                )
            } catch {
                throw InputCollectionError.unreadableFolder(folder.path)
            }

            for entry in entries.sorted(by: { $0.path < $1.path }) {
                let values: URLResourceValues
                do {
                    values = try entry.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .isHiddenKey,
                        .isPackageKey,
                        .isSymbolicLinkKey
                    ])
                } catch {
                    throw InputCollectionError.unreadableFolder(folder.path)
                }

                if values.isHidden == true || entry.lastPathComponent.hasPrefix(".") {
                    continue
                }
                if values.isSymbolicLink == true {
                    continue
                }
                if values.isDirectory == true, values.isPackage == true {
                    continue
                }

                foundVisibleEntry = true
                if count == budget {
                    return FolderInspection(
                        mediaKinds: kinds,
                        visibleEntryCount: count,
                        supportedItemCount: supportedItemCount,
                        isAmbiguous: true,
                        foundVisibleEntry: true,
                        containsSupportedNestedMedia: false
                    )
                }
                count += 1

                if values.isDirectory == true {
                    if recursive {
                        pending.append(entry)
                    } else {
                        skippedDirectories.append(entry)
                    }
                    continue
                }

                let kind = detector.kind(for: entry)
                if kind != .unknown, !kinds.contains(kind) {
                    kinds.append(kind)
                }
                if kind != .unknown {
                    supportedItemCount += 1
                }
            }
        }

        let containsSupportedNestedMedia = !recursive
            && kinds.isEmpty
            && skippedDirectories.contains(where: containsSupportedMedia)

        return FolderInspection(
            mediaKinds: kinds,
            visibleEntryCount: count,
            supportedItemCount: supportedItemCount,
            isAmbiguous: false,
            foundVisibleEntry: foundVisibleEntry,
            containsSupportedNestedMedia: containsSupportedNestedMedia
        )
    }

    private func containsSupportedMedia(in root: URL) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isHiddenKey,
                .isPackageKey,
                .isSymbolicLinkKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        var inspected = 0
        for case let entry as URL in enumerator {
            guard inspected < InputCollector.folderInspectionBudget else {
                return false
            }
            inspected += 1
            guard let values = try? entry.resourceValues(forKeys: [
                .isDirectoryKey,
                .isHiddenKey,
                .isPackageKey,
                .isSymbolicLinkKey
            ]) else {
                continue
            }
            if values.isSymbolicLink == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values.isDirectory == true {
                continue
            }
            if detector.kind(for: entry) != .unknown {
                return true
            }
        }
        return false
    }
}

protocol FinderSelectionReading {
    func selectedItems() throws -> [String]
}

struct SystemFinderSelectionReader: FinderSelectionReading {
    func selectedItems() throws -> [String] {
        let source = """
        tell application "Finder"
            set selectedItems to selection
            set output to ""
            repeat with selectedItem in selectedItems
                set output to output & POSIX path of (selectedItem as alias) & linefeed
            end repeat
            return output
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?
            .executeAndReturnError(&error)
            .stringValue else {
            throw InputCollectionError.finderSelectionUnavailable
        }
        return result
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}

struct InputCollector {
    static let folderInspectionBudget = 500

    var fileManager: FileManager = .default
    var detector = MediaKindDetector()
    var folderInspector: any FolderInspecting = FoundationFolderInspector()
    var clipboardImageMaterializer: any ClipboardImageMaterializing =
        FoundationClipboardImageMaterializer()
    var clipboardHistory: any ClipboardHistoryReading =
        AlfredClipboardHistoryReader()

    func collect(
        request: ClopInputRequest,
        clipboard: ClipboardReading,
        finder: any FinderSelectionReading,
        recursiveFolders: Bool,
        allowClipboardHistoryFallback: Bool = false
    ) throws -> InputSelection {
        switch request {
        case .clipboard:
            return try collect(
                clipboard: clipboard,
                recursiveFolders: recursiveFolders,
                allowHistoryFallback: allowClipboardHistoryFallback
            )
        case .finderSelection:
            let items = try finder.selectedItems()
            guard !items.isEmpty else {
                throw InputCollectionError.emptyFinderSelection
            }
            return try collect(
                items: items,
                extractText: false,
                recursiveFolders: recursiveFolders
            )
        case let .explicit(items, extractText):
            return try collect(
                items: items,
                extractText: extractText,
                recursiveFolders: recursiveFolders
            )
        }
    }

    func collect(
        clipboard: ClipboardReading,
        recursiveFolders: Bool = false,
        allowHistoryFallback: Bool = false
    ) throws -> InputSelection {
        do {
            let selection = try collectCurrentClipboard(
                clipboard,
                recursiveFolders: recursiveFolders
            )
            guard allowHistoryFallback,
                  ActionCatalog.validActions(for: selection).isEmpty,
                  let recovered = recoveredClipboardSelection(
                    recursiveFolders: recursiveFolders
                  ) else {
                return selection
            }
            return recovered
        } catch {
            guard allowHistoryFallback,
                  let recovered = recoveredClipboardSelection(
                    recursiveFolders: recursiveFolders
                  ) else {
                throw error
            }
            return recovered
        }
    }

    private func collectCurrentClipboard(
        _ clipboard: ClipboardReading,
        recursiveFolders: Bool
    ) throws -> InputSelection {
        let fileURLs = clipboard.fileURLs()
        if !fileURLs.isEmpty {
            return try collect(
                items: fileURLs.map(\.path),
                extractText: false,
                recursiveFolders: recursiveFolders
            )
        }

        if let clipboardString = clipboard.string() {
            do {
                return try collect(
                    items: [clipboardString],
                    extractText: true,
                    recursiveFolders: recursiveFolders
                )
            } catch InputCollectionError.noInputs {
                // Unrelated text can coexist with a useful image representation.
            }
        }

        if let image = clipboard.image(),
           let fileURL = try? clipboardImageMaterializer.materialize(image) {
            return try collect(
                items: [fileURL.path],
                extractText: false,
                recursiveFolders: recursiveFolders
            )
        }

        throw InputCollectionError.noInputs
    }

    private func recoveredClipboardSelection(
        recursiveFolders: Bool
    ) -> InputSelection? {
        guard let reader = try? clipboardHistory.makeCandidateReader() else {
            return nil
        }
        while true {
            let candidate: ClipboardHistoryCandidate?
            do {
                candidate = try reader.next()
            } catch {
                return nil
            }
            guard let candidate else {
                return nil
            }
            let selection: InputSelection
            do {
                switch candidate {
                case .text(let text):
                    selection = try collect(
                        items: [text],
                        extractText: true,
                        recursiveFolders: recursiveFolders
                    )
                case .files(let paths):
                    selection = try collect(
                        items: paths,
                        extractText: false,
                        recursiveFolders: recursiveFolders
                    )
                case .image(let image):
                    let fileURL = try clipboardImageMaterializer.materialize(image)
                    selection = try collect(
                        items: [fileURL.path],
                        extractText: false,
                        recursiveFolders: recursiveFolders
                    )
                }
            } catch {
                continue
            }
            guard !ActionCatalog.validActions(for: selection).isEmpty else {
                continue
            }
            var recovered = selection
            recovered.recoveredFromClipboardHistory = true
            return recovered
        }
    }

    func collect(json: String) throws -> InputSelection {
        guard let data = json.data(using: .utf8),
              let input = try? JSONDecoder().decode(MenuInput.self, from: data) else {
            throw InputCollectionError.invalidJSON
        }

        if let mediaKinds = input.mediaKinds,
           let itemKinds = input.itemKinds,
           let ambiguousKinds = input.ambiguousKinds {
            return InputSelection(
                inputs: input.paths,
                mediaKinds: mediaKinds,
                itemKinds: itemKinds,
                ambiguousKinds: ambiguousKinds,
                processableItemCount: input.processableItemCount
            )
        }
        return try collect(paths: input.paths)
    }

    func collect(paths: [String]) throws -> InputSelection {
        try collect(
            items: expandedAlfredItems(paths),
            extractText: false,
            recursiveFolders: false
        )
    }

    func collect(
        items: [String],
        extractText: Bool,
        recursiveFolders: Bool
    ) throws -> InputSelection {
        let candidates: [String]
        if extractText {
            candidates = try items.flatMap { value in
                if isExistingPath(value) || isStandaloneURL(value) {
                    return [value]
                }
                let expanded = expandedAlfredItems([value])
                if expanded.count > 1,
                   expanded.allSatisfy({
                       isExistingPath($0) || isStandaloneURL($0)
                   }) {
                    return expanded
                }
                return try extractInputs(from: value)
            }
        } else {
            candidates = expandedAlfredItems(items)
        }
        guard !candidates.isEmpty else {
            throw InputCollectionError.noInputs
        }

        var seen = Set<String>()
        var inputs = [String]()
        var mediaKinds = [MediaKind]()
        var itemKinds = [InputItemKind]()
        var ambiguousKinds = [AmbiguousInputKind]()
        var processableItemCount = 0
        var hasAmbiguousCount = false

        for candidate in candidates {
            if let remoteURL = try validatedRemoteURL(candidate) {
                let value = remoteURL.absoluteString
                guard seen.insert(value).inserted else {
                    continue
                }
                inputs.append(value)
                itemKinds.append(.remoteURL)
                let kind = detector.kind(for: remoteURL)
                if kind == .unknown {
                    if !ambiguousKinds.contains(.remoteURL) {
                        ambiguousKinds.append(.remoteURL)
                    }
                } else {
                    mediaKinds.append(kind)
                }
                processableItemCount += 1
                continue
            }

            let pathValue: String
            if let url = URL(string: candidate), url.isFileURL {
                pathValue = url.path
            } else {
                pathValue = candidate
            }
            let expanded = NSString(string: pathValue).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let path = url.path

            guard fileManager.fileExists(atPath: path) else {
                throw InputCollectionError.missingPath(candidate)
            }
            guard seen.insert(path).inserted else {
                continue
            }

            let kind = detector.kind(for: url)
            if kind == .folder {
                let inspection = try folderInspector.inspect(
                    folder: url,
                    recursive: recursiveFolders,
                    budget: Self.folderInspectionBudget
                )
                if !inspection.foundVisibleEntry {
                    throw InputCollectionError.emptyFolder(candidate)
                }
                if inspection.mediaKinds.isEmpty, !inspection.isAmbiguous {
                    if inspection.containsSupportedNestedMedia {
                        throw InputCollectionError.recursionDisabledFolder(candidate)
                    }
                    throw InputCollectionError.unsupportedFolder(candidate)
                }
                inputs.append(path)
                itemKinds.append(.folder)
                for mediaKind in inspection.mediaKinds where !mediaKinds.contains(mediaKind) {
                    mediaKinds.append(mediaKind)
                }
                if inspection.isAmbiguous, !ambiguousKinds.contains(.folder) {
                    ambiguousKinds.append(.folder)
                }
                if inspection.isAmbiguous {
                    hasAmbiguousCount = true
                } else {
                    processableItemCount += inspection.supportedItemCount
                }
            } else {
                inputs.append(path)
                itemKinds.append(.localFile)
                mediaKinds.append(kind)
                processableItemCount += 1
            }
        }

        guard !inputs.isEmpty else {
            throw InputCollectionError.noInputs
        }

        return InputSelection(
            inputs: inputs,
            mediaKinds: mediaKinds,
            itemKinds: itemKinds,
            ambiguousKinds: ambiguousKinds,
            processableItemCount: hasAmbiguousCount ? nil : processableItemCount
        )
    }

    private func expandedAlfredItems(_ items: [String]) -> [String] {
        guard items.count == 1, let value = items.first else {
            return items
        }
        if isExistingPath(value) || isStandaloneURL(value) {
            return items
        }
        if let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }

        let separated = value
            .split(whereSeparator: { $0 == "\n" || $0 == "\t" })
            .map(String.init)
        return separated.isEmpty ? items : separated
    }

    private func extractInputs(from text: String) throws -> [String] {
        var matches = [(range: Range<String.Index>, value: String)]()
        let wrappedPattern = #"(["'`])((?:file://|/|~/).*?)\1"#
        let urlPattern = #"[A-Za-z][A-Za-z0-9+.-]*://[^\s"'`<>]+"#
        let pathPattern = #"(?<![\w])(?:~/|/)[^\s"'`<>]+"#

        for pattern in [wrappedPattern, urlPattern, pathPattern] {
            let expression = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            for result in expression.matches(in: text, range: range) {
                let capture = pattern == wrappedPattern ? 2 : 0
                guard let matchRange = Range(result.range(at: capture), in: text) else {
                    continue
                }
                let value = trimTrailingPunctuation(String(text[matchRange]))
                if pattern == pathPattern, !isPlausibleExtractedPath(value) {
                    continue
                }
                let fullRange = Range(result.range, in: text) ?? matchRange
                if matches.contains(where: { $0.range.overlaps(fullRange) }) {
                    continue
                }
                if isURLLike(value) {
                    _ = try validatedRemoteURL(value)
                }
                matches.append((fullRange, value))
            }
        }

        return matches
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map(\.value)
    }

    private func validatedRemoteURL(_ value: String) throws -> URL? {
        guard isURLLike(value), let url = URL(string: value) else {
            return nil
        }
        if url.isFileURL {
            return nil
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw InputCollectionError.unsupportedURL(value)
        }
        guard url.user == nil, url.password == nil else {
            throw InputCollectionError.credentialedURL(value)
        }
        guard url.host != nil else {
            throw InputCollectionError.unsupportedURL(value)
        }
        return url
    }

    private func isExistingPath(_ value: String) -> Bool {
        fileManager.fileExists(
            atPath: NSString(string: value).expandingTildeInPath
        )
    }

    private func isPlausibleExtractedPath(_ value: String) -> Bool {
        if value.hasPrefix("~/") {
            return true
        }
        guard value.hasPrefix("/") else {
            return false
        }
        let withoutLeadingSlash = value.dropFirst()
        return withoutLeadingSlash.contains("/") || isExistingPath(value)
    }

    private func isURLLike(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#,
            options: .regularExpression
        ) != nil
    }

    private func isStandaloneURL(_ value: String) -> Bool {
        isURLLike(value) && !value.contains(where: \.isWhitespace)
    }

    private func trimTrailingPunctuation(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
    }
}
