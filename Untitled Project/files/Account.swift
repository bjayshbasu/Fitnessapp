import Foundation
import Observation
#if canImport(FirebaseAuth)
import FirebaseCore
import FirebaseAuth
#endif

// Email and password accounts, using Firebase Authentication.
// Until GoogleService-Info.plist is added to the project, accounts are
// switched off and the app works without signing in.
@Observable
@MainActor
final class AccountManager {
    enum State: Equatable {
        case unavailable   // Firebase not set up yet
        case loading
        case signedOut
        case signedIn(uid: String, email: String, name: String)
    }

    private(set) var state: State = .loading

    var uid: String? {
        if case .signedIn(let uid, _, _) = state { return uid }
        return nil
    }

    var email: String {
        if case .signedIn(_, let email, _) = state { return email }
        return ""
    }

    var displayName: String {
        if case .signedIn(_, _, let name) = state { return name }
        return ""
    }

    #if canImport(FirebaseAuth)
    private var listener: AuthStateDidChangeListenerHandle?
    #endif

    init() {
        #if canImport(FirebaseAuth)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            state = .unavailable
            #if DEBUG
            // Test-only: launch with "-previewLogin" to see the login screens before Firebase is set up.
            if ProcessInfo.processInfo.arguments.contains("-previewLogin") { state = .signedOut }
            #endif
            return
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.update(from: user) }
        }
        #else
        state = .unavailable
        #endif
    }

    // MARK: Actions

    func signUp(name: String, email: String, password: String) async throws {
        #if canImport(FirebaseAuth)
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try await change.commitChanges()
            update(from: result.user)
        } catch {
            throw AccountError(error)
        }
        #endif
    }

    func signIn(email: String, password: String) async throws {
        #if canImport(FirebaseAuth)
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            throw AccountError(error)
        }
        #endif
    }

    func sendPasswordReset(email: String) async throws {
        #if canImport(FirebaseAuth)
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw AccountError(error)
        }
        #endif
    }

    func updateName(_ name: String) async throws {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else { return }
        do {
            let change = user.createProfileChangeRequest()
            change.displayName = name
            try await change.commitChanges()
            update(from: user)
        } catch {
            throw AccountError(error)
        }
        #endif
    }

    func signOut() {
        #if canImport(FirebaseAuth)
        try? Auth.auth().signOut()
        #endif
    }

    // Deleting an account asks for the password again, as Firebase requires a recent sign-in.
    func deleteAccount(password: String) async throws {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser, let email = user.email else { return }
        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: credential)
            try await user.delete()
        } catch {
            throw AccountError(error)
        }
        #endif
    }

    #if canImport(FirebaseAuth)
    private func update(from user: User?) {
        if let user {
            state = .signedIn(uid: user.uid, email: user.email ?? "",
                              name: user.displayName ?? "")
        } else {
            state = .signedOut
        }
    }
    #endif
}

// Plain-English messages for the errors people actually hit.
struct AccountError: LocalizedError {
    let message: String

    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }

    init(_ error: Error) {
        let nsError = error as NSError
        guard nsError.domain == "FIRAuthErrorDomain" else {
            message = error.localizedDescription
            return
        }
        // Firebase Auth error codes (stable across SDK versions).
        switch nsError.code {
        case 17007: message = "There's already an account with this email. Try logging in instead."
        case 17008: message = "That email address doesn't look right."
        case 17009, 17004, 17011: message = "Wrong email or password."
        case 17026: message = "Choose a stronger password: at least 8 characters."
        case 17010: message = "Too many attempts. Wait a few minutes and try again."
        case 17020: message = "No internet connection. Check your connection and try again."
        case 17005: message = "This account has been disabled."
        case 17014: message = "For your security, please log in again first."
        default: message = error.localizedDescription
        }
    }
}

enum AccountValidation {
    static func isEmail(_ text: String) -> Bool {
        text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    static let minimumPasswordLength = 8
}
