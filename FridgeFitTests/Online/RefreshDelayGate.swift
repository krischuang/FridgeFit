//
//  RefreshDelayGate.swift
//  FridgeFitTests
//

import Foundation

/// Stands in for the view model's debounce window, held open by the test
/// instead of by a clock.
///
/// A zero-length delay would not do: the edits in a burst are separated by
/// `await`s (writing to the pantry), so each queued re-check would get to run
/// before the next edit arrived and nothing would coalesce. A real sleep
/// would make the tests timing-dependent. Parking every re-check until the
/// test says otherwise reproduces the burst exactly, and deterministically.
actor RefreshDelayGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Passed to the view model as its `pantryRefreshDelay`.
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Lets everything parked - and anything arriving while open - through.
    /// Call once the burst being tested has been queued.
    func open() {
        isOpen = true
        let parked = waiters
        waiters = []
        for waiter in parked { waiter.resume() }
    }

    /// Re-arms the gate, so the next burst parks again.
    func close() {
        isOpen = false
    }
}
