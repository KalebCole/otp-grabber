import Foundation

public struct ClientConfiguration: Equatable, Sendable {
    public let endpoint: URL
    public let token: String

    public init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OTP Grabber/client.json")
    }

    public static func load(from url: URL = defaultURL) throws -> ClientConfiguration {
        try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> ClientConfiguration {
        let raw = try JSONDecoder().decode(RawConfiguration.self, from: data)
        let serverURL = raw.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = raw.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, let endpoint = URL(string: serverURL), endpoint.host != nil else {
            throw ClientError.invalidConfiguration
        }
        let scheme = endpoint.scheme?.lowercased()
        let loopback = endpoint.host == "127.0.0.1" || endpoint.host == "localhost" || endpoint.host == "::1"
        let tailnet = endpoint.host?.lowercased().hasSuffix(".ts.net") == true
        let originOnly = (endpoint.path.isEmpty || endpoint.path == "/") && endpoint.query == nil && endpoint.fragment == nil && endpoint.user == nil && endpoint.password == nil
        guard originOnly, (loopback && (scheme == "http" || scheme == "https")) || (tailnet && scheme == "https") else {
            throw ClientError.invalidConfiguration
        }
        return ClientConfiguration(endpoint: endpoint, token: token)
    }

    private struct RawConfiguration: Decodable {
        let serverURL: String
        let token: String

        enum CodingKeys: String, CodingKey {
            case serverURL = "server_url"
            case token
        }
    }
}

public struct CodeRecord: Codable, Equatable, Sendable {
    public let id: String
    public let source: String
    public let code: String
    public let sender: String
    public let subject: String
    public let timestampMilliseconds: Int64

    public init(id: String, source: String, code: String, sender: String, subject: String, timestampMilliseconds: Int64) {
        self.id = id
        self.source = source
        self.code = code
        self.sender = sender
        self.subject = subject
        self.timestampMilliseconds = timestampMilliseconds
    }

    enum CodingKeys: String, CodingKey {
        case id, source, code, sender, subject
        case timestampMilliseconds = "timestamp_ms"
    }
}

public struct SourceError: Codable, Equatable, Sendable {
    public let source: String
    public let message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public struct LatestResponse: Equatable, Sendable {
    public let codes: [CodeRecord]
    public let errors: [SourceError]

    public init(codes: [CodeRecord], errors: [SourceError]) {
        self.codes = codes.sorted { $0.timestampMilliseconds > $1.timestampMilliseconds }
        self.errors = errors
    }

    public var latest: CodeRecord? { codes.first }

    public var presentationState: MenuState {
        if latest != nil {
            return errors.isEmpty ? .success(code: latest!.code, source: latest!.source, partialWarning: nil) : .partial
        }
        return errors.isEmpty ? .empty : .offline
    }

    public static func parse(_ data: Data) throws -> LatestResponse {
        let raw = try JSONDecoder().decode(RawLatestResponse.self, from: data)
        let codes = raw.codes ?? (raw.latest.map { [$0] } ?? [])
        return LatestResponse(codes: codes, errors: raw.errors ?? [])
    }

    private struct RawLatestResponse: Decodable {
        let latest: CodeRecord?
        let codes: [CodeRecord]?
        let errors: [SourceError]?
    }
}

public enum ClientError: Error, Equatable, Sendable {
    case invalidConfiguration
    case offline
    case invalidResponse
}

public protocol OTPClient: Sendable {
    func latest() async throws -> LatestResponse
    func archive(messageID: String) async throws
}

public final class APIClient: OTPClient, @unchecked Sendable {
    private let configuration: ClientConfiguration
    private let session: URLSession

    public init(configuration: ClientConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func latest() async throws -> LatestResponse {
        var request = APIClient.request(path: "v1/latest", configuration: configuration)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try LatestResponse.parse(data)
    }

    public func archive(messageID: String) async throws {
        let request = try Self.archiveRequest(messageID: messageID, configuration: configuration)
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    public static func archiveRequest(messageID: String, configuration: ClientConfiguration) throws -> URLRequest {
        guard !messageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.invalidResponse }
        var request = Self.request(path: "v1/archive", configuration: configuration)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": messageID], options: [.sortedKeys])
        return request
    }

    private static func request(path: String, configuration: ClientConfiguration) -> URLRequest {
        let endpoint = configuration.endpoint.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw ClientError.offline }
    }
}

@MainActor
public protocol ClipboardWriting: AnyObject {
    func copy(_ text: String) -> Bool
}

public enum MenuState: Equatable, Sendable {
    case setup
    case loading
    case success(code: String, source: String, partialWarning: String?)
    case empty
    case partial
    case offline
}

@MainActor
public final class MenuBarController {
    private let client: OTPClient
    private let clipboard: ClipboardWriting
    public private(set) var state: MenuState = .loading
    public var onStateChange: ((MenuState) -> Void)?

    public init(client: OTPClient, clipboard: ClipboardWriting) {
        self.client = client
        self.clipboard = clipboard
    }

    public func refresh() async {
        setState(.loading)
        do {
            let response = try await client.latest()
            guard let record = response.latest else {
                setState(response.errors.isEmpty ? .empty : .offline)
                return
            }
            guard clipboard.copy(record.code) else {
                setState(.offline)
                return
            }
            let warning = response.errors.first.map { "\($0.source) unavailable" }
            setState(.success(code: record.code, source: record.source, partialWarning: warning))
            if record.source.lowercased() == "gmail" {
                do {
                    try await client.archive(messageID: record.id)
                } catch {
                    setState(.success(code: record.code, source: record.source, partialWarning: "Gmail archive will retry next time"))
                }
            }
        } catch {
            setState(.offline)
        }
    }

    private func setState(_ state: MenuState) {
        self.state = state
        onStateChange?(state)
    }
}
