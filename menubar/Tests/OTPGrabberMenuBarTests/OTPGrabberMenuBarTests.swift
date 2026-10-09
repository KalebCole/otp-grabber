#if canImport(Testing)
import Foundation
import SQLite3
import Testing
@testable import OTPGrabberMenuBarCore

@Suite("OTP Grabber menu-bar core")
struct OTPGrabberMenuBarTests {
    @Test("history persists and prunes after 24 hours")
    func findingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("otp-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("findings.sqlite")
        let now = Date(timeIntervalSince1970: 100_000)
        let recent = CodeFinding(source: .messages, messageID: "1", sender: "Bank", receivedAt: now.addingTimeInterval(-3_600), code: "552146")!
        let expired = CodeFinding(source: .gmail, messageID: "2", sender: "Store", receivedAt: now.addingTimeInterval(-86_401), code: "483921")!
        let first = FindingsStore(databaseURL: url)
        #expect(try first.save([.code(recent), .code(expired)], now: now).count == 1)
        let reopened = FindingsStore(databaseURL: url)
        #expect(try reopened.history(now: now) == [.code(recent)])
        #expect(try reopened.history(now: now.addingTimeInterval(86_400)).isEmpty)
    }

    @Test("Gmail MIME code and reset link extraction uses read-only message data")
    func gmailMessage() throws {
        let html = "<html><body><a href=\"https://static.example.test/logo\">Logo</a> Reset your password: <a href=\"https://accounts.example.test/reset?token=abc123&amp;nonce=xyz\">Reset</a></body></html>"
        let encodedHTML = Data(html.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let encodedCode = Data("Your verification code is A1B2C3".utf8).base64EncodedString()
        let json = """
        {"id":"gmail-1","threadId":"thread-1","internalDate":"10000000","payload":{
          "mimeType":"multipart/alternative","headers":[{"name":"From","value":"Bank"},{"name":"Subject","value":"Password reset and verification"}],
          "parts":[{"mimeType":"text/plain","body":{"data":"\(encodedCode)"}},{"mimeType":"text/html","body":{"data":"\(encodedHTML)"}}]
        }}
        """
        let message = try JSONDecoder().decode(GmailMessage.self, from: Data(json.utf8))
        let findings = GmailReader.findings(in: message, since: Date(timeIntervalSince1970: 0), accountEmail: "one@example.test")
        #expect(findings.count == 2)
        #expect(findings.contains { if case .code(let code) = $0 { return code.code == "A1B2C3" && code.gmailURL?.absoluteString.contains("thread-1") == true }; return false })
        #expect(findings.contains { if case .resetLink(let link) = $0 { return link.destinationDomain == "accounts.example.test" && link.url.query?.contains("&nonce=xyz") == true }; return false })
    }

    @Test("Messages reader only returns inbound codes from a read-only database")
    func messagesReader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("otp-messages-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        var database: OpaquePointer?
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        let sql = """
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY, handle_id INTEGER, text TEXT, attributedBody BLOB, date INTEGER, is_from_me INTEGER);
        INSERT INTO handle VALUES (1, 'Bank');
        INSERT INTO message VALUES (10, 1, 'Your security code is 552146', NULL, 1000000000000, 0);
        INSERT INTO message VALUES (11, 1, 'Your security code is 999888', NULL, 1000000000001, 1);
        """
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let findings = try MessagesReader(databaseURL: url).read(since: Date(timeIntervalSince1970: 978_307_200))
        #expect(findings.count == 1)
        let first = try #require(findings.first)
        if case .code(let code) = first {
            #expect(code.code == "552146")
            #expect(code.sender == "Bank")
        } else {
            Issue.record("Expected a Messages code")
        }
    }

    @Test("Messages typedstream text and missing database")
    func messagesAccess() {
        let payload = Data("prefixNSString\u{01}\u{95}\u{84}\u{01}+\u{06}123456trailing".utf8)
        #expect(MessagesReader.decodeAttributedBody(payload) == "123456")
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).db")
        do {
            _ = try MessagesReader(databaseURL: missing).read(since: .now)
            Issue.record("Expected missing database")
        } catch let error as MessagesReadError {
            #expect(error == .unavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    @Test("extracts contextual codes and rejects non-codes")
    func extraction() {
        #expect(FindingExtractor.code(subject: "Verification code", body: "Your code is 483921") == "483921")
        #expect(FindingExtractor.code(subject: "", body: "Use 741205 to sign in.") == "741205")
        #expect(FindingExtractor.code(subject: "Order update", body: "Order 483921 shipped today.") == nil)
        #expect(FindingExtractor.code(subject: "", body: "Your code is undefined") == nil)
        #expect(FindingExtractor.code(subject: "", body: "") == nil)
        #expect(FindingExtractor.code(subject: "Your verification code", body: "Call +1 555 123 4567") == nil)
        #expect(FindingExtractor.code(subject: "Payment confirmation", body: "One-time payment received. Confirmation number: U064L599.") == nil)
        #expect(FindingExtractor.code(subject: "Rewards confirmation", body: "This is a one time offer. Michaels Stores, 3939 West John Carpenter Freeway, Irving TX 75063.") == nil)
    }

    @Test("newest eligible code includes the exact five-minute cutoff")
    func freshness() {
        let now = Date(timeIntervalSince1970: 10_000)
        let cutoff = now.addingTimeInterval(-300)
        let older = CodeFinding(source: .messages, messageID: "old", sender: "A", receivedAt: cutoff.addingTimeInterval(-1), code: "654321")!
        let boundary = CodeFinding(source: .gmail, messageID: "edge", sender: "B", receivedAt: cutoff, code: "483921")!
        let recent = CodeFinding(source: .messages, messageID: "recent", sender: "C", receivedAt: now.addingTimeInterval(-10), code: "552146")!
        let future = CodeFinding(source: .messages, messageID: "future", sender: "C", receivedAt: now.addingTimeInterval(1), code: "741205")!
        #expect(FindingSelection.newestCode(in: [.code(older), .code(boundary), .code(future)], now: now)?.id == boundary.id)
        #expect(FindingSelection.newestCode(in: [.code(boundary), .code(recent)], now: now)?.id == recent.id)
        #expect(FindingSelection.deduplicated([.code(boundary), .code(boundary)]).count == 1)
        #expect(FindingSelection.newestCode(in: [.code(older)], now: now) == nil)
    }

    @Test("reset URLs require HTTPS and explicit reset context")
    func resetLinks() {
        #expect(FindingExtractor.resetLink(subject: "Reset your password", body: "https://accounts.example.test/reset?token=abc123")?.host == "accounts.example.test")
        #expect(FindingExtractor.resetLink(subject: "Reset your password", body: "Logo https://static.example.test/logo Reset your password: https://accounts.example.test/reset?token=abc123")?.host == "accounts.example.test")
        #expect(FindingExtractor.resetLink(subject: "Newsletter", body: "https://accounts.example.test/reset") == nil)
        #expect(ResetLinkFinding(messageID: "1", sender: "A", receivedAt: .now, url: URL(string: "http://example.test/reset")!) == nil)
    }
    @Test("copy boundary rejects missing and malformed values")
    func copyBoundary() {
        #expect(CopyCode.validated("") == nil)
        #expect(CopyCode.validated("undefined") == nil)
        #expect(CopyCode.validated("123") == nil)
        #expect(CopyCode.validated("123456789") == nil)
        #expect(CopyCode.validated("12 34") == nil)
        #expect(CopyCode.validated("  A1B2C3  ") == "A1B2C3")
    }

    @Test("malformed response code never reaches clipboard")
    @MainActor
    func malformedCode() async {
        let client = RecordingClient(response: LatestResponse(codes: [
            CodeRecord(id: "bad", source: "gmail", code: "undefined", sender: "", subject: "", timestampMilliseconds: 1)
        ], errors: []))
        let controller = MenuBarController(client: client, clipboard: RecordingClipboard(events: client.events))
        await controller.refresh()
        #expect(client.events.values == ["fetch"])
        #expect(controller.state == .copyError)
    }
    @Test("configuration accepts only private origin-only endpoints")
    func configurationValidation() throws {
        let valid = Data("""
        {"server_url":"https://agent.example.ts.net","token":"  secret-token  "}
        """.utf8)
        let config = try ClientConfiguration.parse(valid)

        #expect(config.endpoint.absoluteString == "https://agent.example.ts.net")
        #expect(config.token == "secret-token")
        #expect(!configurationIsValid("http://example.com"))
        #expect(!configurationIsValid("https://example.com"))
        #expect(!configurationIsValid("https://agent.ts.net/path"))
        #expect(configurationIsValid("http://127.0.0.1:8787"))
    }

    @Test("latest response chooses freshest code and preserves partial errors")
    func latestResponse() throws {
        let response = try LatestResponse.parse(Data("""
        {
          "codes": [
            {"id":"old","source":"messages","code":"111111","sender":"Bank","subject":"","timestamp_ms":100},
            {"id":"new","source":"gmail","code":"222222","sender":"Store","subject":"Sign in","timestamp_ms":200}
          ],
          "errors": [{"source":"messages","message":"unavailable"}]
        }
        """.utf8))

        #expect(response.latest?.id == "new")
        #expect(response.errors == [SourceError(source: "messages", message: "unavailable")])
        #expect(response.presentationState == .partial)
    }

    @Test("archive request uses POST, bearer token, and JSON id")
    func archiveRequest() throws {
        let endpoint = try #require(URL(string: "https://agent.example.ts.net"))
        let request = try APIClient.archiveRequest(
            messageID: "gmail-123",
            configuration: ClientConfiguration(endpoint: endpoint, token: "token")
        )

        #expect(request.url?.absoluteString == "https://agent.example.ts.net/v1/archive")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(String(data: try #require(request.httpBody), encoding: .utf8) == "{\"id\":\"gmail-123\"}")
    }

    @Test("controller copies before acknowledging Gmail")
    @MainActor
    func copyBeforeArchive() async {
        let client = RecordingClient(response: LatestResponse(
            codes: [CodeRecord(id: "gmail-1", source: "gmail", code: "123456", sender: "Bank", subject: "", timestampMilliseconds: 1)],
            errors: []
        ))
        let controller = MenuBarController(client: client, clipboard: RecordingClipboard(events: client.events))

        await controller.refresh()

        #expect(client.events.values == ["fetch", "copy:123456", "archive:gmail-1"])
        #expect(controller.state == .success(code: "123456", source: "gmail", partialWarning: nil))
    }

    @Test("clipboard failure never archives")
    @MainActor
    func clipboardFailure() async {
        let record = CodeRecord(id: "gmail-1", source: "gmail", code: "123456", sender: "Bank", subject: "", timestampMilliseconds: 1)
        let client = RecordingClient(response: LatestResponse(codes: [record], errors: []))
        let controller = MenuBarController(
            client: client,
            clipboard: RecordingClipboard(events: client.events, succeeds: false)
        )

        await controller.refresh()

        #expect(client.events.values == ["fetch", "copy:123456"])
        #expect(controller.state == .copyError)
    }

    @Test("archive failure preserves copied code and shows retry guidance")
    @MainActor
    func archiveFailure() async {
        let record = CodeRecord(id: "gmail-1", source: "gmail", code: "123456", sender: "Bank", subject: "", timestampMilliseconds: 1)
        let client = RecordingClient(
            response: LatestResponse(codes: [record], errors: []),
            archiveError: ClientError.offline
        )
        let controller = MenuBarController(client: client, clipboard: RecordingClipboard(events: client.events))

        await controller.refresh()

        #expect(client.events.values == ["fetch", "copy:123456", "archive:gmail-1"])
        #expect(controller.state == .success(
            code: "123456",
            source: "gmail",
            partialWarning: "Gmail archive will retry next time"
        ))
    }
}

private func configurationIsValid(_ serverURL: String) -> Bool {
    let encoded = serverURL.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let data = Data("{\"server_url\":\"\(encoded)\",\"token\":\"secret-token\"}".utf8)
    return (try? ClientConfiguration.parse(data)) != nil
}

private final class EventLog: @unchecked Sendable {
    var values: [String] = []
}

private final class RecordingClient: OTPClient, @unchecked Sendable {
    let response: LatestResponse
    let archiveError: Error?
    let events = EventLog()

    init(response: LatestResponse, archiveError: Error? = nil) {
        self.response = response
        self.archiveError = archiveError
    }

    func latest() async throws -> LatestResponse {
        events.values.append("fetch")
        return response
    }

    func archive(messageID: String) async throws {
        events.values.append("archive:\(messageID)")
        if let archiveError { throw archiveError }
    }
}

@MainActor
private final class RecordingClipboard: ClipboardWriting {
    let events: EventLog
    let succeeds: Bool

    init(events: EventLog, succeeds: Bool = true) {
        self.events = events
        self.succeeds = succeeds
    }

    func copy(_ text: String) -> Bool {
        events.values.append("copy:\(text)")
        return succeeds
    }
}
#endif
