//
//  IngredientRecognitionAvailability.swift
//  FridgeFit
//

import Foundation

/// Whether fridge scanning can run right now, in FridgeFit's own terms.
///
/// Providers map their own SDK states onto this - `SystemLanguageModel`'s
/// `Availability` in `AppleIngredientRecognitionService`'s case - so nothing
/// above the data layer has to know which framework is behind the scan or
/// import it. Scanning being unavailable never affects pantry, recipes or
/// Firebase; only the scan entry point changes.
/// `nonisolated` because `IngredientRecognitionError` carries this as an
/// associated value, and an `Error` conformance can't be actor-isolated -
/// the target compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum IngredientRecognitionAvailability: Equatable {
    case available
    /// The device supports Apple Intelligence, but the user hasn't turned
    /// it on in Settings.
    case appleIntelligenceNotEnabled
    /// Hardware that can't run the on-device model at all.
    case deviceNotSupported
    /// Enabled, but the model assets are still downloading or the device
    /// is otherwise not ready yet - worth retrying later.
    case modelNotReady
    /// The provider reported a state this version of FridgeFit doesn't
    /// recognise. Treated as unavailable rather than assumed to work.
    case unavailableForUnknownReason

    var canScan: Bool { self == .available }

    /// Title for the unavailable state shown in place of the scanner.
    var unavailableTitle: String? {
        switch self {
        case .available:
            return nil
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence Is Off"
        case .deviceNotSupported:
            return "Not Supported on This Device"
        case .modelNotReady:
            return "Apple Intelligence Isn't Ready"
        case .unavailableForUnknownReason:
            return "Scanning Is Unavailable"
        }
    }

    /// User-facing explanation. Never mentions framework or error details.
    var unavailableExplanation: String? {
        switch self {
        case .available:
            return nil
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to scan your fridge. You can still add ingredients to your pantry by hand."
        case .deviceNotSupported:
            return "This device can't run on-device fridge scanning. You can still add ingredients to your pantry by hand."
        case .modelNotReady:
            return "Apple Intelligence is still getting set up on this device. Try scanning again in a few minutes, or add ingredients by hand."
        case .unavailableForUnknownReason:
            return "Fridge scanning isn't available right now. You can still add ingredients to your pantry by hand."
        }
    }
}
