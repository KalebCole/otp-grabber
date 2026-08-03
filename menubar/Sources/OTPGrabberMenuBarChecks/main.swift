import Foundation
import OTPGrabberMenuBarCore

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

private func configIsValid(_ serverURL: String) -> Bool {
    let data = Data("{\"server_url\":\"\(serverURL)\",\"token\":\"secret\"}".utf8)
    return (try? ClientConfiguration.parse(data)) != nil
}

private final class Events: @unchecked Sendable { var values: [String] = [] }

private final class Client: OTPClient, @unchecked Sendable {
    let response: LatestResponse
    let archiveError: Error?
    let events = Events()

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
private final class Clipboard: ClipboardWriting {
    let events: Events
    let succeeds: Bool

    init(events: Events, succeeds: Bool = true) {
        self.events = events
        self.succeeds = succeeds
    }

    func copy(_ text: String) -> Bool {
        events.values.append("copy:\(text)")
        return succeeds
    }
}

@main
private struct OTPGrabberMenuBarChecks {
    @MainActor
    static func main() async throws {
        try check(configIsValid("https://agent.example.ts.net:8877"), "tailnet HTTPS should be valid")
        try check(configIsValid("http://127.0.0.1:8877"), "loopback HTTP should be valid")
        try check(!configIsValid("https://example.com"), "public HTTPS must be rejected")
        try check(!configIsValid("https://agent.ts.net/v1/latest"), "endpoint paths must be rejected")

        let parsed = try LatestResponse.parse(Data("""
        {"codes":[
          {"id":"old","source":"messages","code":"111111","sender":"A","subject":"","timestamp_ms":1},
          {"id":"new","source":"gmail","code":"222222","sender":"B","subject":"","timestamp_ms":2}
        ],"errors":[]}
        """.utf8))
        try check(parsed.latest?.id == "new", "freshest code should win")

        let endpoint = try checkURL("https://agent.example.ts.net:8877")
        let request = try APIClient.archiveRequest(
            messageID: "gmail-1",
            configuration: ClientConfiguration(endpoint: endpoint, token: "token")
        )
        try check(request.httpMethod == "POST", "archive must POST")
        try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer token", "archive must authenticate")

        let gmail = CodeRecord(id: "gmail-1", source: "gmail", code: "123456", sender: "Bank", subject: "", timestampMilliseconds: 1)
        let client = Client(response: LatestResponse(codes: [gmail], errors: []))
        let controller = MenuBarController(client: client, clipboard: Clipboard(events: client.events))
        await controller.refresh()
        try check(client.events.values == ["fetch", "copy:123456", "archive:gmail-1"], "copy must precede archive")

        let copyFailureClient = Client(response: LatestResponse(codes: [gmail], errors: []))
        let copyFailure = MenuBarController(client: copyFailureClient, clipboard: Clipboard(events: copyFailureClient.events, succeeds: false))
        await copyFailure.refresh()
        try check(copyFailureClient.events.values == ["fetch", "copy:123456"], "failed copy must not archive")

        let archiveFailureClient = Client(response: LatestResponse(codes: [gmail], errors: []), archiveError: ClientError.offline)
        let archiveFailure = MenuBarController(client: archiveFailureClient, clipboard: Clipboard(events: archiveFailureClient.events))
        await archiveFailure.refresh()
        try check(archiveFailure.state == .success(code: "123456", source: "gmail", partialWarning: "Gmail archive will retry next time"), "archive failure must preserve code and guidance")

        print("OTPGrabberMenuBarChecks: 8 checks passed")
    }

    private static func checkURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else { throw CheckFailure.failed("invalid test URL") }
        return url
    }
}
