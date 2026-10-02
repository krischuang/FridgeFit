//
//  VisionReceiptTextRecognizer.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Vision

/// `ReceiptTextRecognizer` backed by Apple's Vision text recogniser.
///
/// OCR only. No image classification of any kind runs here - a receipt is
/// read, not looked at, and Vision's visual taxonomy has nothing useful to
/// say about a piece of paper.
///
/// ## Why the settings are what they are
///
/// - `.accurate`, because a receipt is read once and the whole feature
///   depends on getting `CHKN BREAST 500G` character-perfect. The extra
///   hundreds of milliseconds are invisible next to the model call that
///   follows.
/// - `usesLanguageCorrection = false`. This is the one that matters and it
///   is the opposite of what prose wants. Language correction rewrites
///   unrecognised strings towards real dictionary words, and a receipt is
///   mostly *not* words: `CHKN`, `CAPS`, `MUSH`, `ATL`, SKUs and store
///   codes. Correction rewrites `CHKN` towards a real word and the
///   interpreter
///   then faithfully interprets the wrong product. Raw characters are worth
///   more than plausible ones here.
/// - `minimumTextHeightFraction` is lowered, because a long receipt
///   photographed whole makes each line a very small fraction of the frame
///   and the default silently skips them.
/// - No downsampling, no recompression. Receipt text is small and
///   thermal-printed; shrinking the image is the fastest way to lose the
///   bottom half of a receipt. The full-resolution `CGImage` goes straight
///   to Vision.
///
/// ## Why observations get merged into rows
///
/// Receipts are laid out in columns: the description is left-aligned and
/// the price is right-aligned, separated by a wide gap. Vision reports
/// those as two separate observations even though a human reads them as one
/// line. Emitting them separately would hand the parser a bare `8.50` with
/// no product attached, so observations sharing a horizontal band are
/// stitched back into a single line, left to right, before anything else
/// sees them.
///
/// Nothing leaves the device.
struct VisionReceiptTextRecognizer: ReceiptTextRecognizer {
    /// Lines Vision was less sure about than this are dropped. Deliberately
    /// permissive: a misread product line can still be corrected by the
    /// user, but a dropped one is invisible to them.
    private let minimumLineConfidence: Float
    /// Two observations belong to the same receipt row when their vertical
    /// centres are closer than this multiple of their height.
    private let rowGroupingTolerance: CGFloat
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "VisionReceiptTextRecognizer")

    init(minimumLineConfidence: Float = 0.3, rowGroupingTolerance: CGFloat = 0.6) {
        self.minimumLineConfidence = minimumLineConfidence
        self.rowGroupingTolerance = rowGroupingTolerance
    }

    func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> RecognizedReceiptText {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeightFraction = 0.008
        request.recognitionLanguages = Self.recognitionLanguages(supportedBy: request)

        let observations: [RecognizedTextObservation]
        do {
            observations = try await request.perform(on: image, orientation: orientation)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Receipt OCR failed: \(error.localizedDescription, privacy: .public)")
            throw ReceiptScanError.invalidImage
        }

        return RecognizedReceiptText(lines: Self.lines(from: observations, tolerance: rowGroupingTolerance, minimumConfidence: minimumLineConfidence))
    }

    /// Prefers Australian English, then generic English, falling back to
    /// whatever the device actually supports.
    ///
    /// Asked of the request rather than hardcoded: forcing an unsupported
    /// language identifier makes Vision throw, and the supported set differs
    /// by device and OS.
    private static func recognitionLanguages(supportedBy request: RecognizeTextRequest) -> [Locale.Language] {
        let supported = request.supportedRecognitionLanguages
        let preferred = ["en-AU", "en-GB", "en-US", "en"].map(Locale.Language.init(identifier:))
        let available = preferred.filter { candidate in
            supported.contains { $0.minimalIdentifier == candidate.minimalIdentifier }
        }
        return available.isEmpty ? supported : available
    }

    // MARK: - Row stitching

    /// Groups observations into receipt rows and renders each as one line.
    ///
    /// Vision's normalized coordinates put the origin at the bottom left, so
    /// a *larger* y is higher up the page - hence the descending sort to get
    /// reading order.
    private static func lines(
        from observations: [RecognizedTextObservation],
        tolerance: CGFloat,
        minimumConfidence: Float
    ) -> [RecognizedReceiptLine] {
        let fragments = observations.compactMap(Fragment.init(observation:))
        guard !fragments.isEmpty else { return [] }

        let topDown = fragments.sorted { $0.frame.midY > $1.frame.midY }

        var rows: [[Fragment]] = []
        for fragment in topDown {
            guard var row = rows.last else {
                rows.append([fragment])
                continue
            }
            // Compare against the row's current vertical centre and height,
            // so a row of mixed-size text still groups sensibly.
            let rowMidY = row.map(\.frame.midY).reduce(0, +) / CGFloat(row.count)
            let rowHeight = row.map(\.frame.height).reduce(0, +) / CGFloat(row.count)
            let limit = max(rowHeight, fragment.frame.height) * tolerance

            if abs(rowMidY - fragment.frame.midY) <= limit {
                row.append(fragment)
                rows[rows.count - 1] = row
            } else {
                rows.append([fragment])
            }
        }

        return rows.enumerated().compactMap { index, row in
            let ordered = row.sorted { $0.frame.minX < $1.frame.minX }
            let text = ordered
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            // The least confident fragment sets the row's confidence - a
            // row is only as trustworthy as its worst-read part.
            let confidence = ordered.map(\.confidence).min() ?? 0
            guard confidence >= minimumConfidence else { return nil }

            return RecognizedReceiptLine(text: text, confidence: confidence, order: index)
        }
    }

    /// One Vision observation reduced to the three things row stitching
    /// needs, so the geometry code doesn't carry Vision types around.
    private struct Fragment {
        let text: String
        let confidence: Float
        let frame: CGRect

        init?(observation: RecognizedTextObservation) {
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            self.text = text
            self.confidence = candidate.confidence
            self.frame = observation.boundingBox.cgRect
        }
    }
}
