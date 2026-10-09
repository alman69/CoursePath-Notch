import Foundation
import CryptoKit
import Security

struct CoursePathPKCE {
    static let clientID = "dev.coursepath.notch"
    static let callback = "dev.coursepath.notch:/oauth/callback"
    let verifier: String
    let state: String
    var challenge: String { Self.base64(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    init() throws { verifier = try Self.random(); state = try Self.random() }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw CoursePathError.keychain(status) }
        return base64(Data(bytes))
    }
    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func code(from callback: URL) throws -> String {
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme == "dev.coursepath.notch", parts.host == nil, parts.path == "/oauth/callback", parts.fragment == nil else { throw CoursePathError.invalidResponse }
        let items = parts.queryItems ?? []
        guard items.allSatisfy({ ["state", "code", "error"].contains($0.name) }),
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count + items.filter({ $0.name == "error" }).count == 1 else { throw CoursePathError.invalidResponse }
        if items.first(where: { $0.name == "error" })?.value == "access_denied" { throw CancellationError() }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              code.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else { throw CoursePathError.invalidResponse }
        return code
    }
}

struct CoursePathPairedCredential: Codable, Equatable {
    let accessToken, refreshToken, deviceId: String
    let accessExpiresAt, sessionExpiresAt: Date
    func validate(now: Date) throws {
        guard accessToken.range(of: #"^cpna_[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil,
              refreshToken.range(of: #"^cpnr_[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil,
              UUID(uuidString: deviceId) != nil, sessionExpiresAt > now,
              accessExpiresAt <= now.addingTimeInterval(660), sessionExpiresAt <= now.addingTimeInterval(181 * 86400) else { throw CoursePathError.unauthorized }
    }
}
struct CoursePathPairing: Decodable {
    let requestId, authorizationURL, confirmation: String
    let expiresIn: Int
    func browserURL() throws -> URL {
        guard let url = URL(string: authorizationURL), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http://127.0.0.1:5173", "http://localhost:5173"].contains("\(parts.scheme ?? "")://\(parts.host ?? ""):\(parts.port ?? 0)"),
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.path == "/desktop/connect",
              parts.queryItems == [URLQueryItem(name: "request", value: requestId)],
              requestId.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil,
              confirmation.range(of: #"^[0-9A-F]{8}$"#, options: .regularExpression) != nil, expiresIn > 0, expiresIn <= 300 else { throw CoursePathError.invalidResponse }
        return url
    }
}
protocol CoursePathAuthAPI {
    func start(server: CoursePathServer, pkce: CoursePathPKCE) async throws -> CoursePathPairing
    func exchange(server: CoursePathServer, code: String, verifier: String) async throws -> CoursePathPairedCredential
    func renew(server: CoursePathServer, refreshToken: String) async throws -> CoursePathPairedCredential
    func revoke(server: CoursePathServer, refreshToken: String) async throws
    func cancel(server: CoursePathServer, requestId: String, verifier: String) async throws
}

struct CoursePathAuthClient: CoursePathAuthAPI {
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config, delegate: CoursePathNoRedirects(), delegateQueue: nil)
    }
    private struct Tokens: Decodable {
        let accessToken, refreshToken, deviceId, accessExpiresAt, sessionExpiresAt, scope: String
        func credential() throws -> CoursePathPairedCredential {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard scope == "approved-plan:read task-completion:write", let access = formatter.date(from: accessExpiresAt), let expiry = formatter.date(from: sessionExpiresAt) else { throw CoursePathError.invalidResponse }
            return CoursePathPairedCredential(accessToken: accessToken, refreshToken: refreshToken, deviceId: deviceId, accessExpiresAt: access, sessionExpiresAt: expiry)
        }
    }
    private func post<T: Decodable>(_ route: String, server: CoursePathServer, body: [String: String]) async throws -> T {
        // Until live browser verification, no paired requests can reach production.
        guard server != .production else { throw CoursePathError.unauthorized }
        var request = URLRequest(url: server.baseURL.appendingPathComponent("api/desktop-auth/" + route))
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(body)
        request.setValue("1", forHTTPHeaderField: "X-CoursePath")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("http://127.0.0.1:5173", forHTTPHeaderField: "Origin")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CoursePathError.invalidResponse }
            if [401, 403].contains(response.statusCode) { throw CoursePathError.unauthorized }
            guard response.statusCode == 200 else { throw CoursePathError.http(response.statusCode) }
            guard data.count < 16384 else { throw CoursePathError.invalidResponse }
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw CoursePathError.invalidResponse }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? CoursePathError.timeout : CoursePathError.offline
        }
    }
    func start(server: CoursePathServer, pkce: CoursePathPKCE) async throws -> CoursePathPairing {
        try await post("start", server: server, body: ["clientId": CoursePathPKCE.clientID, "redirectURI": CoursePathPKCE.callback, "codeChallenge": pkce.challenge, "codeChallengeMethod": "S256", "state": pkce.state, "label": "CoursePath Notch on Mac"])
    }
    func exchange(server: CoursePathServer, code: String, verifier: String) async throws -> CoursePathPairedCredential {
        let wire: Tokens = try await post("exchange", server: server, body: ["clientId": CoursePathPKCE.clientID, "redirectURI": CoursePathPKCE.callback, "code": code, "codeVerifier": verifier])
        return try wire.credential()
    }
    func renew(server: CoursePathServer, refreshToken: String) async throws -> CoursePathPairedCredential {
        let wire: Tokens = try await post("refresh", server: server, body: ["clientId": CoursePathPKCE.clientID, "refreshToken": refreshToken])
        return try wire.credential()
    }
    func revoke(server: CoursePathServer, refreshToken: String) async throws {
        struct Response: Decodable { let disconnected: Bool }
        let result: Response = try await post("disconnect", server: server, body: ["clientId": CoursePathPKCE.clientID, "refreshToken": refreshToken])
        guard result.disconnected else { throw CoursePathError.invalidResponse }
    }
    func cancel(server: CoursePathServer, requestId: String, verifier: String) async throws {
        struct Response: Decodable { let cancelled: Bool }
        let _: Response = try await post("cancel", server: server, body: ["requestId": requestId, "codeVerifier": verifier])
    }
}

