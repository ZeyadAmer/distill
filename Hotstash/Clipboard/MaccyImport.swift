import Foundation
import SQLite3

// MARK: - MaccyImportError

enum MaccyImportError: LocalizedError {
    case databaseNotFound
    case unreadableDatabase

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Couldn't find Maccy's Storage.sqlite. Choose the Maccy folder or the Storage.sqlite file inside it."
        case .unreadableDatabase:
            return "Couldn't read Maccy's history. Quit Maccy and try again."
        }
    }
}

// MARK: - MaccyImporter

/// Imports clipboard history from Maccy's unencrypted Core Data/SwiftData store.
/// The user picks the Maccy folder (or `Storage.sqlite`) — nothing is read
/// silently. The store is copied to a temp dir first so SQLite never needs
/// write access next to Maccy's live files.
///
/// Schema: `ZHISTORYITEM` (one row per clip: `ZLASTCOPIEDAT`, `ZNUMBEROFCOPIES`,
/// `ZPIN`) and `ZHISTORYITEMCONTENT` (one row per pasteboard type: `ZITEM` →
/// item `Z_PK`, `ZTYPE` = UTI, `ZVALUE` = bytes). File copies are skipped —
/// their sandbox bookmarks can't be recreated from a path.
enum MaccyImporter {

    /// Where Maccy keeps its store; used to pre-navigate the open panel.
    /// Uses the real home dir — `homeDirectoryForCurrentUser` is the sandbox container.
    static let defaultFolder = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir))
        .appendingPathComponent("Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy")

    @MainActor
    @discardableResult
    static func importClipboard(from url: URL, into store: ClipboardStore = .shared) throws -> Int {
        let items = try clipboardItems(from: url)
        return store.importItems(items)
    }

    // MARK: Decode

    @MainActor
    static func clipboardItems(from url: URL) throws -> [ClipboardItem] {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let source = isDirectory ? url.appendingPathComponent("Storage.sqlite") : url
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw MaccyImportError.databaseNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccy-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let copy = tempDir.appendingPathComponent("Storage.sqlite")
        // The -wal/-shm siblings hold recent, uncheckpointed clips. They're only
        // reachable when the user picked the folder; missing ones are fine.
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            let to = URL(fileURLWithPath: copy.path + suffix)
            if suffix.isEmpty {
                do { try FileManager.default.copyItem(at: from, to: to) }
                catch { throw MaccyImportError.unreadableDatabase }
            } else {
                try? FileManager.default.copyItem(at: from, to: to)
            }
        }
        return try readItems(databaseAt: copy)
    }

    private struct Row {
        var date = Date.now
        var count = 0
        var isPinned = false
        var contents: [String: Data] = [:]
    }

    private static func readItems(databaseAt url: URL) throws -> [ClipboardItem] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw MaccyImportError.unreadableDatabase
        }
        defer { sqlite3_close(db) }

        var rows: [Int64: Row] = [:]
        try query(db, """
            SELECT Z_PK, ZLASTCOPIEDAT, ZNUMBEROFCOPIES, ZPIN FROM ZHISTORYITEM
            """) { stmt in
            var row = Row()
            // Core Data stores dates as seconds since 2001-01-01.
            if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                row.date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 1))
            }
            row.count = Int(sqlite3_column_int64(stmt, 2))
            row.isPinned = sqlite3_column_type(stmt, 3) != SQLITE_NULL
            rows[sqlite3_column_int64(stmt, 0)] = row
        }
        try query(db, "SELECT ZITEM, ZTYPE, ZVALUE FROM ZHISTORYITEMCONTENT") { stmt in
            let pk = sqlite3_column_int64(stmt, 0)
            guard rows[pk] != nil,
                  let typePtr = sqlite3_column_text(stmt, 1),
                  let blob = sqlite3_column_blob(stmt, 2) else { return }
            let bytes = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 2)))
            rows[pk]?.contents[String(cString: typePtr)] = bytes
        }

        return rows.values
            .sorted { $0.date < $1.date }
            .compactMap(makeItem)
    }

    private static func query(_ db: OpaquePointer?, _ sql: String, row: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            throw MaccyImportError.unreadableDatabase
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    private static let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic"]

    /// Maps one Maccy clip to a `ClipboardItem`, or nil to skip it.
    private static func makeItem(_ row: Row) -> ClipboardItem? {
        let c = row.contents
        if c["public.file-url"] != nil { return nil }

        if let image = imageTypes.lazy.compactMap({ c[$0] }).first {
            return ClipboardItem(
                content: "[Image]", contentType: .image, timestamp: row.date,
                isPinned: row.isPinned, useCount: row.count, imageData: image
            )
        }

        let text = c["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) }
            ?? c["public.utf16-plain-text"].flatMap { String(data: $0, encoding: .utf16) }
            ?? ""
        guard !text.isEmpty else { return nil }
        return ClipboardItem(
            content: text, contentType: ContentDetector.detect(text), timestamp: row.date,
            isPinned: row.isPinned, useCount: row.count,
            rtfData: c["public.rtf"], htmlData: c["public.html"]
        )
    }
}
