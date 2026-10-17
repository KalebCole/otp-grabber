import Foundation

public enum FindingSource: String, Codable, Sendable, CaseIterable {
    case gmail
    case messages
}

public struct CodeFinding: Codable, Equatable, Sendable, Identifiable {
    public let source: FindingSource
    public let messageID: String
    public let sender: String
    public let receivedAt: Date
    public let code: String
    public let gmailURL: URL?

    public var id: String { "\(source.rawValue):\(messageID):code" }

    public init?(source: FindingSource, messageID: String, sender: String, receivedAt: Date, code: String, gmailURL: URL? = nil) {
        guard !messageID.isEmpty, let validated = CopyCode.validated(code) else { return nil }
        self.source = source
        self.messageID = messageID
        self.sender = sender
        self.receivedAt = receivedAt
        self.code = validated
        self.gmailURL = source == .gmail ? gmailURL : nil
    }
}

public struct ResetLinkFinding: Codable, Equatable, Sendable, Identifiable {
    public let messageID: String
    public let sender: String
    public let receivedAt: Date
    public let url: URL

    public var id: String { "gmail:\(messageID):reset" }
    public var destinationDomain: String { url.host ?? "" }

    public init?(messageID: String, sender: String, receivedAt: Date, url: URL) {
        guard !messageID.isEmpty, url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        self.messageID = messageID
        self.sender = sender
        self.receivedAt = receivedAt
        self.url = url
    }

    private enum CodingKeys: String, CodingKey { case messageID, sender, receivedAt, url }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let messageID = try values.decode(String.self, forKey: .messageID)
        let sender = try values.decode(String.self, forKey: .sender)
        let receivedAt = try values.decode(Date.self, forKey: .receivedAt)
        let url = try values.decode(URL.self, forKey: .url)
        guard let validated = Self(messageID: messageID, sender: sender, receivedAt: receivedAt, url: url) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: values, debugDescription: "Reset URL must be HTTPS")
        }
        self = validated
    }
}

public enum Finding: Codable, Equatable, Sendable, Identifiable {
    case code(CodeFinding)
    case resetLink(ResetLinkFinding)

    public var id: String {
        switch self {
        case .code(let value): value.id
        case .resetLink(let value): value.id
        }
    }

    public var receivedAt: Date {
        switch self {
        case .code(let value): value.receivedAt
        case .resetLink(let value): value.receivedAt
        }
    }

    public var source: FindingSource {
        switch self {
        case .code(let value): value.source
        case .resetLink: .gmail
        }
    }
}

public enum FindingSelection {
    public static func deduplicated(_ findings: [Finding]) -> [Finding] {
        var byID: [String: Finding] = [:]
        for finding in findings {
            if let previous = byID[finding.id], previous.receivedAt >= finding.receivedAt { continue }
            byID[finding.id] = finding
        }
        return byID.values.sorted { $0.receivedAt > $1.receivedAt }
    }

    public static func newestCode(in findings: [Finding], now: Date) -> CodeFinding? {
        let cutoff = now.addingTimeInterval(-300)
        return deduplicated(findings).compactMap { finding -> CodeFinding? in
            guard case .code(let code) = finding,
                  code.receivedAt >= cutoff, code.receivedAt <= now else { return nil }
            return code
        }.first
    }
}

public enum FindingExtractor {
    private static let context = ["verification code", "verify code", "your code", "code is", "security code", "one-time", "one time", "otp", "2fa", "two-factor", "authentication code", "login code", "sign-in code", "sign in", "passcode", "pin code", "access code"]
    private static let resetContext = ["reset your password", "password reset", "reset link", "change your password"]
    private static let codePattern = try! NSRegularExpression(pattern: #"\b(?:[A-Z0-9]{4,8}|\d{3}[- ]\d{3})\b"#, options: [.caseInsensitive])
    private static let urlPattern = try! NSRegularExpression(pattern: #"https://[^\s<>\"']+"#, options: [.caseInsensitive])
    private static let noisePattern = try! NSRegularExpression(pattern: #"https?://\S+|www\.\S+|\+?\d{1,3}[-. ]?\(?\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}|\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b|\b(?:19|20)\d{2}\b|\b(?:order|reference|tracking|invoice|account|ticket|confirmation)\s*(?:number|id)?\s*[:#]?\s*[A-Z0-9-]{4,}\b|\b\d{2,6}\s+(?:[A-Za-z]+\s+){0,3}(?:street|st|avenue|ave|road|rd|drive|dr|freeway|fwy)\b|\b[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#, options: [.caseInsensitive])

    public static func code(subject: String, body: String) -> String? {
        let text = subject + " " + body
        let lowered = text.lowercased()
        guard context.contains(where: lowered.contains) else { return nil }
        let cleaned = noisePattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        let candidates = codePattern.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
        var scored: [(String, Int)] = []
        for match in candidates {
            guard let range = Range(match.range, in: cleaned) else { continue }
            let raw = String(cleaned[range])
            let candidate = raw.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "").uppercased()
            guard let code = CopyCode.validated(candidate), !code.allSatisfy({ $0.isLetter }),
                  Set(code).count > 1, !isSequence(code) else { continue }
            let prefix = cleaned[..<range.lowerBound]
            let distance = prefix.count
            let window = String(cleaned.dropFirst(max(0, distance - 80)).prefix(140)).lowercased()
            let strong = context.contains { window.contains($0) }
            guard strong else { continue }
            let subjectBonus = subject.localizedCaseInsensitiveContains(raw) ? 2 : 0
            scored.append((code, 10 + subjectBonus - min(9, abs(distance - (text.count / 2)) / 20)))
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }),
              scored.filter({ $0.1 == best.1 && $0.0 != best.0 }).isEmpty else { return nil }
        return best.0
    }

    public static func resetLink(subject: String, body: String) -> URL? {
        let text = subject + " " + body
        guard resetContext.contains(where: text.lowercased().contains) else { return nil }
        var candidates: [(URL, Bool)] = []
        for match in urlPattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let range = Range(match.range, in: body) else { continue }
            let raw = String(body[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)]"))
            guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil,
                  url.user == nil, url.password == nil else { continue }
            let prefix = body[..<range.lowerBound]
            let window = String(prefix.suffix(60))
            candidates.append((url, resetContext.contains(where: window.lowercased().contains)))
        }
        let contextual = candidates.filter { $0.1 }
        if contextual.count == 1 { return contextual[0].0 }
        if contextual.isEmpty && candidates.count == 1 { return candidates[0].0 }
        return nil
    }

    private static func isSequence(_ value: String) -> Bool {
        guard value.allSatisfy({ $0.isNumber }) else { return false }
        let numbers = value.compactMap { $0.wholeNumberValue }
        return zip(numbers, numbers.dropFirst()).allSatisfy { pair in pair.1 == pair.0 + 1 } ||
            zip(numbers, numbers.dropFirst()).allSatisfy { pair in pair.1 == pair.0 - 1 }
    }
}
