import Foundation
import Observation
import Supabase

/// Who is signed in. Email plus a six-digit code; a magic link opening the app through the
/// `timecontrol://auth-callback` URL scheme signs in the same way. Session persistence and refresh
/// are the SDK's; this only mirrors them into observable state and owns the profile row.
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    enum State: Equatable, Sendable {
        /// The build carries no Supabase configuration; sync and groups are unavailable.
        case unavailable
        case signedOut
        case signedIn(userID: UUID, email: String?)
    }

    enum AuthError: Error, LocalizedError {
        case unavailable
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .unavailable: "This build has no account service configured."
            case .notSignedIn: "Sign in first."
            }
        }
    }

    private(set) var state: State {
        didSet { if state != oldValue { stateContinuation.yield(state) } }
    }
    /// The signed-in user's profile name, as other members see it.
    private(set) var displayName: String = ""
    /// Every change of `state`, for the one service that reacts to sign-in and sign-out.
    let stateChanges: AsyncStream<State>

    private let client: SupabaseClient?
    private let stateContinuation: AsyncStream<State>.Continuation
    private var listener: Task<Void, Never>?

    init(client: SupabaseClient? = SupabaseClientProvider.shared) {
        self.client = client
        state = client == nil ? .unavailable : .signedOut
        (stateChanges, stateContinuation) = AsyncStream.makeStream(of: State.self)
    }

    var isAvailable: Bool { client != nil }

    var userID: UUID? {
        if case .signedIn(let id, _) = state { return id }
        return nil
    }

    var email: String? {
        if case .signedIn(_, let email) = state { return email }
        return nil
    }

    var isSignedIn: Bool { userID != nil }

    /// Picks up the stored session and follows sign-ins, sign-outs and token refreshes from then on.
    func start() {
        guard let client, listener == nil else { return }
        apply(client.auth.currentSession)
        listener = Task { [weak self] in
            for await change in client.auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    apply(change.session)
                case .signedOut, .userDeleted:
                    apply(nil)
                default:
                    break
                }
            }
        }
    }

    private func apply(_ session: Session?) {
        let previous = userID
        if let session {
            state = .signedIn(userID: session.user.id, email: session.user.email)
            if previous != session.user.id {
                displayName = ""
                Task { await loadProfile() }
            }
        } else {
            state = client == nil ? .unavailable : .signedOut
            displayName = ""
        }
    }

    // MARK: Sign in

    /// Emails a six-digit code (and a magic link) to `email`, creating the account on first use.
    func sendCode(to email: String) async throws {
        guard let client else { throw AuthError.unavailable }
        try await client.auth.signInWithOTP(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            redirectTo: URL(string: "timecontrol://auth-callback"),
            shouldCreateUser: true
        )
    }

    /// Exchanges the emailed code for a session.
    func verify(email: String, code: String) async throws {
        guard let client else { throw AuthError.unavailable }
        let digits = code.filter(\.isNumber)
        try await client.auth.verifyOTP(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            token: digits,
            type: .email
        )
    }

    /// A magic link opened the app. Returns whether the URL was an auth callback the SDK accepted.
    @discardableResult
    func handle(url: URL) async -> Bool {
        guard let client, url.scheme == "timecontrol" else { return false }
        do {
            _ = try await client.auth.session(from: url)
            return true
        } catch {
            print("AuthService: callback URL rejected: \(error)")
            return false
        }
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
        } catch {
            // A failed network sign-out still clears the local session in the SDK; mirror that.
            print("AuthService: signOut failed: \(error)")
        }
        apply(nil)
    }

    // MARK: Profile

    func loadProfile() async {
        guard let client, let userID else { return }
        do {
            let row: ProfileRow = try await client
                .from("profiles")
                .select("id, display_name, updated_at")
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            displayName = row.displayName
        } catch {
            print("AuthService: loadProfile failed: \(error)")
        }
    }

    func updateDisplayName(_ name: String) async throws {
        guard let client else { throw AuthError.unavailable }
        guard let userID else { throw AuthError.notSignedIn }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client
            .from("profiles")
            .update(["display_name": trimmed])
            .eq("id", value: userID.uuidString)
            .execute()
        displayName = trimmed
    }
}