@MainActor
final class CoursePathAuth {
    static var developmentEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["COURSEPATH_BROWSER_PAIRING"] == "1"
        #else
        return false
        #endif
    }
    let enabled: Bool
    private let api: CoursePathAuthAPI
    private let storage: CoursePathCredentialStorage
    private let now: () -> Date
    private var generation = UUID()
    private var renewal: Task<CoursePathPairedCredential, Error>?
    private(set) var credential: CoursePathPairedCredential?
    private var loadedServer: CoursePathServer?
    private var renewalUncertain = false
    init(api: CoursePathAuthAPI = CoursePathAuthClient(), storage: CoursePathCredentialStorage = CoursePathKeychain(service: "dev.coursepath.notch.paired"), now: @escaping () -> Date = Date.init, enabled: Bool? = nil) {
        self.api = api; self.storage = storage; self.now = now; self.enabled = enabled ?? Self.developmentEnabled
    }
    func load(server: CoursePathServer) throws {
        generation = UUID(); renewal?.cancel(); renewal = nil; credential = nil; loadedServer = server; renewalUncertain = false
        guard enabled, server != .production else { return }
        guard let json = try storage.read(server: server) else { return }
        do {
            let value = try JSONDecoder().decode(CoursePathPairedCredential.self, from: Data(json.utf8))
            try value.validate(now: now()); credential = value
        } catch { try storage.delete(server: server); throw CoursePathError.unauthorized }
    }
    private func save(_ value: CoursePathPairedCredential, server: CoursePathServer) throws {
        try value.validate(now: now())
        guard value.accessExpiresAt > now(), value.accessExpiresAt <= value.sessionExpiresAt else { throw CoursePathError.invalidResponse }
        try storage.save(String(decoding: JSONEncoder().encode(value), as: UTF8.self), server: server)
        credential = value; loadedServer = server; renewalUncertain = false
    }
    func authorize(server: CoursePathServer, confirmation: (String) -> Void, browser: (URL) async throws -> URL) async throws {
        guard enabled, server != .production, credential == nil else { throw CoursePathError.unauthorized }
        let version = generation, pkce = try CoursePathPKCE()
        let pairing = try await api.start(server: server, pkce: pkce)
        do {
            try Task.checkCancellation(); guard generation == version else { throw CancellationError() }
            let url = try pairing.browserURL(); confirmation(pairing.confirmation)
            let callback = try await browser(url)
            try Task.checkCancellation(); guard generation == version else { throw CancellationError() }
            let code = try pkce.code(from: callback)
            let result = try await api.exchange(server: server, code: code, verifier: pkce.verifier)
            // A consumed code must never be retried. Revoke if cancellation/storage fails.
            do {
                try Task.checkCancellation(); guard generation == version else { throw CancellationError() }
                try save(result, server: server)
            } catch { try? await api.revoke(server: server, refreshToken: result.refreshToken); throw error }
        } catch { try? await api.cancel(server: server, requestId: pairing.requestId, verifier: pkce.verifier); throw error }
    }
    func accessToken(server: CoursePathServer) async throws -> String {
        guard enabled, server != .production, loadedServer == server, let old = credential, !renewalUncertain else { throw CoursePathError.unauthorized }
        guard old.sessionExpiresAt > now() else { throw CoursePathError.unauthorized }
        if old.accessExpiresAt > now().addingTimeInterval(30) { return old.accessToken }
        if let renewal { return try await renewal.value.accessToken }
        let version = generation, api = api
        // Single flight. Once rotation has been issued, finish and persist it even if
        // a visibility read is canceled; losing that response would lose the session.
        let task = Task { [self] in
            do {
                let next = try await api.renew(server: server, refreshToken: old.refreshToken)
                guard generation == version else { throw CancellationError() }
                guard next.deviceId == old.deviceId, next.refreshToken != old.refreshToken else { throw CoursePathError.invalidResponse }
                try save(next, server: server)
                return next
            } catch {
                if generation == version { renewalUncertain = true }
                throw error
            }
        }
        renewal = task
        defer { if generation == version { renewal = nil } }
        return try await task.value.accessToken
    }
    func remove(server: CoursePathServer) throws -> CoursePathPairedCredential? {
        let previous = credential
        generation = UUID(); renewal?.cancel(); renewal = nil; credential = nil; renewalUncertain = false
        try storage.delete(server: server)
        return previous
    }
    func revoke(_ credential: CoursePathPairedCredential, server: CoursePathServer) async throws {
        try await api.revoke(server: server, refreshToken: credential.refreshToken)
    }
}
