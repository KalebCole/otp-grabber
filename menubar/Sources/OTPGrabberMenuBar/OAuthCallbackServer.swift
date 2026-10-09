import Darwin
import Foundation

enum OAuthCallbackError: Error {
    case listenerFailed
    case invalidCallback
    case timedOut
}

final class OAuthCallbackServer: @unchecked Sendable {
    private let descriptor: Int32
    let redirectURI: String

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw OAuthCallbackError.listenerFailed }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: in_addr_t(0x7f000001).bigEndian)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else {
            close(fd)
            throw OAuthCallbackError.listenerFailed
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else {
            close(fd)
            throw OAuthCallbackError.listenerFailed
        }
        descriptor = fd
        redirectURI = "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))/oauth2callback"
    }

    deinit { close(descriptor) }

    func waitForCode(expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let deadline = Date().addingTimeInterval(180)
                while Date() < deadline {
                    var event = pollfd(fd: self.descriptor, events: Int16(POLLIN), revents: 0)
                    let remaining = max(1, Int32(deadline.timeIntervalSinceNow * 1000))
                    guard poll(&event, 1, remaining) > 0 else { break }
                    let client = accept(self.descriptor, nil, nil)
                    guard client >= 0 else { continue }
                    var timeout = timeval(tv_sec: 2, tv_usec: 0)
                    _ = withUnsafePointer(to: &timeout) {
                        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
                    }
                    var bytes = [UInt8](repeating: 0, count: 8192)
                    let count = recv(client, &bytes, bytes.count, 0)
                    guard count > 0, let line = String(bytes: bytes.prefix(count), encoding: .utf8)?.components(separatedBy: "\r\n").first,
                          line.hasPrefix("GET "), let path = line.split(separator: " ").dropFirst().first,
                          let components = URLComponents(string: "http://127.0.0.1\(path)"),
                          components.path == "/oauth2callback",
                          components.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else {
                        self.reply(client, success: false)
                        close(client)
                        continue
                    }
                    guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                          !code.isEmpty else {
                        self.reply(client, success: false)
                        close(client)
                        continuation.resume(throwing: OAuthCallbackError.invalidCallback)
                        return
                    }
                    self.reply(client, success: true)
                    close(client)
                    continuation.resume(returning: code)
                    return
                }
                continuation.resume(throwing: OAuthCallbackError.timedOut)
            }
        }
    }

    private func reply(_ client: Int32, success: Bool) {
        let text = success ? "Return to OTP Grabber to finish sign-in." : "Sign-in failed. Return to OTP Grabber and try again."
        let body = "<html><body><p>\(text)</p></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = response.withCString { send(client, $0, response.utf8.count, 0) }
    }
}
