import Foundation
import SQLite3

enum ClipboardHistoryCandidate: Equatable {
    case text(String)
    case files([String])
    case image(ClipboardImage)
}

protocol ClipboardHistoryCandidateReading: AnyObject {
    func next() throws -> ClipboardHistoryCandidate?
}

protocol ClipboardHistoryReading {
    func makeCandidateReader() throws -> any ClipboardHistoryCandidateReading
}

enum ClipboardHistoryError: Error {
    case unavailable
    case database(String)
}

struct AlfredClipboardHistoryReader: ClipboardHistoryReading {
    var databaseURL: URL
    var attachmentsURL: URL
    var fileManager: FileManager

    init(
        databaseURL: URL? = nil,
        attachmentsURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedDatabase = databaseURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Alfred/Databases/clipboard.alfdb")
        self.databaseURL = resolvedDatabase
        self.attachmentsURL = attachmentsURL
            ?? URL(fileURLWithPath: resolvedDatabase.path + ".data", isDirectory: true)
        self.fileManager = fileManager
    }

    func makeCandidateReader() throws -> any ClipboardHistoryCandidateReading {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw ClipboardHistoryError.unavailable
        }
        return try SQLiteClipboardHistoryCandidateReader(
            databaseURL: databaseURL,
            attachmentsURL: attachmentsURL
        )
    }
}

private final class SQLiteClipboardHistoryCandidateReader: ClipboardHistoryCandidateReading {
    private var database: OpaquePointer?
    private var statement: OpaquePointer?
    private let attachmentsURL: URL

    init(databaseURL: URL, attachmentsURL: URL) throws {
        self.attachmentsURL = attachmentsURL.standardizedFileURL

        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Unable to open database"
            if let database {
                sqlite3_close(database)
            }
            self.database = nil
            throw ClipboardHistoryError.database(message)
        }

        sqlite3_busy_timeout(database, 100)
        let sql = """
        SELECT dataType, item, dataHash
        FROM clipboard
        WHERE dataType IN (0, 1, 2)
        ORDER BY ts DESC, rowid DESC
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(database))
            sqlite3_close(database)
            self.database = nil
            throw ClipboardHistoryError.database(message)
        }
    }

    deinit {
        if let statement {
            sqlite3_finalize(statement)
        }
        if let database {
            sqlite3_close(database)
        }
    }

    func next() throws -> ClipboardHistoryCandidate? {
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return nil
            }
            guard result == SQLITE_ROW else {
                let message = database.map { String(cString: sqlite3_errmsg($0)) }
                    ?? "Unable to read database"
                throw ClipboardHistoryError.database(message)
            }

            let dataType = sqlite3_column_int(statement, 0)
            guard let item = text(at: 1) else {
                continue
            }
            switch dataType {
            case 0:
                guard !item.isEmpty else {
                    continue
                }
                return .text(item)
            case 1:
                guard let attachment = attachmentURL(
                    hash: text(at: 2),
                    extension: "tiff"
                ), let data = try? Data(contentsOf: attachment), !data.isEmpty else {
                    continue
                }
                return .image(ClipboardImage(data: data, format: .tiff))
            case 2:
                guard let attachment = attachmentURL(
                    hash: text(at: 2),
                    extension: "plist"
                ), let data = try? Data(contentsOf: attachment),
                      let paths = try? PropertyListDecoder().decode([String].self, from: data),
                      !paths.isEmpty else {
                    continue
                }
                return .files(paths)
            default:
                continue
            }
        }
    }

    private func text(at index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func attachmentURL(hash: String?, extension expectedExtension: String) -> URL? {
        guard let hash,
              !hash.isEmpty,
              hash == URL(fileURLWithPath: hash).lastPathComponent,
              URL(fileURLWithPath: hash).pathExtension.lowercased() == expectedExtension else {
            return nil
        }
        let candidate = attachmentsURL
            .appendingPathComponent(hash, isDirectory: false)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == attachmentsURL else {
            return nil
        }
        return candidate
    }
}
