//
//  GatedPantryRepository.swift
//  FridgeFitTests
//

import Foundation
@testable import FridgeFit

/// `PantryRepository` whose `fetchAll()` parks until the test releases it,
/// with the pantry that particular call should see.
///
/// Exists so overlapping Discover re-checks can be finished in the *opposite*
/// order to the one they started in, deterministically: `waitForParkedFetches`
/// is how the test knows a call has arrived, and `release(call:with:)` decides
/// which one finishes first. No sleeps, so nothing here depends on timing.
///
/// Only `fetchAll()` is driven - reading the pantry is the single suspension
/// point in both `execute` and `reevaluate`, so it is the only place two of
/// them can interleave.
@MainActor
final class GatedPantryRepository: PantryRepository {
    private var parked: [Int: CheckedContinuation<[PantryItem], Never>] = [:]
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var enteredCount = 0

    /// How many times `fetchAll()` has been entered - the assertion that a
    /// local re-check spends no extra pantry read, and no API quota.
    var fetchAllCount: Int { enteredCount }

    func fetchAll() async throws -> [PantryItem] {
        enteredCount += 1
        let call = enteredCount
        return await withCheckedContinuation { continuation in
            parked[call] = continuation
            let waiters = arrivalWaiters
            arrivalWaiters = []
            for waiter in waiters { waiter.resume() }
        }
    }

    /// Suspends until at least `count` `fetchAll()` calls are parked.
    func waitForParkedFetches(_ count: Int) async {
        while parked.count < count {
            await withCheckedContinuation { arrivalWaiters.append($0) }
        }
    }

    /// Completes the `call`-th `fetchAll()` (1-based, in arrival order) with
    /// `items`, leaving any other parked call still waiting.
    func release(call: Int, with items: [PantryItem]) {
        parked.removeValue(forKey: call)?.resume(returning: items)
    }

    // Unused: these tests only read the pantry.
    func fetch(id: UUID) async throws -> PantryItem? { nil }
    func fetchExpiring(before date: Date) async throws -> [PantryItem] { [] }
    func add(_ item: PantryItem) async throws {}
    func update(_ item: PantryItem) async throws {}
    func remove(id: UUID) async throws {}
}
