import AppKit
import AuthenticationServices

// ASWebAuthenticationSession uses the external browser's Clerk session. No web view,
// Clerk bearer credential or browser cookie is exposed to the native application.
@MainActor
final class CoursePathBrowserSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var timeout: Task<Void, Never>?
    private var completion: CheckedContinuation<URL, Error>?
    func open(_ url: URL) async throws -> URL {
        guard session == nil else { throw CoursePathError.invalidResponse }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                let value = ASWebAuthenticationSession(url: url, callbackURLScheme: "dev.coursepath.notch") { [weak self] callback, error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let callback { self.finish(.success(callback)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { self.finish(.failure(CancellationError())) }
                        else { self.finish(.failure(CoursePathError.invalidResponse)) }
                    }
                }
                value.presentationContextProvider = self
                value.prefersEphemeralWebBrowserSession = false
                session = value
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    guard !Task.isCancelled else { return }
                    self?.cancel()
                }
                if !value.start() { finish(.failure(CoursePathError.invalidResponse)) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? NSWindow()
    }
    func cancel() {
        session?.cancel()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<URL, Error>) {
        timeout?.cancel(); timeout = nil
        session = nil
        let continuation = completion; completion = nil
        continuation?.resume(with: result)
    }
}
