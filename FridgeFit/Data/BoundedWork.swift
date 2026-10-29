//
//  BoundedWork.swift
//  FridgeFit
//

import Foundation

/// Runs one asynchronous operation under a hard deadline, and **returns at
/// the deadline whether or not the operation itself ever finishes**.
///
/// Used for the two kinds of work in FridgeFit that can hang without
/// reporting anything: on-device model generation (see
/// `AppleSubstitutionService`, `AppleReceiptIngredientInterpreter`,
/// `AppleRecipeSuggestionService`) and waiting for Firestore to acknowledge a
/// write (`FirestoreBudgetStore` and friends, where the wait is bounded so an
/// offline device reports a queued write instead of spinning).
///
/// ## Why this exists rather than a task group
///
/// The obvious way to bound an `async` call is to race it against a sleeping
/// sibling inside `withThrowingTaskGroup`, take `group.next()`, and
/// `cancelAll()`. `AppleSubstitutionService` was written that way and it does
/// not work for this problem, for a reason that only shows up with the exact
/// failure it was meant to protect against.
///
/// A task group is a *structured* scope: when its body returns, the group
/// implicitly awaits every child that is still running. `cancelAll()` sets
/// the cancellation flag on those children - it does not stop them. A child
/// that never checks cancellation, and never reaches a cancellable
/// suspension point, keeps the scope open, so `withThrowingTaskGroup` does
/// not return and the caller stays suspended. The timeout fires, the error
/// is produced, and nobody receives it until the operation it was supposed
/// to abandon finishes on its own.
///
/// `LanguageModelSession.respond` is precisely that kind of child. On a
/// device where `SystemLanguageModel.default.availability` reports
/// `.available` but no model assets are installed - the iOS 26 simulator
/// does exactly this - `respond` neither returns nor throws
/// `assetsUnavailable`. It simply never completes. Racing it in a task group
/// therefore produces a spinner that runs forever *with* a timeout in place,
/// which is the bug the timeout was added to prevent.
///
/// So the race here is deliberately **unstructured**. The operation runs in
/// its own detached task and reports into a single-assignment box; the
/// caller waits on the box, not on the operation. Whichever of
/// {operation finished, deadline elapsed, caller cancelled} happens first
/// resolves the box and the caller resumes immediately. The losing task is
/// cancelled as a courtesy - it stops promptly if it is well behaved, and if
/// it is not, it is simply no longer anybody's problem.
///
/// ## What the leak costs, and why it is the right trade
///
/// An operation that ignores cancellation keeps running after this function
/// returns, holding whatever the model holds until the process ends. That is
/// a real cost and it is accepted on purpose: the alternative is an
/// indefinite spinner with no way out, and a user who can retry or type the
/// item in by hand is strictly better off than one watching a progress view
/// that will never stop. Nothing is retained by FridgeFit itself - the box
/// and both tasks are unreferenced once the caller resumes.
///
/// ## Why detached rather than inheriting
///
/// Callers are view models on the main actor. A plain `Task { }` inherits
/// the enclosing actor, which would put model generation or network I/O on
/// the main actor and freeze the UI for the duration. `Task.detached`
/// guarantees the work runs on the global executor regardless of who called.
nonisolated enum BoundedWork {

    /// Runs `operation`, giving up after `timeout`.
    ///
    /// - Parameters:
    ///   - timeout: how long the operation may take.
    ///   - timeoutError: produces the error to throw when the deadline wins.
    ///     A closure rather than a value so the caller's feature-specific
    ///     error type does not have to be `Sendable`.
    ///   - operation: the work to bound.
    /// - Returns: whatever `operation` returned, if it won the race.
    /// - Throws: `operation`'s own error if it failed first; `timeoutError()`
    ///   if the deadline elapsed first; `CancellationError` if the calling
    ///   task was cancelled first.
    static func run<T: Sendable>(
        timeout: Duration,
        timeoutError: @Sendable @escaping () -> any Error,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        // Cancelled before we even start: don't launch the model.
        try Task.checkCancellation()

        let outcome = SingleAssignmentOutcome<T>()

        let work = Task.detached(priority: .userInitiated) {
            do {
                outcome.settle(.success(try await operation()))
            } catch {
                outcome.settle(.failure(error))
            }
        }

        // `Task.sleep` throws on cancellation, which is how the timer exits
        // quietly once the operation has already won.
        let timer = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            outcome.settle(.failure(timeoutError()))
        }

        defer {
            work.cancel()
            timer.cancel()
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                outcome.attach(continuation)
            }
        } onCancel: {
            work.cancel()
            timer.cancel()
            // Resolves the box so the caller resumes now, rather than when
            // (or if) the cancelled operation notices.
            outcome.settle(.failure(CancellationError()))
        }
    }
}

/// The box the race resolves through: first writer wins, and the waiting
/// continuation is resumed exactly once.
///
/// `@unchecked Sendable` with an explicit lock rather than an `actor`,
/// because `settle` is called from `withTaskCancellationHandler`'s `onCancel`
/// - a synchronous, non-isolated context that cannot `await` an actor.
///
/// `nonisolated` because the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise put
/// this on the main actor - and the whole point is that the detached tasks
/// settle it from wherever they happen to be running.
nonisolated private final class SingleAssignmentOutcome<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, any Error>?
    private var continuation: CheckedContinuation<T, any Error>?
    private var hasResumed = false

    /// Registers the caller's continuation, resuming it straight away if the
    /// race was already decided (which happens when the calling task was
    /// cancelled before the body ran).
    func attach(_ continuation: CheckedContinuation<T, any Error>) {
        lock.lock()
        if let result, !hasResumed {
            hasResumed = true
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Records the first outcome and resumes the caller if it is already
    /// waiting. Later calls are ignored, so a losing task that finishes after
    /// the fact cannot resume a continuation twice.
    func settle(_ outcome: Result<T, any Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = outcome
        guard let continuation, !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: outcome)
    }
}
