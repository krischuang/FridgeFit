//
//  FundsEnvironmentKey.swift
//  FridgeFit
//

import SwiftUI

// lets screens outside the Budget tab (recipe detail) read FridgeFunds without
// threading it through every view's init. same trick as \.pantryRepository.
// nil means FridgeFunds isn't wired in (previews), and those screens just
// leave the cost bits out.
private struct FundsEnvironmentKey: EnvironmentKey {
    static let defaultValue: FundsEnvironment? = nil
}

extension EnvironmentValues {
    var fundsEnvironment: FundsEnvironment? {
        get { self[FundsEnvironmentKey.self] }
        set { self[FundsEnvironmentKey.self] = newValue }
    }
}
