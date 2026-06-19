import Foundation
import SQLite3
import Testing
@testable import AlfredClop

struct ClipboardHistoryTests {
    @Test
    func alfredDatabaseReaderDecodesFilesImagesAndTextNewestFirst() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("clipboard.alfdb")
        let attachmentsURL = directory.appendingPathComponent(
            "clipboard.alfdb.data",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: attachmentsURL,
            withIntermediateDirectories: false
        )

        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        let openedDatabase = try #require(database)
        defer { sqlite3_close(openedDatabase) }
        try execute(
            "CREATE TABLE clipboard(item, ts decimal, app, apppath, dataType integer, dataHash)",
            in: openedDatabase
        )

        let paths = ["/tmp/first image.png", "/tmp/second.pdf"]
        let plist = try PropertyListEncoder().encode(paths)
        try plist.write(to: attachmentsURL.appendingPathComponent("files.plist"))
        let image = Data("stored tiff".utf8)
        try image.write(to: attachmentsURL.appendingPathComponent("image.tiff"))
        try execute(
            """
            INSERT INTO clipboard VALUES ('Broken', 4, '', '', 2, 'missing.plist');
            INSERT INTO clipboard VALUES ('Files', 3, '', '', 2, 'files.plist');
            INSERT INTO clipboard VALUES ('Image', 2, '', '', 1, 'image.tiff');
            INSERT INTO clipboard VALUES ('https://example.com/photo.png', 1, '', '', 0, NULL);
            """,
            in: openedDatabase
        )

        let reader = try AlfredClipboardHistoryReader(
            databaseURL: databaseURL,
            attachmentsURL: attachmentsURL
        ).makeCandidateReader()

        #expect(try reader.next() == .files(paths))
        #expect(
            try reader.next()
                == .image(ClipboardImage(data: image, format: .tiff))
        )
        #expect(try reader.next() == .text("https://example.com/photo.png"))
        #expect(try reader.next() == nil)
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            throw ClipboardHistoryError.database(message)
        }
    }
}
