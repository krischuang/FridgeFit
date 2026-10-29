//
//  BoundedWorkTests.swift
//  FridgeFitTests
//
//  The deadline primitive every on-device model call in FridgeFit now runs
//  under.
//
//  ## The test that matters
//
//  `test_run_operationIgnoresCancellation_stillThrowsTimeoutPromptly` is the
//  regression test for the bug that motivated this type. The previous
//  implementation raced the operation against a sleeping sibling inside
//  `withThrowingTaskGroup`. That passes a test whose slow operation is
//  `Task.sleep`, because `Task.sleep` throws on cancellation and lets the
//  group's scope close. It does **not** survive an operation that ignores
//  cancellation: a task group awaits its remaining children when the body
//  returns, so the caller stayed suspended until the operation it had given
//  up on finished by itself - which, for `LanguageModelSession.respond` on a
//  device that reports a model it has no assets for, is never.
//
//  `neverFinishes()` below is that operation. It parks on a continuation
//  nobody resumes, which is not a cancellable suspension point, so no amount
//  of `cancel()` will end it. Every timeout test here uses it rather than
//  `Task.sleep`, so passing them requires the unstructured race and not just
//  a well-behaved child.
//

import XCTest
@testable import FridgeFit

final class BoundedWorkTests: XCTestCase {

    private struct Deadline: Error, Equatable {}
    private struct Boom: Error, Equatable {}

    /// How long a test is willing to wait for a bound of `timeout` to be
    /// honoured. Generous enough not to be flaky on a loaded CI machine,
    /// still far short of "it hung".
    private static let slack: Duration = .seconds(5)

    /// An operation that never completes **and ignores cancellation**, the
    /// way a `respond` call does on a device with no model assets.
    ///
    /// `withUnsafeContinuation` is deliberate: unlike `Task.sleep` it does
    /// not throw on cancellation, and unlike `withCheckedContinuation` it
    /// emits no "continuation misuse" diagnostic for never being resumed -
    /// which is the whole point, because this task is expected to outlive
    /// the call that abandoned it.
    private static func neverFinishes() async {
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
    }

    // MARK: - Happy path

    func test_run_operationFinishesInTime_returnsItsValue() async throws {
        let value = try await BoundedWork.run(
            timeout: .seconds(30),
            timeoutError: { Deadline() },
            operation: { 42 }
        )
        XCTAssertEqual(value, 42)
    }

    /// A generation that fails for its own reason must surface that reason.
    /// Reporting a timeout instead would send the user to retry something
    /// that failed for a different, possibly permanent, cause.
    func test_run_operationThrows_propagatesThatErrorNotTheDeadline() async {
        do {
            let _: Int = try await BoundedWork.run(
                timeout: .seconds(30),
                timeoutError: { Deadline() },
                operation: { throw Boom() }
            )
            XCTFail("Expected Boom")
        } catch is Boom {
            // Expected.
        } catch {
            XCTFail("Expected Boom, got \(error)")
        }
    }

    // MARK: - The deadline, against an uncancellable operation

    func test_run_operationIgnoresCancellation_stillThrowsTimeoutPromptly() async {
        let started = ContinuousClock.now

        do {
            let _: Int = try await BoundedWork.run(
                timeout: .milliseconds(50),
                timeoutError: { Deadline() },
                operation: {
                    await Self.neverFinishes()
                    return 1
                }
            )
            XCTFail("Expected the deadline error")
        } catch is Deadline {
            let elapsed = ContinuousClock.now - started
            XCTAssertLessThan(
                elapsed,
                Self.slack,
                "The deadline must not wait for an operation that ignores cancellation"
            )
        } catch {
            XCTFail("Expected Deadline, got \(error)")
        }
    }

    /// Cancelling the caller has to end the wait now, not at the deadline and
    /// not when the abandoned operation notices (it never will).
    func test_run_callerCancelled_throwsCancellationPromptly_evenWithUncancellableOperation() async throws {
        let started = ContinuousClock.now

        let task = Task {
            try await BoundedWork.run(
                timeout: .seconds(120),
                timeoutError: { Deadline() },
                operation: {
                    await Self.neverFinishes()
                    return 1
                }
            )
        }

        // Let the race actually start, so this exercises cancelling a
        // running operation rather than a pre-cancelled task.
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let elapsed = ContinuousClock.now - started
            XCTAssertLessThan(elapsed, Self.slack, "Cancellation must not wait for the deadline")
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    /// A caller that was already cancelled must not start the model at all.
    func test_run_alreadyCancelled_doesNotInvokeTheOperation() async {
        let didRun = Flag()

        let task = Task {
            try await BoundedWork.run(
                timeout: .seconds(30),
                timeoutError: { Deadline() },
                operation: {
                    didRun.set()
                    return 1
                }
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(didRun.isSet, "A cancelled request must not spend a generation")
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - Resume-once safety

    /// The loser of the race finishing afterwards must not resume the
    /// caller's continuation a second time - that traps, rather than failing
    /// politely, so it is worth pinning down.
    func test_run_operationFinishesAfterTheDeadline_doesNotCrashOrChangeTheOutcome() async throws {
        let gate = Gate()

        do {
            let _: Int = try await BoundedWork.run(
                timeout: .milliseconds(50),
                timeoutError: { Deadline() },
                operation: {
                    await gate.wait()
                    return 99
                }
            )
            XCTFail("Expected the deadline error")
        } catch is Deadline {
            // Now let the abandoned operation complete. It tries to settle an
            // already-settled outcome; nothing may happen as a result.
            gate.open()
            try await Task.sleep(for: .milliseconds(100))
        } catch {
            XCTFail("Expected Deadline, got \(error)")
        }
    }

    /// Two rapid requests must not interfere - each gets its own box.
    func test_run_concurrentRequests_areIndependent() async throws {
        async let fast = BoundedWork.run(
            timeout: .seconds(30),
            timeoutError: { Deadline() },
            operation: { "fast" }
        )
        async let slow: String = BoundedWork.run(
            timeout: .milliseconds(50),
            timeoutError: { Deadline() },
            operation: {
                await Self.neverFinishes()
                return "slow"
            }
        )

        let fastValue = try await fast
        XCTAssertEqual(fastValue, "fast")

        do {
            _ = try await slow
            XCTFail("Expected the deadline error")
        } catch is Deadline {
            // Expected.
        }
    }
}

// MARK: - Test helpers

/// A set-once flag readable across isolation domains.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// A one-shot gate a test can hold an operation behind and then release.
/// Unlike `Task.sleep` it is not cancellable, which is what makes it useful
/// here.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [UnsafeContinuation<Void, Never>] = []

    func wait() async {
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending { waiter.resume() }
    }
}
