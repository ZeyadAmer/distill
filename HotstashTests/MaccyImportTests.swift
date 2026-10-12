import Testing
import Foundation
import SQLite3
import SwiftData
@testable import Hotstash

@MainActor
struct MaccyImportTests {

    private let container: ModelContainer
    private let store: ClipboardStore

    init() throws {
        container = try ModelContainer.hotstashInMemory()
        store = ClipboardStore(container: container)
    }

    /// Builds a folder holding a Maccy-shaped Storage.sqlite:
    /// 1 pinned text clip (with RTF), 2 image clips (PNG, TIFF), 1 file copy (skipped),
    /// 1 duplicate of the text clip (collapsed).
    private func makeMaccyFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Maccy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var db: OpaquePointer?
        #expect(sqlite3_open(dir.appendingPathComponent("Storage.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }

        let sql = """
            CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZLASTCOPIEDAT TIMESTAMP,
                ZNUMBEROFCOPIES INTEGER, ZPIN VARCHAR, ZTITLE VARCHAR);
            CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER,
                ZTYPE VARCHAR, ZVALUE BLOB);
            INSERT INTO ZHISTORYITEM VALUES (1, 700000000, 3, 'b', 'hello maccy');
            INSERT INTO ZHISTORYITEM VALUES (2, 700000100, 1, NULL, 'Image');
            INSERT INTO ZHISTORYITEM VALUES (3, 700000200, 1, NULL, 'file');
            INSERT INTO ZHISTORYITEM VALUES (4, 700000300, 1, NULL, 'hello maccy');
            INSERT INTO ZHISTORYITEM VALUES (5, 700000400, 1, NULL, 'Image');
            INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', CAST('hello maccy' AS BLOB));
            INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 1, 'public.rtf', CAST('{\\rtf1 hello}' AS BLOB));
            INSERT INTO ZHISTORYITEMCONTENT VALUES (3, 2, 'public.png', X'89504E47');
            INSERT INTO ZHISTORYITEMCONTENT VALUES (4, 3, 'public.file-url', CAST('file:///tmp/x' AS BLOB));
            INSERT INTO ZHISTORYITEMCONTENT VALUES (5, 3, 'public.utf8-plain-text', CAST('/tmp/x' AS BLOB));
            INSERT INTO ZHISTORYITEMCONTENT VALUES (6, 4, 'public.utf8-plain-text', CAST('hello maccy' AS BLOB));
            INSERT INTO ZHISTORYITEMCONTENT VALUES (7, 5, 'public.tiff', X'4D4D002A');
            """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        return dir
    }

    @Test("Imports text and images, keeps pin + RTF, skips files and duplicates")
    func importsFolder() throws {
        let dir = try makeMaccyFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let count = try MaccyImporter.importClipboard(from: dir, into: store)
        #expect(count == 3)

        let text = store.items.first { $0.content == "hello maccy" }
        #expect(text?.isPinned == true)
        #expect(text?.useCount == 3)
        #expect(text?.rtfData != nil)
        #expect(text?.timestamp == Date(timeIntervalSinceReferenceDate: 700_000_000))

        #expect(store.items.contains { $0.contentType == .image && $0.imageData == Data([0x89, 0x50, 0x4E, 0x47]) })
        #expect(store.items.filter { $0.contentType == .image }.count == 2)
        #expect(!store.items.contains { $0.content == "/tmp/x" })
    }

    @Test("Accepts the Storage.sqlite file directly; re-import adds nothing")
    func importsFileAndIsIdempotent() throws {
        let dir = try makeMaccyFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try MaccyImporter.importClipboard(from: dir.appendingPathComponent("Storage.sqlite"), into: store)
        #expect(try MaccyImporter.importClipboard(from: dir, into: store) == 0)
    }

    @Test("A folder without Storage.sqlite throws")
    func missingDatabaseThrows() {
        #expect(throws: MaccyImportError.self) {
            try MaccyImporter.importClipboard(from: FileManager.default.temporaryDirectory, into: store)
        }
    }
}
