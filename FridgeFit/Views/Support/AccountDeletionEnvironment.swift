//
//  AccountDeletionEnvironment.swift
//  FridgeFit
//

import SwiftUI

/// Builds the account-deletion use case on demand.
///
/// A factory rather than the use case itself because the use case closes over
/// a `ModelContext`, and building one per app launch and holding it for the
/// lifetime of the environment would keep a context alive for a screen almost
/// nobody opens. The sheet asks for one when it appears.
nonisolated struct DeleteAccountUseCaseFactory: Sendable {
    private let build: @MainActor @Sendable () -> DeleteAccountUseCase

    init(_ build: @MainActor @Sendable @escaping () -> DeleteAccountUseCase) {
        self.build = build
    }

    @MainActor
    func make() -> DeleteAccountUseCase { build() }
}

/// Reaches Profile → Settings without giving that screen a Firebase or
/// SwiftData dependency of its own. Exactly the shape of
/// `\.fundsEnvironment` and `\.pantryRepository`, for the same reason: the
/// composition root owns the decision, the screen only consumes it.
///
/// `nil` in previews and tests, where the Delete Account section is simply
/// not offered rather than offered and then unable to work.
private struct DeleteAccountUseCaseFactoryKey: EnvironmentKey {
    static let defaultValue: DeleteAccountUseCaseFactory? = nil
}

extension EnvironmentValues {
    var deleteAccountUseCaseFactory: DeleteAccountUseCaseFactory? {
        get { self[DeleteAccountUseCaseFactoryKey.self] }
        set { self[DeleteAccountUseCaseFactoryKey.self] = newValue }
    }
}

/// Which backend `AppDependencies` actually chose.
///
/// Passed down so Settings can *state* where the user's data is, which is the
/// one legitimate reason a view may know this - `PersistenceConfiguration`'s
/// rule is that no view may *read the configuration to branch on it*, and
/// nothing here does. The value travels as data, from the one object that
/// resolved it.
private struct PersistenceBackendKey: EnvironmentKey {
    static let defaultValue: PersistenceBackend? = nil
}

extension EnvironmentValues {
    var persistenceBackend: PersistenceBackend? {
        get { self[PersistenceBackendKey.self] }
        set { self[PersistenceBackendKey.self] = newValue }
    }
}
