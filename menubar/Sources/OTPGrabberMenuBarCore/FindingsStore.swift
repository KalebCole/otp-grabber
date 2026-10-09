import Foundation
import SQLite3

public enum FindingsStoreError: Error, Sendable {
    case database
    case serialization
}

public struct FindingsStore: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OTP Grabber/findings.sqlite")) {
        self.databaseURL = databaseURL
    }

    public func save(_ findings: [Finding], now: Date = .now) throws -> [Finding] {
        try withDatabase { database in
            let cutoff = now.addingTimeInterval(-86_400)
            try prune(database, before: cutoff)
            let sql = "INSERT OR REPLACE INTO findings (id, received_at, payload) VALUES (?, ?, ?)"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw FindingsStoreError.database }
            defer { sqlite3_finalize(statement) }
            for finding in FindingSelection.deduplicated(findings) where finding.receivedAt >= cutoff && finding.receivedAt <= now {
                let data = try JSONEncoder().encode(finding)
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(finding.id, at: 1, to: statement)
                sqlite3_bind_double(statement, 2, finding.receivedAt.timeIntervalSince1970)
                let result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(data.count), sqliteTransient)
                }
                guard result == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw FindingsStoreError.database }
            }
            return try load(database, since: cutoff)
        }
    }

    public func history(now: Date = .now) throws -> [Finding] {
        try withDatabase { database in
            let cutoff = now.addingTimeInterval(-86_400)
            try prune(database, before: cutoff)
            return try load(database, since: cutoff)
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            throw FindingsStoreError.database
        }
        defer { sqlite3_close(database) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        guard sqlite3_exec(database, "CREATE TABLE IF NOT EXISTS findings (id TEXT PRIMARY KEY, received_at REAL NOT NULL, payload BLOB NOT NULL)", nil, nil, nil) == SQLITE_OK else {
            throw FindingsStoreError.database
        }
        return try body(database)
    }

    private func prune(_ database: OpaquePointer, before cutoff: Date) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM findings WHERE received_at < ?", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw FindingsStoreError.database }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FindingsStoreError.database }
    }

    private func load(_ database: OpaquePointer, since cutoff: Date) throws -> [Finding] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM findings WHERE received_at >= ? ORDER BY received_at DESC", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw FindingsStoreError.database }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
        var findings: [Finding] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) else { throw FindingsStoreError.database }
            let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0)))
            guard let finding = try? JSONDecoder().decode(Finding.self, from: data) else { throw FindingsStoreError.serialization }
            findings.append(finding)
        }
        return findings
    }

    private func bind(_ string: String, at index: Int32, to statement: OpaquePointer) throws {
        let result = string.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
        guard result == SQLITE_OK else { throw FindingsStoreError.database }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
