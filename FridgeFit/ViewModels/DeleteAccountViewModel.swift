//
//  DeleteAccountViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// State for the Delete Account flow.
///
/// ## The states, and why they are a closed enum
///
/// Deletion is the one irreversible action in FridgeFit, and the difference
/// between "we are about to", "we are halfway", "we stopped and changed
/// nothing" and "it is done" has to be unmistakable on screen. A pair of
/// loose `isLoading` / `errorMessage` properties can represent combinations
/// that make no sense - deleting *and* finished, finished *and* failed - and
/// the one that matters most, "your data is gone but your login is not", has
/// no representation at all. So the screen reads one `phase`.
@MainActor
final class DeleteAccountViewModel: ObservableObject {

    /// Where the flow is.
    enum Phase: Equatable {
        /// The confirmation step. Nothing has been touched.
        case confirming
        /// Firebase wants a fresh sign-in. Carries what this account can
        /// prove itself with, so the sheet asks for the right thing.
        case needsReauthentication([AccountAuthProvider])
        /// In flight. The destructive button is disabled in this phase,
        /// which is what stops a double tap starting a second deletion.
        case deleting
        /// Stopped. Carries the error so the copy can say which of "nothing
        /// happened" and "your data is gone" the user is in.
        case failed(DeleteAccountError)
        /// Done. The account and its data are both gone.
        case deleted
    }

    @Published private(set) var phase: Phase = .confirming
    /// The password typed into the reauthentication step. Held here rather
    /// than in the view so it can be cleared the moment it is no longer
    /// needed.
    @Published var password = ""

    private let useCase: DeleteAccountUseCase

    init(useCase: DeleteAccountUseCase) {
        self.useCase = useCase
    }

    var accountEmail: String? { useCase.accountEmail }

    var isDeleting: Bool { phase == .deleting }

    var isFinished: Bool { phase == .deleted }

    /// Whether the destructive action can be triggered right now.
    ///
    /// False while deleting (no concurrent attempts), false once finished,
    /// and - in the reauthentication phase - false until the required proof
    /// has actually been supplied.
    var canSubmit: Bool {
        switch phase {
        case .deleting, .deleted:
            return false
        case .confirming:
            return true
        case .failed(let error):
            return error.isRetryable
        case .needsReauthentication(let providers):
            if providers.contains(.password) {
                return !password.isEmpty
            }
            return providers.contains(.google)
        }
    }

    /// The error on screen, if any.
    var error: DeleteAccountError? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    /// Whether the user is being asked for a password.
    ///
    /// Only when the account genuinely has a password provider. A Google-only
    /// account is never shown this field - it would be asking for a
    /// credential that does not exist.
    var isAskingForPassword: Bool {
        guard case .needsReauthentication(let providers) = phase else { return false }
        return providers.contains(.password)
    }

    /// Whether the user is being sent back through Google.
    var isAskingForGoogle: Bool {
        guard case .needsReauthentication(let providers) = phase else { return false }
        return !providers.contains(.password) && providers.contains(.google)
    }

    /// What to tell the user they must do to re-confirm.
    var reauthenticationPrompt: String? {
        guard case .needsReauthentication(let providers) = phase else { return nil }
        if providers.contains(.password) { return AccountAuthProvider.password.reauthenticationPrompt }
        if providers.contains(.google) { return AccountAuthProvider.google.reauthenticationPrompt }
        return AccountAuthProvider.other.reauthenticationPrompt
    }

    /// Runs (or resumes) the deletion.
    ///
    /// Safe to call again after a failure: every stage underneath is
    /// idempotent, so a retry finishes whatever was left rather than
    /// repeating work or double-deleting.
    func deleteAccount() async {
        // The one place concurrent attempts are stopped. `canSubmit` already
        // disables the button, but a view can be re-entered faster than a
        // state change propagates, and starting two deletions would mean two
        // `user.delete()` calls racing - the loser reporting a failure for an
        // account that was in fact deleted.
        guard !isDeleting, phase != .deleted else { return }

        let method = reauthenticationMethod()
        phase = .deleting

        do {
            try await useCase.execute(reauthentication: method)
            password = ""
            phase = .deleted
        } catch let error as DeleteAccountError {
            handle(error)
        } catch {
            // Nothing below throws anything else, but reporting an
            // unexpected error as a *failure* rather than letting it escape
            // keeps the screen out of a stuck `deleting` state.
            phase = .failed(.accountDeletionFailed(error.localizedDescription))
        }
    }

    /// What proof to present on this attempt.
    private func reauthenticationMethod() -> ReauthenticationMethod? {
        switch phase {
        case .needsReauthentication(let providers):
            if providers.contains(.password), !password.isEmpty {
                return .password(password)
            }
            if providers.contains(.google) {
                return .google
            }
            return nil
        case .failed(.wrongPassword), .failed(.reauthenticationFailed):
            // Retrying after a rejected proof: present the new one rather
            // than attempting an unauthenticated delete that would only
            // produce the same demand again.
            if !password.isEmpty { return .password(password) }
            return nil
        case .confirming, .deleting, .deleted, .failed:
            return nil
        }
    }

    private func handle(_ error: DeleteAccountError) {
        switch error {
        case .reauthenticationRequired(let providers):
            guard providers.contains(.password) || providers.contains(.google) else {
                // Nothing we can ask for. Say so rather than showing an
                // empty prompt.
                phase = .failed(.noSupportedReauthenticationMethod)
                return
            }
            phase = .needsReauthentication(providers)

        case .wrongPassword, .reauthenticationFailed:
            // Keep the field on screen so the user can correct it, but clear
            // the rejected value.
            password = ""
            phase = .failed(error)

        default:
            phase = .failed(error)
        }
    }
}
