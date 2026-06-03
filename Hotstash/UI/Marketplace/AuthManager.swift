import AppKit
import AuthenticationServices
import Foundation
import OSLog

/// Sign in with Apple → Supabase session exchange for the marketplace.
///
/// Flow: `ASAuthorizationController` returns an Apple identity token, which is
/// exchanged with Supabase Auth (`/auth/v1/token?grant_type=id_token`) for an
/// access token used on authenticated marketplace writes (publish/rate/review/
/// report). Requires the `com.apple.developer.applesignin` entitlement and a
/// configured `Supabase.plist`; when the backend is unconfigured, sign-in is
/// unavailable and `errorMessage` explains why.
@MainActor
final class AuthManager: NSObject, ObservableObject {

    static let shared = AuthManager()

    @Published private(set) var accessToken: String?
    @Published private(set) var displayName: String?
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    private let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "Auth")
    private let session = URLSession.shared
    private static let displayNameKey = "com.zeyadamer.hotstash.appleDisplayName"

    private override init() {
        displayName = UserDefaults.standard.string(forKey: Self.displayNameKey)
        super.init()
    }

    var isSignedIn: Bool { accessToken != nil }

    /// Whether sign-in is possible (a backend must be configured to exchange tokens).
    var canSignIn: Bool { SupabaseConfig.current != nil }

    func signIn() {
        guard canSignIn else {
            errorMessage = "Marketplace backend not configured. Add Supabase.plist to enable publishing."
            return
        }
        errorMessage = nil
        isSigningIn = true
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        accessToken = nil
        // Keep the cached display name; Apple only returns the name on first sign-in.
    }

    // MARK: - Supabase exchange

    private func exchange(identityToken: String, fullName: String?) async {
        guard let config = SupabaseConfig.current else {
            finish(error: "Marketplace backend not configured.")
            return
        }
        guard let url = URL(string: config.url.absoluteString + "/auth/v1/token?grant_type=id_token") else {
            finish(error: "Invalid backend URL.")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": identityToken,
        ])
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                finish(error: "Sign-in failed (HTTP \(code)).")
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["access_token"] as? String else {
                finish(error: "Sign-in response was not understood.")
                return
            }
            let serverName = (obj["user"] as? [String: Any])
                .flatMap { ($0["user_metadata"] as? [String: Any])?["full_name"] as? String }
            let resolvedName = fullName ?? serverName ?? displayName
            if let resolvedName, !resolvedName.isEmpty {
                UserDefaults.standard.set(resolvedName, forKey: Self.displayNameKey)
            }
            accessToken = token
            displayName = resolvedName
            isSigningIn = false
            errorMessage = nil
        } catch {
            logger.error("Apple→Supabase exchange failed: \(error, privacy: .public)")
            finish(error: "Sign-in failed. Check your connection and try again.")
        }
    }

    private func finish(error: String) {
        isSigningIn = false
        errorMessage = error
    }
}

// MARK: - ASAuthorization delegate

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            finish(error: "Apple did not return an identity token.")
            return
        }
        let fullName = credential.fullName.flatMap { name -> String? in
            let parts = [name.givenName, name.familyName].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }
        Task { await exchange(identityToken: token, fullName: fullName) }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        // User cancellation is not an error worth surfacing loudly.
        if (error as? ASAuthorizationError)?.code == .canceled {
            isSigningIn = false
            return
        }
        finish(error: "Sign-in was cancelled or failed.")
    }
}

// MARK: - Presentation anchor

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        SettingsWindowController.shared.window
            ?? NSApp.keyWindow
            ?? NSApp.windows.first
            ?? ASPresentationAnchor()
    }
}
