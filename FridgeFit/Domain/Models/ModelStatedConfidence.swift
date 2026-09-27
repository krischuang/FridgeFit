//
//  ModelStatedConfidence.swift
//  FridgeFit
//

import Foundation

/// How sure the on-device model *said* it was about a detection.
///
/// Deliberately named "model stated": this is the model's own coarse
/// self-report, not a calibrated probability, so it must never be rendered
/// as a percentage or used to decide anything factual. Pantry contents are
/// decided by the pantry, never by this.
enum ModelStatedConfidence: String, Codable, CaseIterable, Identifiable, Equatable {
    case high
    case medium
    case low

    var id: String { rawValue }

    /// Shown next to a detection, e.g. "High confidence".
    var label: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        }
    }

    /// Ordering for presentation - most trustworthy detections first.
    var sortPriority: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
