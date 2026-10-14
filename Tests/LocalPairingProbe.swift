import Foundation

// Browser consent is simulated with a disposable mock Clerk identity. This verifies
// HTTP/Keychain/Store integration; it does NOT claim real Clerk or browser E2E.
@main struct LocalPairingProbe {
    @MainActor static func main() async {
        struct Input: Codable { let token, clerkToken, accountId, service: String; var rotateOnly: Bool? }
        do {
            let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
            let manual = CoursePathKeychain(service: input.service), paired = CoursePathKeychain(service: input.service + ".paired")
            if input.rotateOnly == true {
                let worker = CoursePathAuth(storage: paired, enabled: true)
                try worker.load(server: .local)
                _ = try await worker.accessToken(server: .local)
                print("ROTATION_OK"); return
            }
            defer { try? manual.delete(server: .local); try? paired.delete(server: .local) }
            let auth = CoursePathAuth(storage: paired, enabled: true)
            let suite = input.service + ".preferences", prefs = UserDefaults(suiteName: suite)!
            defer { prefs.removePersistentDomain(forName: suite) }
            let store = CoursePathStore(credentials: manual, preferences: prefs, auth: auth)
            func website(_ route: String, body: [String: Any]) async throws -> [String: Any] {
                var request = URLRequest(url: CoursePathServer.local.baseURL.appendingPathComponent("api/" + route))
                request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.setValue("1", forHTTPHeaderField: "X-CoursePath"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer " + input.clerkToken, forHTTPHeaderField: "Authorization"); request.setValue(input.accountId, forHTTPHeaderField: "X-Account-ID")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoursePathError.invalidResponse }
                return value
            }
            let connected = await store.connectBrowser { url in
                let requestID = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
                let review = try await website("desktop-pairing/review", body: ["requestId": requestID])
                guard review["confirmation"] == nil, store.pairingConfirmation != nil else { throw CoursePathError.invalidResponse }
                let approved = try await website("desktop-pairing/decide", body: ["requestId": requestID, "csrf": review["csrf"]!, "approve": true, "confirmation": store.pairingConfirmation!])
                guard let callback = approved["callbackURL"] as? String, let url = URL(string: callback) else { throw CoursePathError.invalidResponse }
                return url
            }
            guard connected, store.snapshot?.revision == 1, let original = auth.credential else { throw CoursePathError.invalidResponse }
            // Expire the locally stored access credential, not the fixture session.
            let expired = CoursePathPairedCredential(accessToken: original.accessToken, refreshToken: original.refreshToken, deviceId: original.deviceId, accessExpiresAt: .now.addingTimeInterval(-1), sessionExpiresAt: original.sessionExpiresAt)
            try paired.save(String(decoding: JSONEncoder().encode(expired), as: UTF8.self), server: .local)
            // Two real processes load the same expired credential. Kernel locking
            // and fresh Keychain reads must yield one rotation, with no replay revoke.
            var childInput = input; childInput.rotateOnly = true
            let data = try JSONEncoder().encode(childInput)
            let workers = try (0..<2).map { _ -> (Process, Pipe) in
                let process = Process(), stdin = Pipe(), stdout = Pipe()
                process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stdout
                try process.run(); stdin.fileHandleForWriting.write(data); try stdin.fileHandleForWriting.close()
                return (process, stdout)
            }
            for (process, pipe) in workers {
                process.waitUntilExit()
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                guard process.terminationStatus == 0, output.contains("ROTATION_OK") else { throw CoursePathError.invalidResponse }
            }
            try auth.load(server: .local)
            guard await store.setTaskCompletion("first", completed: true), store.snapshot?.revision == 2,
                  auth.credential?.refreshToken != original.refreshToken, store.snapshot?.tasks.first?.completed == true else { throw CoursePathError.invalidResponse }
            guard await store.setTaskCompletion("first", completed: false), store.snapshot?.revision == 3 else { throw CoursePathError.invalidResponse }
            guard try manual.read(server: .local) == nil else { throw CoursePathError.invalidResponse }
            do { _ = try await CoursePathAuthClient().renew(server: .local, refreshToken: original.refreshToken); throw CoursePathError.invalidResponse }
            catch CoursePathError.unauthorized {} // Reuse revokes the whole family, including new access.
            guard !(await store.refresh()), store.status == .expired, !store.hasCredential,
                  try paired.read(server: .local) == nil else { throw CoursePathError.invalidResponse }
            guard await store.connect(input.token), store.snapshot?.revision == 3 else { throw CoursePathError.invalidResponse }
            store.disconnect()
            print("PASS: sandboxed pairing code exchange, separate Keychain storage, two-process coordinated rotation, completion/restoration after renewal, committed reuse revocation, and manual-token fallback. Browser/Clerk consent was simulated.")
        } catch {
            print("FAIL: \((error as? CoursePathError)?.localizedDescription ?? "Local pairing probe failed.")")
            exit(1)
        }
    }
}
