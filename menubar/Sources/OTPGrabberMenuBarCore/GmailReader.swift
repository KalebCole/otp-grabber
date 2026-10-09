import Foundation

public enum GmailReadError: Error, Equatable, Sendable {
    case signInRequired
    case invalidResponse
    case requestFailed(Int)
}

public struct GmailReader: Sendable {
    public typealias TokenProvider = @Sendable () async throws -> String
    private let token: TokenProvider
    private let session: URLSession

    public init(token: @escaping TokenProvider, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func read(since: Date) async throws -> [Finding] {
        let accessToken = try await token()
        let profile: GmailProfile = try await get(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!, token: accessToken)
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "q", value: "after:\(Int(since.timeIntervalSince1970)) in:anywhere (verification OR passcode OR OTP OR \"one-time\" OR \"sign-in code\" OR \"security code\" OR \"password reset\" OR \"reset your password\")"),
        ]
        let listing: MessageList = try await get(components.url!, token: accessToken)
        var findings: [Finding] = []
        for summary in listing.messages ?? [] {
            guard !summary.id.isEmpty else { continue }
            let encoded = summary.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? summary.id
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encoded)?format=full")!
            let message: GmailMessage = try await get(url, token: accessToken)
            findings.append(contentsOf: Self.findings(in: message, since: since, accountEmail: profile.emailAddress))
        }
        return FindingSelection.deduplicated(findings)
    }

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GmailReadError.invalidResponse }
        if response.statusCode == 401 { throw GmailReadError.signInRequired }
        guard (200...299).contains(response.statusCode) else { throw GmailReadError.requestFailed(response.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GmailReadError.invalidResponse }
    }

    static func findings(in message: GmailMessage, since: Date, accountEmail: String) -> [Finding] {
        guard let milliseconds = Double(message.internalDate ?? ""),
              let payload = message.payload, !message.id.isEmpty else { return [] }
        let receivedAt = Date(timeIntervalSince1970: milliseconds / 1000)
        guard receivedAt >= since else { return [] }
        let headers = Dictionary(payload.headers?.map { ($0.name.lowercased(), $0.value) } ?? [], uniquingKeysWith: { first, _ in first })
        let sender = headers["from"] ?? "Unknown sender"
        let subject = headers["subject"] ?? ""
        let body = payload.readableText
        var findings: [Finding] = []
        var gmailLink: URL?
        if let threadID = message.threadId, !threadID.isEmpty {
            var link = URLComponents(string: "https://mail.google.com/mail/")!
            link.queryItems = [URLQueryItem(name: "authuser", value: accountEmail)]
            link.fragment = "all/\(threadID)"
            gmailLink = link.url
        }
        if let code = FindingExtractor.code(subject: subject, body: body),
           let finding = CodeFinding(source: .gmail, messageID: message.id, sender: sender, receivedAt: receivedAt, code: code, gmailURL: gmailLink) {
            findings.append(.code(finding))
        }
        if let link = FindingExtractor.resetLink(subject: subject, body: body),
           let finding = ResetLinkFinding(messageID: message.id, sender: sender, receivedAt: receivedAt, url: link) {
            findings.append(.resetLink(finding))
        }
        return findings
    }
}

struct MessageList: Decodable {
    let messages: [MessageSummary]?
}

struct GmailProfile: Decodable {
    let emailAddress: String
}

struct MessageSummary: Decodable {
    let id: String
}

struct GmailMessage: Decodable {
    let id: String
    let threadId: String?
    let internalDate: String?
    let payload: GmailPart?
}

struct GmailHeader: Decodable {
    let name: String
    let value: String
}

struct GmailPart: Decodable {
    let mimeType: String?
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailPart]?

    var readableText: String {
        let children = (parts ?? []).map(\.readableText).joined(separator: " ")
        guard let data = body?.data, (mimeType ?? "").hasPrefix("text/"),
              let decoded = Self.decodeBase64URL(data) else { return children }
        let text = String(decoding: decoded, as: UTF8.self)
        if mimeType?.lowercased() == "text/html" {
            return Self.plainText(fromHTML: text) + " " + Self.links(fromHTML: text) + " " + children
        }
        return text + " " + children
    }

    private static func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func plainText(fromHTML html: String) -> String {
        let withoutScripts = html.replacingOccurrences(of: #"<(script|style)\b[^>]*>[\s\S]*?</\1>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        let stripped = withoutScripts.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return stripped.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func links(fromHTML html: String) -> String {
        guard let pattern = try? NSRegularExpression(pattern: #"<a\b[^>]*href\s*=\s*["'](https://[^"']+)["'][^>]*>([\s\S]*?)</a>"#, options: [.caseInsensitive]) else { return "" }
        return pattern.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html) else { return nil }
            let label = String(html[labelRange]).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            guard label.localizedCaseInsensitiveContains("reset") || label.localizedCaseInsensitiveContains("password") else { return nil }
            let url = String(html[urlRange]).replacingOccurrences(of: "&amp;", with: "&")
            return label + " " + url
        }.joined(separator: " ")
    }
}

struct GmailBody: Decodable {
    let data: String?
}
