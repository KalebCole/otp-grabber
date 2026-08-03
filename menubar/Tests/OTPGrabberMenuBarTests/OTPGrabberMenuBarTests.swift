#if canImport(XCTest)
import Foundation
import XCTest
@testable import OTPGrabberMenuBarCore

final class OTPGrabberMenuBarTests: XCTestCase {
    func testConfigurationParsesOnlyValidHTTPSOrLoopbackEndpoint() throws {
        let json = Data("""
        {"server_url":"https://agent.tailnet.example","token":"  secret-token  "}
        """.utf8)

        let config = try ClientConfiguration.parse(json)

        XCTAssertEqual(config.endpoint.absoluteString, "https://agent.tailnet.example")
        XCTAssertEqual(config.token, "secret-token")
        XCTAssertThrowsError(try ClientConfiguration.parse(Data("{\"server_url\":\"http://example.com\",\"token\":\"t\"}".utf8)))
    }

    func testLatestResponseChoosesFreshestCodeAndPreservesPartialErrors() throws {
        let response = try LatestResponse.parse(Data("""
        {
          "codes": [
            {"id":"old","source":"messages","code":"111111","sender":"Bank","subject":"","timestamp_ms":100},
            {"id":"new","source":"gmail","code":"222222","sender":"Store","subject":"Sign in","timestamp_ms":200}
          ],
          "errors": [{"source":"messages","message":"unavailable"}]
        }
        """.utf8))

        XCTAssertEqual(response.latest?.id, "new")
        XCTAssertEqual(response.errors, [SourceError(source: "messages", message: "unavailable")])
        XCTAssertEqual(response.presentationState, .partial)
    }

    func testLatestResponseSupportsAgentLatestShapeAndEmptyState() throws {
        let response = try LatestResponse.parse(Data("{\"latest\":null,\"errors\":[]}".utf8))
        XCTAssertNil(response.latest)
        XCTAssertEqual(response.presentationState, .empty)
    }

    func testArchiveRequestUsesPOSTBearerTokenAndJSONID() throws {
        let config = ClientConfiguration(endpoint: try XCTUnwrap(URL(string: "https://agent.tailnet.example/api")), token: "token")
        let request = try APIClient.archiveRequest(messageID: "gmail-123", configuration: config)

        XCTAssertEqual(request.url?.absoluteString, "https://agent.tailnet.example/api/v1/archive")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "{\"id\":\"gmail-123\"}")
    }

    @MainActor
    func testControllerCopiesBeforeAcknowledgingOnlyGmail() async {
        let client = RecordingClient(response: LatestResponse(
            codes: [CodeRecord(id: "gmail-1", source: "gmail", code: "123456", sender: "Bank", subject: "", timestampMilliseconds: 1)],
            errors: []
        ))
        let clipboard = RecordingClipboard(events: client.events)
        let controller = MenuBarController(client: client, clipboard: clipboard)

        await controller.refresh()

        XCTAssertEqual(client.events.values, ["fetch", "copy:123456", "archive:gmail-1"])
        XCTAssertEqual(controller.state, .success(code: "123456", source: "gmail", partialWarning: nil))
    }

    @MainActor
    func testControllerDoesNotArchiveWhenCopyFailsAndReportsOffline() async {
        let client = RecordingClient(response: LatestResponse(codes: [], errors: []), fetchError: ClientError.offline)
        let clipboard = RecordingClipboard(events: client.events, succeeds: false)
        let controller = MenuBarController(client: client, clipboard: clipboard)

        await controller.refresh()

        XCTAssertEqual(client.events.values, ["fetch"])
        XCTAssertEqual(controller.state, .offline)
    }
}

private final class EventLog: @unchecked Sendable {
    var values: [String] = []
}

private final class RecordingClient: OTPClient, @unchecked Sendable {
    let response: LatestResponse
    let fetchError: Error?
    let events = EventLog()

    init(response: LatestResponse, fetchError: Error? = nil) {
        self.response = response
        self.fetchError = fetchError
    }

    func latest() async throws -> LatestResponse {
        events.values.append("fetch")
        if let fetchError { throw fetchError }
        return response
    }

    func archive(messageID: String) async throws {
        events.values.append("archive:\(messageID)")
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
