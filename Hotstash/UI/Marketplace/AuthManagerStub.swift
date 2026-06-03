import Foundation

// TODO(S4): replaced by real Sign in with Apple (ASAuthorization) in task S4.
//
// Minimal stand-in so marketplace auth-gated controls (rate/review/report/publish)
// compile and are simply hidden while `accessToken` is nil. Do NOT implement
// ASAuthorization here — that is the separate S4 task.
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var accessToken: String?
    @Published var displayName: String?

    private init() {}

    func signInPlaceholder() {}
}
