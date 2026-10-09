import Foundation

// Standalone, sandbox-signed local integration probe; never linked into the notch.
@main struct LocalConnectionProbe {
    @MainActor static func main() async {
        struct Input: Decodable { let token, service: String }
        do {
            let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
            let credentials = CoursePathKeychain(service: input.service)
            defer { try? credentials.delete(server: .local) }
            try credentials.save(input.token, server: .local)
            guard try credentials.read(server: .local) == input.token else { throw CoursePathError.invalidToken }
            let store = CoursePathStore(credentials: credentials)
            store.selectServer(.local)
            guard await store.connect(input.token), store.snapshot?.revision == 1 else { throw CoursePathError.invalidResponse }
            guard await store.setTaskCompletion("first", completed: true), store.snapshot?.revision == 2 else { throw CoursePathError.invalidResponse }
            guard store.snapshot?.tasks.first(where: { $0.id == "second" })?.completed == false,
                  store.snapshot?.assignments.first?.completed == false else { throw CoursePathError.invalidResponse }
            guard await store.setTaskCompletion("first", completed: false), store.snapshot?.revision == 3 else { throw CoursePathError.invalidResponse }
            // A second client changes progress before the store's next mutation.
            _ = try await CoursePathAPIClient().complete(server: .local, token: input.token, taskId: "first", completed: true, revision: 3)
            let conflict = await store.setTaskCompletion("first", completed: false)
            guard !conflict, store.snapshot?.revision == 4, store.snapshot?.tasks.first?.completed == true else { throw CoursePathError.invalidResponse }
            store.disconnect()
            guard try credentials.read(server: .local) == nil else { throw CoursePathError.invalidToken }
            print("PASS: sandboxed Keychain lifecycle, authentication, approved snapshot, individual-step completion, partial assignment integrity, restoration and conflict refresh (revision 4).")
        } catch {
            // Errors are fixed local categories, never raw request headers or response bodies.
            print("FAIL: \((error as? CoursePathError)?.localizedDescription ?? "Local connection probe failed.")")
            exit(1)
        }
    }
}
