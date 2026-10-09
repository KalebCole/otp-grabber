import CryptoKit
import Foundation
import Security

public enum GmailAuthError: Error, Equatable, Sendable {
    case missingClientID
    case signInRequired
    case authorizationRejected
    case missingRefreshToken
    case invalidResponse
    case tokenRejected(Int, String)
    case keychain(OSStatus)
}

public struct AuthorizationRequest: Sendable {
    public let url: URL
    public let verifier: String
    public let state: String
    public let redirectURI: String
}

public enum GmailOAuth {
    public static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    public static func makeRequest(clientID: String, redirectURI: String) throws -> AuthorizationRequest {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GmailAuthError.missingClientID }
        let verifier = randomURLSafeBytes(count: 48)
        let state = randomURLSafeBytes(count: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString
        var parts = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        parts.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return AuthorizationRequest(url: parts.url!, verifier: verifier, state: state, redirectURI: redirectURI)
    }

    private static func randomURLSafeBytes(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess)
        return Data(bytes).base64URLString
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public struct GmailRefreshTokenStore: Sendable {
    private let service = "com.otpgrabber.menubar.gmail"
    private let account = "primary"

    public init() {}

    public func load() throws -> String? {
        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw GmailAuthError.keychain(status) }
        return token
    }

    public func save(_ token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard update == errSecSuccess else { throw GmailAuthError.keychain(update) }
        } else if status != errSecSuccess {
            throw GmailAuthError.keychain(status)
        }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GmailAuthError.keychain(status) }
    }
}

public actor GmailTokenProvider {
    private let clientID: String
    private let store: GmailRefreshTokenStore
    private let session: URLSession
    private var cached: (value: String, expiresAt: Date)?

    public init(clientID: String, store: GmailRefreshTokenStore = .init(), session: URLSession = .shared) {
        self.clientID = clientID
        self.store = store
        self.session = session
    }

    public func accessToken() async throws -> String {
        if let cached, cached.expiresAt > Date().addingTimeInterval(60) { return cached.value }
        guard let refresh = try store.load() else { throw GmailAuthError.signInRequired }
        return try await exchange(["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"], requiresRefresh: false)
    }

    public func connect(code: String, request: AuthorizationRequest) async throws {
        _ = try await exchange([
            "client_id": clientID,
            "code": code,
            "code_verifier": request.verifier,
            "redirect_uri": request.redirectURI,
            "grant_type": "authorization_code",
        ], requiresRefresh: true)
    }

    private func exchange(_ fields: [String: String], requiresRefresh: Bool) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GmailAuthError.invalidResponse }
        if response.statusCode == 400 || response.statusCode == 401 {
            let failure = try? JSONDecoder().decode(TokenFailure.self, from: data)
            if failure?.error == "invalid_grant" {
                if requiresRefresh { throw GmailAuthError.authorizationRejected }
                throw GmailAuthError.signInRequired
            }
            throw GmailAuthError.tokenRejected(response.statusCode, failure?.error ?? "unknown")
        }
        guard (200...299).contains(response.statusCode),
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !token.accessToken.isEmpty else { throw GmailAuthError.invalidResponse }
        if requiresRefresh && (token.refreshToken?.isEmpty != false) { throw GmailAuthError.missingRefreshToken }
        if let refresh = token.refreshToken { try store.save(refresh) }
        cached = (token.accessToken, Date().addingTimeInterval(TimeInterval(token.expiresIn)))
        return token.accessToken
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct TokenFailure: Decodable {
        let error: String
    }
}
