@preconcurrency import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import Observation
import UIKit

@MainActor
@Observable
final class AccountSession {
    private(set) var configurationState: FirebaseConfigurationState = .checking
    private(set) var account: StylezamAccount?
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var accountChangeHandler: ((StylezamAccount?) -> Void)?

    var isAuthenticated: Bool { account != nil }
    var isDeveloper: Bool { account?.isDeveloper == true }

    func setAccountChangeHandler(_ handler: ((StylezamAccount?) -> Void)?) {
        accountChangeHandler = handler
    }

    func start() async {
        guard configureFirebaseIfPresent() else { return }
        if let user = Auth.auth().currentUser {
            // Developer access is delivered by a signed Firebase custom claim.
            // Always refresh at launch so a newly granted role does not remain
            // hidden behind Firebase's cached ID token.
            await loadAccount(from: user, forceTokenRefresh: true)
        } else {
            account = nil
            accountChangeHandler?(nil)
        }
    }

    func signInWithGoogle() async {
        guard configureFirebaseIfPresent() else { return }
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            configurationState = .invalidPlist
            return
        }
        guard let presenter = Self.presentingViewController() else {
            errorMessage = "Stylezam could not present Google Sign-In. Try again after reopening the app."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AccountSessionError.missingGoogleToken
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            await loadAccount(from: authResult.user, forceTokenRefresh: true)
        } catch is CancellationError {
            return
        } catch {
            let nsError = error as NSError
            if nsError.domain == "com.google.GIDSignIn" && nsError.code == -5 { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshDeveloperAccess() async {
        guard let user = Auth.auth().currentUser else { return }
        await loadAccount(from: user, forceTokenRefresh: true)
    }

    func updateProfile(_ profile: LocalUserProfile) {
        guard var current = account else { return }
        let normalized = LocalUserProfile(
            displayName: String(profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
            username: String(profile.username.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)),
            styleNote: String(profile.styleNote.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        )
        current.profile = normalized
        account = current
        saveProfile(normalized, uid: current.uid)
    }

    func signOut() {
        errorMessage = nil
        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
            account = nil
            accountChangeHandler?(nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let uid = user.uid
            try await user.delete()
            UserDefaults.standard.removeObject(forKey: profileKey(uid: uid))
            GIDSignIn.sharedInstance.signOut()
            account = nil
            accountChangeHandler?(nil)
            return true
        } catch {
            errorMessage = "Google may require you to sign in again before deleting the account. \(error.localizedDescription)"
            return false
        }
    }

    private func configureFirebaseIfPresent() -> Bool {
        if FirebaseApp.app() != nil {
            configurationState = .ready
            return true
        }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
            configurationState = .missingPlist
            account = nil
            return false
        }
        guard let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == Bundle.main.bundleIdentifier
        else {
            configurationState = .invalidPlist
            account = nil
            return false
        }
        FirebaseApp.configure(options: options)
        configurationState = .ready
        return true
    }

    private func loadAccount(from user: User, forceTokenRefresh: Bool) async {
        do {
            let token = try await user.getIDTokenResult(forcingRefresh: forceTokenRefresh)
            let developer = token.claims["developer"] as? Bool == true
            let googleName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = user.email?.split(separator: "@").first.map(String.init) ?? "Stylezam member"
            let resolvedName = (googleName?.isEmpty == false ? googleName : nil) ?? fallbackName
            account = StylezamAccount(
                uid: user.uid,
                email: user.email ?? "",
                googleDisplayName: resolvedName,
                photoURL: user.photoURL,
                profile: loadProfile(uid: user.uid, defaultName: resolvedName),
                isDeveloper: developer
            )
            accountChangeHandler?(account)
            errorMessage = nil
        } catch {
            errorMessage = "Your account signed in, but its access role could not be verified. \(error.localizedDescription)"
            account = nil
            accountChangeHandler?(nil)
        }
    }

    private func profileKey(uid: String) -> String { "stylezam.account.profile.\(uid)" }

    private func loadProfile(uid: String, defaultName: String) -> LocalUserProfile {
        guard let data = UserDefaults.standard.data(forKey: profileKey(uid: uid)),
              let profile = try? JSONDecoder().decode(LocalUserProfile.self, from: data)
        else { return .initial(displayName: defaultName) }
        return profile
    }

    private func saveProfile(_ profile: LocalUserProfile, uid: String) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey(uid: uid))
    }

    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        if let navigation = controller as? UINavigationController { return navigation.visibleViewController }
        if let tab = controller as? UITabBarController { return tab.selectedViewController }
        return controller
    }
}

enum AccountSessionError: LocalizedError {
    case missingGoogleToken

    var errorDescription: String? {
        switch self {
        case .missingGoogleToken: "Google Sign-In did not return an identity token."
        }
    }
}
