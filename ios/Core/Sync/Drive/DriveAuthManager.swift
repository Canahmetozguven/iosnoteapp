import Foundation

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
@Observable
final class DriveAuthManager {
    var isConnected: Bool = false
    var userEmail: String? = nil
    var lastError: String? = nil

    private(set) var accessToken: String? = nil

    func connect() async {
        lastError = nil
        #if canImport(GoogleSignIn)
        guard let presenter = TopViewController.current() else {
            lastError = "No presenter available"
            return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            // Ensure Drive scope for reading/writing backups.
            let driveScope = "https://www.googleapis.com/auth/drive.file"
            let granted = result.user.grantedScopes ?? []
            if !granted.contains(driveScope) {
                _ = try await GIDSignIn.sharedInstance.addScopes([driveScope], presenting: presenter)
            }

            let user = GIDSignIn.sharedInstance.currentUser ?? result.user
            userEmail = user.profile?.email
            accessToken = user.accessToken.tokenString
            isConnected = true
        } catch {
            lastError = error.localizedDescription
            isConnected = false
        }
        #else
        lastError = "GoogleSignIn not available. Add the GoogleSignIn package."
        isConnected = false
        #endif
    }

    func disconnect() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        isConnected = false
        userEmail = nil
        accessToken = nil
    }

    func refreshTokenIfNeeded() async {
        #if canImport(GoogleSignIn)
        guard let user = GIDSignIn.sharedInstance.currentUser else { return }
        do {
            let refreshed = try await user.refreshTokensIfNeeded()
            userEmail = refreshed.profile?.email ?? userEmail
            accessToken = refreshed.accessToken.tokenString
            isConnected = true
        } catch {
            lastError = error.localizedDescription
        }
        #endif
    }
}
