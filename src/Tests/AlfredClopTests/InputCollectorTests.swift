import Foundation
import Testing
@testable import AlfredClop

struct InputCollectorTests {
    @Test
    func clipboardNativeFileURLsUseExistingInputPipeline() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let clipboard = StubClipboard(
            urls: [file, file],
            text: "/ignored/path.jpg"
        )

        let selection = try InputCollector().collect(clipboard: clipboard)

        #expect(selection.inputs == [file.standardizedFileURL.path])
        #expect(selection.mediaKinds == [.image])
    }

    @Test
    func clipboardAcceptsFileURLsAndNewlineSeparatedPaths() throws {
        let first = try temporaryFile(named: "first.png")
        let second = first.deletingLastPathComponent().appendingPathComponent("second.pdf")
        try Data().write(to: second)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        let clipboard = StubClipboard(
            text: "\(first.absoluteString)\n\(second.path)\n\(first.path)"
        )

        let selection = try InputCollector().collect(clipboard: clipboard)

        #expect(selection.inputs == [
            first.standardizedFileURL.path,
            second.standardizedFileURL.path
        ])
        #expect(selection.mediaKinds == [.image, .pdf])
    }

    @Test
    func clipboardAcceptsSingleCopiedPath() throws {
        let file = try temporaryFile(named: "movie.mp4")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let selection = try InputCollector().collect(
            clipboard: StubClipboard(text: "  \(file.path)  ")
        )

        #expect(selection.inputs == [file.standardizedFileURL.path])
        #expect(selection.mediaKinds == [.video])
    }

    @Test
    func validPathsJSONDecodesAndNormalizes() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let input = MenuInput(paths: [file.path, file.path])
        let json = try JSONOutput.string(for: input, prettyPrinted: false)

        let selection = try InputCollector().collect(json: json)

        #expect(selection.inputs == [file.standardizedFileURL.path])
        #expect(selection.mediaKinds == [.image])
    }

    @Test
    func invalidJSONProducesAlfredErrorResponse() {
        let response = ActionMenu.response(inputJSON: "{bad json", query: "")

        #expect(response.items.count == 1)
        #expect(response.items[0].title == "Unable to read selected files")
        #expect(response.items[0].valid == false)
    }

    @Test
    func alfredSerializedPathsAreExpanded() throws {
        let first = try temporaryFile(named: "first.png")
        let second = first.deletingLastPathComponent().appendingPathComponent("second.jpg")
        try Data().write(to: second)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }

        let selection = try InputCollector().collect(
            paths: ["\(first.path)\t\(second.path)"]
        )

        #expect(selection.inputs.count == 2)
        #expect(selection.mediaKinds == [.image, .image])
    }

    @Test
    func JSONSerializedAlfredPathsAreExpanded() throws {
        let file = try temporaryFile(named: "image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let serialized = try JSONOutput.string(
            for: [file.path],
            prettyPrinted: false
        )

        let selection = try InputCollector().collect(paths: [serialized])

        #expect(selection.inputs == [file.resolvingSymlinksInPath().path])
    }

    @Test
    func newlineSeparatedArgumentPathsAreExpanded() throws {
        let first = try temporaryFile(named: "first.png")
        let second = first.deletingLastPathComponent().appendingPathComponent("second.pdf")
        try Data().write(to: second)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }

        let selection = try InputCollector().collect(
            paths: ["\(first.path)\n\(second.path)"]
        )

        #expect(selection.inputs == [
            first.standardizedFileURL.path,
            second.standardizedFileURL.path
        ])
        #expect(selection.mediaKinds == [.image, .pdf])
    }

    @Test
    func proseExtractsURLsAndSupportedPathFormsInOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let spaced = directory.appendingPathComponent("first image.png")
        let plain = directory.appendingPathComponent("second.pdf")
        try Data().write(to: spaced)
        try Data().write(to: plain)
        let text = """
        Try https://example.com/video.mp4?download=1#preview, then "\(spaced.path)".
        The PDF is \(plain.path)
        """

        let selection = try InputCollector().collect(
            items: [text],
            extractText: true,
            recursiveFolders: false
        )

        #expect(selection.inputs == [
            "https://example.com/video.mp4?download=1#preview",
            spaced.path,
            plain.path
        ])
        #expect(selection.mediaKinds == [.video, .image, .pdf])
        #expect(selection.itemKinds == [.remoteURL, .localFile, .localFile])
    }

    @Test
    func explicitItemsAreExactRatherThanProse() {
        #expect(throws: InputCollectionError.missingPath(
            "Open /tmp/photo.png please"
        )) {
            try InputCollector().collect(
                items: ["Open /tmp/photo.png please"],
                extractText: false,
                recursiveFolders: false
            )
        }
    }

    @Test
    func URLValidationRejectsCredentialsAndUnsupportedSchemes() {
        #expect(throws: InputCollectionError.credentialedURL(
            "https://user:secret@example.com/photo.png"
        )) {
            try InputCollector().collect(
                items: ["https://user:secret@example.com/photo.png"],
                extractText: false,
                recursiveFolders: false
            )
        }
        #expect(throws: InputCollectionError.unsupportedURL(
            "ftp://example.com/photo.png"
        )) {
            try InputCollector().collect(
                items: ["ftp://example.com/photo.png"],
                extractText: false,
                recursiveFolders: false
            )
        }
    }

    @Test
    func extensionlessHTTPURLRemainsAmbiguous() throws {
        let selection = try InputCollector().collect(
            items: ["https://example.com/download?asset=42#latest"],
            extractText: false,
            recursiveFolders: false
        )

        #expect(selection.inputs == [
            "https://example.com/download?asset=42#latest"
        ])
        #expect(selection.mediaKinds.isEmpty)
        #expect(selection.ambiguousKinds == [.remoteURL])
    }

    @Test
    func folderInspectionUsesImmediateContentsWhenRecursionIsDisabled() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nested,
            withIntermediateDirectories: false
        )
        try Data().write(to: nested.appendingPathComponent("photo.png"))

        #expect(throws: InputCollectionError.recursionDisabledFolder(root.path)) {
            try InputCollector().collect(
                items: [root.path],
                extractText: false,
                recursiveFolders: false
            )
        }

        let recursive = try InputCollector().collect(
            items: [root.path],
            extractText: false,
            recursiveFolders: true
        )
        #expect(recursive.mediaKinds == [.image])
        #expect(recursive.itemKinds == [.folder])
        #expect(recursive.processableItemCount == 1)
    }

    @Test
    func folderSelectionCountsSupportedFilesWhenInspectionCompletes() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("one.png"))
        try Data().write(to: root.appendingPathComponent("two.mp4"))
        try Data().write(to: root.appendingPathComponent("notes.txt"))

        let selection = try InputCollector().collect(
            items: [root.path],
            extractText: false,
            recursiveFolders: false
        )

        #expect(selection.processableItemCount == 2)
    }

    @Test
    func emptyUnsupportedAndUnreadableFoldersAreDistinct() throws {
        let empty = try makeTemporaryDirectory()
        let unsupported = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: empty)
            try? FileManager.default.removeItem(at: unsupported)
        }
        try Data().write(to: unsupported.appendingPathComponent("notes.txt"))

        #expect(throws: InputCollectionError.emptyFolder(empty.path)) {
            try InputCollector().collect(
                items: [empty.path],
                extractText: false,
                recursiveFolders: false
            )
        }
        #expect(throws: InputCollectionError.unsupportedFolder(
            unsupported.path
        )) {
            try InputCollector().collect(
                items: [unsupported.path],
                extractText: false,
                recursiveFolders: false
            )
        }

        let unreadableCollector = InputCollector(
            folderInspector: StubFolderInspector(
                error: .unreadableFolder(unsupported.path)
            )
        )
        #expect(throws: InputCollectionError.unreadableFolder(
            unsupported.path
        )) {
            try unreadableCollector.collect(
                items: [unsupported.path],
                extractText: false,
                recursiveFolders: false
            )
        }
    }

    @Test
    func folderBudgetMarksTheInputAmbiguousAtFiveHundredEntries() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<501 {
            try Data().write(
                to: root.appendingPathComponent(
                    String(format: "%03d.txt", index)
                )
            )
        }

        let selection = try InputCollector().collect(
            items: [root.path],
            extractText: false,
            recursiveFolders: false
        )

        #expect(selection.mediaKinds.isEmpty)
        #expect(selection.ambiguousKinds == [.folder])
        #expect(selection.processableItemCount == nil)
    }

    @Test
    func folderScannerIgnoresHiddenPackagesAndDirectorySymlinks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent(".hidden.png"))
        let package = root.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: package,
            withIntermediateDirectories: false
        )
        try Data().write(to: package.appendingPathComponent("inside.png"))
        let ordinary = root.appendingPathComponent("ordinary", isDirectory: true)
        try FileManager.default.createDirectory(
            at: ordinary,
            withIntermediateDirectories: false
        )
        try Data().write(to: ordinary.appendingPathComponent("inside.pdf"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"),
            withDestinationURL: ordinary
        )
        try Data().write(to: root.appendingPathComponent("visible.jpg"))

        let inspection = try FoundationFolderInspector().inspect(
            folder: root,
            recursive: true,
            budget: 500
        )

        #expect(Set(inspection.mediaKinds) == [.image, .pdf])
        #expect(inspection.visibleEntryCount == 3)
        #expect(!inspection.isAmbiguous)
    }

    @Test
    func emptyFinderSelectionDoesNotUseClipboardFallback() {
        let clipboard = StubClipboard(text: "https://example.com/photo.png")

        #expect(throws: InputCollectionError.emptyFinderSelection) {
            try InputCollector().collect(
                request: .finderSelection,
                clipboard: clipboard,
                finder: StubFinderSelection(items: []),
                recursiveFolders: false
            )
        }
    }
}

private struct StubClipboard: ClipboardReading {
    var urls: [URL] = []
    var text: String?

    func fileURLs() -> [URL] {
        urls
    }

    func string() -> String? {
        text
    }
}

private struct StubFinderSelection: FinderSelectionReading {
    var items: [String]

    func selectedItems() throws -> [String] {
        items
    }
}

private struct StubFolderInspector: FolderInspecting {
    var error: InputCollectionError

    func inspect(
        folder: URL,
        recursive: Bool,
        budget: Int
    ) throws -> FolderInspection {
        throw error
    }
}
