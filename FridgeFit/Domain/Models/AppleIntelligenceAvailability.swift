//
//  AppleIntelligenceAvailability.swift
//  FridgeFit
//

import Foundation

/// Whether an on-device Apple Intelligence feature can run right now, in
/// FridgeFit's own terms.
///
/// Shared by the two features that need the system language model -
/// receipt scanning and recipe suggestions - because the reasons it can't
/// run are a property of the device and the user's settings, not of the
/// feature asking.
///
/// Providers map their own SDK states onto this
/// (`SystemLanguageModel.Availability`), so nothing above the data layer
/// has to know which framework is behind a feature or import it. Apple
/// Intelligence being unavailable never affects pantry, recipes browsing or
/// Firebase; only the features that need the model change.
///
/// The explanations are written to be true of any of those features, which
/// is why they say "this feature" rather than naming one. The callers that
/// want specific wording - `ReceiptScanError`, `RecipeSuggestionError` -
/// supply their own.
///
/// `nonisolated` because the error types carry this as an associated
/// value, and an `Error` conformance can't be actor-isolated - the target
/// compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum AppleIntelligenceAvailability: Equatable {
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

    /// Whether the feature can run. Named for the scan that was the first
    /// caller; reads correctly for recipe suggestions too.
    var canScan: Bool { self == .available }

    /// Title for the unavailable state shown in place of the feature.
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
            return "Unavailable Right Now"
        }
    }

    /// User-facing explanation. Never mentions framework or error details.
    var unavailableExplanation: String? {
        switch self {
        case .available:
            return nil
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings to use this feature. You can still add ingredients to your pantry by hand."
        case .deviceNotSupported:
            return "This device can't run this feature on-device. You can still add ingredients to your pantry by hand."
        case .modelNotReady:
            return "Apple Intelligence is still getting set up on this device. Try again in a few minutes, or add ingredients by hand."
        case .unavailableForUnknownReason:
            return "This feature isn't available right now. You can still add ingredients to your pantry by hand."
        }
    }
}
