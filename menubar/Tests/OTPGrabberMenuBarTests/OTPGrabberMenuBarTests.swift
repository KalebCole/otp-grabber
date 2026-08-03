#if canImport(Testing)
import Foundation
import Testing
@testable import OTPGrabberMenuBarCore

@Suite("OTP Grabber menu-bar core")
struct OTPGrabberMenuBarTests {
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
        #expect(controller.state == .offline)
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
