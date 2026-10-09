import Foundation

protocol CoursePathAPI {
    func snapshot(server: CoursePathServer, token: String, today: String) async throws -> CoursePathSnapshot
    func complete(server: CoursePathServer, token: String, taskId: String, completed: Bool, revision: Int) async throws -> CoursePathCompletion
}

final class CoursePathNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward bearer credentials to a redirect target.
    }
}

struct CoursePathAPIClient: CoursePathAPI {
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration, delegate: CoursePathNoRedirects(), delegateQueue: nil)
    }
    func snapshot(server: CoursePathServer, token: String, today: String) async throws -> CoursePathSnapshot {
        guard CoursePathDate.date(today) != nil else { throw CoursePathError.invalidResponse }
        var url = URLComponents(url: server.baseURL.appendingPathComponent("api/desktop/snapshot"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "today", value: today)]
        let result: CoursePathSnapshot = try await send(request(url.url!, token: token))
        guard result.revision >= 0 else { throw CoursePathError.invalidResponse }
        return result
    }
    func complete(server: CoursePathServer, token: String, taskId: String, completed: Bool, revision: Int) async throws -> CoursePathCompletion {
        struct Payload: Encodable { let taskId: String; let completed: Bool; let revision: Int }
        var request = request(server.baseURL.appendingPathComponent("api/desktop/task-completion"), token: token)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(Payload(taskId: taskId, completed: completed, revision: revision))
        let result: CoursePathCompletion = try await send(request)
        guard result.revision >= revision, result.taskId == taskId, result.completed == completed else { throw CoursePathError.invalidResponse }
        return result
    }
    private func request(_ url: URL, token: String) -> URLRequest {
        // URLs come exclusively from the fixed HTTPS production and loopback presets.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "X-CoursePath")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CoursePathError.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 401, 403: throw CoursePathError.unauthorized
            case 409: throw CoursePathError.conflict
            default: throw CoursePathError.http(response.statusCode)
            }
            guard data.count <= 4 * 1024 * 1024 else { throw CoursePathError.invalidResponse }
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw CoursePathError.invalidResponse }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? CoursePathError.timeout : CoursePathError.offline
        }
    }
}
