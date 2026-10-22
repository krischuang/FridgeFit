//
//  ReceiptScanMetrics.swift
//  FridgeFit
//

import Foundation

/// Where the time went in one receipt scan.
///
/// The fast path makes a claim - that a prepared receipt reaches the review
/// screen in a second or two - and a claim like that is worth very little
/// without the numbers behind it. This records them at the points that
/// actually cost something, so the figure quoted for a demonstration is
/// measured on the device doing the demonstration rather than assumed from a
/// simulator.
///
/// Durations are optional because not every stage runs in every scan: a
/// cache miss has no lookup time worth reporting separately, and a scan with
/// no cache attached has neither.
nonisolated struct ReceiptScanMetrics: Equatable {
    let source: ReceiptRecognitionSource
    /// Canonicalising and hashing the pixels.
    let fingerprinting: Duration?
    /// Reading the store once the key is known.
    let cacheLookup: Duration?
    /// Everything `ScanReceiptUseCase.execute` did, end to end. On a hit
    /// this is the number that matters.
    let total: Duration

    var isCacheHit: Bool { source == .verifiedCache }

    /// Rendered as seconds to two places, which is the resolution anyone
    /// reading a demo timing actually cares about.
    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    var summary: String {
        var parts = ["source \(source.diagnosticLabel)"]
        if let fingerprinting {
            parts.append(String(format: "fingerprint %.3fs", Self.seconds(fingerprinting)))
        }
        if let cacheLookup {
            parts.append(String(format: "lookup %.3fs", Self.seconds(cacheLookup)))
        }
        parts.append(String(format: "total %.3fs", Self.seconds(total)))
        return parts.joined(separator: " · ")
    }
}

/// Receives a scan's timings.
///
/// A protocol rather than a direct `print` so a test can assert on real
/// measurements instead of scraping the console, and so recording stays
/// opt-in: `ScanReceiptUseCase` takes one only if a caller supplies it.
nonisolated protocol ReceiptScanMetricsRecording: AnyObject {
    func record(_ metrics: ReceiptScanMetrics)
}

/// Prints timings to the attached Xcode console in DEBUG, and does nothing
/// at all in Release.
///
/// Same reasoning as `ReceiptScanDiagnostics`: timings are cheap, but they
/// are tied to a scan of someone's shopping, so they do not go to the
/// unified log where a sysdiagnose would collect them later.
nonisolated final class LoggingReceiptScanMetricsRecorder: ReceiptScanMetricsRecording {
    init() {}

    func record(_ metrics: ReceiptScanMetrics) {
        #if DEBUG
        print("\n=== RECEIPT SCAN TIMING === \(metrics.summary)")
        #endif
    }
}

/// Keeps every sample in memory, for tests and for the preparation screen.
nonisolated final class InMemoryReceiptScanMetricsRecorder: ReceiptScanMetricsRecording {
    private(set) var samples: [ReceiptScanMetrics] = []

    init() {}

    var last: ReceiptScanMetrics? { samples.last }

    func record(_ metrics: ReceiptScanMetrics) {
        samples.append(metrics)
    }
}
