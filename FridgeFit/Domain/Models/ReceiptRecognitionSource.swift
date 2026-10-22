//
//  ReceiptRecognitionSource.swift
//  FridgeFit
//

import Foundation

/// Where a receipt scan's result actually came from.
///
/// Exists so a replayed result can never be mistaken for a fresh one. A
/// cache hit returns the *same* structured outcome a real Apple
/// Intelligence run produced earlier, but it did not run the model again,
/// and the app is not allowed to imply that it did - see
/// `ReceiptRecognitionCacheStore` for why the cached result is genuine in
/// the first place.
///
/// This travels with `ReceiptScanOutcome` all the way to the view model so
/// the provenance survives the hand-off, rather than being inferred from
/// how fast the scan happened.
nonisolated enum ReceiptRecognitionSource: String, Codable, Equatable, CaseIterable {
    /// Vision read the photo and Apple's on-device language model
    /// interpreted it, just now.
    case appleIntelligence

    /// Replayed from a previously verified Apple Intelligence run over a
    /// pixel-identical photo. No model invocation took place.
    case verifiedCache

    /// Whether this result came from running the model during this scan.
    var didInvokeModel: Bool { self == .appleIntelligence }

    /// Short label for DEBUG diagnostics. Not user-facing.
    var diagnosticLabel: String { rawValue }
}
