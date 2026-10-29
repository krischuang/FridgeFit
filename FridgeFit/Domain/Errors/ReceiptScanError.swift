//
//  ReceiptScanError.swift
//  FridgeFit
//

import Foundation

/// Every way scanning a grocery receipt can fail. Messages are written for
/// the user - raw `FoundationModels` / `Vision` errors are logged by the
/// provider and mapped onto one of these before they reach the UI.
///
/// The three "nothing found" outcomes are deliberately separate, because
/// they need completely different advice: unreadable photo, readable but no
/// products, and products but no food.
nonisolated enum ReceiptScanError: LocalizedError, Equatable {
    /// Scan was triggered with nothing selected.
    case noImageSelected
    /// The picked photo couldn't be turned into something readable.
    case invalidImage
    /// OCR ran but came back with nothing - usually a blurry, dark or
    /// badly cropped photo.
    case noTextRecognized
    /// Text was read, but none of it looked like purchased products.
    case noProductLinesFound
    /// Products were found, but none were food worth putting in a pantry.
    case noFoodItemsFound
    /// Scanning isn't available - carries the reason so the UI can explain.
    case scanUnavailable(AppleIntelligenceAvailability)
    /// The on-device model ran but its answer couldn't be used.
    case interpretationFailed
    /// The model declined to answer, or the request tripped its safety
    /// guardrails.
    case requestNotAllowed
    /// The model was asked for too much at once, or is busy.
    case modelBusy
    /// Interpretation ran past the time FridgeFit is willing to wait.
    ///
    /// Enforced by FridgeFit, not reported by the SDK: a `respond` call on a
    /// device that claims a model it has no assets for never returns at all,
    /// so without an explicit bound this is an indefinite spinner rather
    /// than an error. See `AppleReceiptIngredientInterpreter` and
    /// `BoundedWork`.
    case timeout

    var errorDescription: String? {
        switch self {
        case .noImageSelected:
            return "Choose or take a photo of your receipt first."
        case .invalidImage:
            return "That photo couldn't be read. Try taking another one."
        case .noTextRecognized:
            return "No text could be read from that photo. Lay the receipt flat, fill the frame and make sure it's in focus."
        case .noProductLinesFound:
            return "That doesn't look like a grocery receipt. Try a photo that includes the purchased items."
        case .noFoodItemsFound:
            return "No food items were found on that receipt. Only groceries you can cook with are added to your pantry."
        case .scanUnavailable(let availability):
            return availability.unavailableExplanation
                ?? "Receipt scanning isn't available right now."
        case .interpretationFailed:
            return "FridgeFit couldn't make sense of that receipt. Try a clearer photo."
        case .requestNotAllowed:
            return "FridgeFit couldn't read that receipt. Try a different photo."
        case .modelBusy:
            return "Apple Intelligence is busy right now. Please try again in a moment."
        case .timeout:
            return "Reading that receipt took too long, so FridgeFit stopped. Try again, or add the items to your pantry by hand."
        }
    }
}
