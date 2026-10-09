import Foundation
import SQLite3
import Darwin

public enum MessagesReadError: Error, Equatable, Sendable {
    case accessDenied
    case unavailable
    case schemaChanged
    case database(String)

    public var recoveryMessage: String {
        switch self {
        case .accessDenied:
            "Give OTP Grabber Full Disk Access in System Settings, then reopen the app."
        case .unavailable:
            "Messages has no local database on this Mac yet. Open Messages and try again."
        case .schemaChanged:
            "Messages changed its local database format. Update OTP Grabber before trying again."
        case .database:
            "Messages could not be read. Check Full Disk Access and try again."
        }
    }
}

public struct MessagesReader: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")) {
        self.databaseURL = databaseURL
    }

    public func read(since: Date) throws -> [Finding] {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database else {
            let systemError = sqlite3_system_errno(database)
            if database != nil { sqlite3_close(database) }
            if systemError == EACCES || systemError == EPERM { throw MessagesReadError.accessDenied }
            if systemError == ENOENT { throw MessagesReadError.unavailable }
            throw MessagesReadError.database("SQLite open failed (\(result), errno \(systemError))")
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT m.ROWID, COALESCE(h.id, '?'), m.text, m.attributedBody, m.date
        FROM message AS m
        LEFT JOIN handle AS h ON m.handle_id = h.ROWID
        WHERE m.is_from_me = 0 AND m.date >= ?
        ORDER BY m.date DESC LIMIT 500
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MessagesReadError.schemaChanged
        }
        defer { sqlite3_finalize(statement) }

        let appleEpoch: Double = 978_307_200
        let cutoff = max(0, Int64((since.timeIntervalSince1970 - appleEpoch) * 1_000_000_000))
        sqlite3_bind_int64(statement, 1, cutoff)
        var findings: [Finding] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw MessagesReadError.database(String(cString: sqlite3_errmsg(database)))
            }
            let rowID = String(sqlite3_column_int64(statement, 0))
            let rawSender = Self.columnText(statement, 1)
            let sender = rawSender.lowercased().hasSuffix("(smsft)") ? String(rawSender.dropLast(7)) : rawSender
            var body = Self.columnText(statement, 2)
            if body.isEmpty, let pointer = sqlite3_column_blob(statement, 3) {
                let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 3)))
                body = Self.decodeAttributedBody(data)
            }
            guard !body.isEmpty, let code = FindingExtractor.code(subject: "", body: body) else { continue }
            let receivedAt = Date(timeIntervalSince1970: appleEpoch + Double(sqlite3_column_int64(statement, 4)) / 1_000_000_000)
            if let finding = CodeFinding(source: .messages, messageID: rowID, sender: sender, receivedAt: receivedAt, code: code) {
                findings.append(.code(finding))
            }
        }
        return findings
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        let buffer = UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(statement, index)))
        return String(decoding: buffer, as: UTF8.self)
    }

    public static func decodeAttributedBody(_ data: Data) -> String {
        let bytes = [UInt8](data)
        guard let marker = data.range(of: Data("NSString".utf8)) else { return "" }
        let start = data.distance(from: data.startIndex, to: marker.upperBound)
        guard start < bytes.count else { return "" }
        let markerEnd = min(start + 16, bytes.count)
        guard let plus = (start..<markerEnd).first(where: { bytes[$0] == 0x2B }), plus + 1 < bytes.count else { return "" }
        let length: Int
        let payloadStart: Int
        if bytes[plus + 1] == 0x81 {
            guard plus + 3 < bytes.count else { return "" }
            length = Int(bytes[plus + 2]) | (Int(bytes[plus + 3]) << 8)
            payloadStart = plus + 4
        } else {
            length = Int(bytes[plus + 1])
            payloadStart = plus + 2
        }
        guard length > 0, payloadStart + length <= bytes.count else { return "" }
        return String(decoding: bytes[payloadStart..<(payloadStart + length)], as: UTF8.self)
    }
}
