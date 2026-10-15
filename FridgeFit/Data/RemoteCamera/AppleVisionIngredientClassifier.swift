//
//  AppleVisionIngredientClassifier.swift
//  FridgeFit
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import OSLog
import UIKit
import Vision

/// Ingredient classification using Apple's built-in image classifier.
///
/// `VNClassifyImageRequest` ships with the OS: no model in the bundle, no
/// download, no Apple Intelligence requirement, no licence obligation, and
/// nothing leaves the device. Revision 2 knows 1,303 classes, of which
/// roughly ninety are ingredients FridgeFit cares about
/// (`VisionIngredientMap`).
///
/// On the 11-image evaluation set this scored better than the 24 MB
/// YOLO-World model it sits beside - see
/// `docs/hybrid-ingredient-recognition.md`. It does **not** replace that
/// model, because it produces no bounding boxes at all.
///
/// ## Filtering
///
/// Apple's taxonomy is hierarchical and multi-label, so a flat confidence cut
/// across it is the wrong instrument: `food` and `fruit` arrive at 1.00 on a
/// fruit bowl and mean nothing. Two filters are applied, in order:
///
/// 1. `hasMinimumRecall(0, forPrecision:)` - Apple's own per-identifier
///    calibration curve, which is the documented way to filter these results.
/// 2. The three-way split in `VisionIngredientMap`, which discards hypernyms
///    and scene labels entirely.
///
/// ## Thread safety
///
/// Not safe for concurrent use: `VNImageRequestHandler` is per-call, but the
/// request object holds its results. Callers serialise, exactly as
/// `RemoteVideoFrameTap` does for the detector.
nonisolated final class AppleVisionIngredientClassifier: IngredientClassifying, @unchecked Sendable {

    nonisolated struct Configuration: Sendable {
        /// Identifiers below this are dropped.
        ///
        /// 0.30 is where the evaluation set put the knee: 42.1% recall at
        /// 72.7% precision, against 55.3%/44.7% at 0.10 and 34.2%/76.5% at
        /// 0.40. Measured with the Python harness over PIL-decoded images;
        /// `AppleVisionClassifierEvaluationTests` re-measures it through
        /// these Swift APIs.
        var confidenceThreshold: Float = 0.30
        /// Apple's calibrated precision floor for an identifier to be
        /// considered at all.
        var minimumPrecision: Float = 0.5
        /// Cap on ingredients returned, highest confidence first.
        var maximumIngredients: Int = 12

        static let `default` = Configuration()
    }

    private let configuration: Configuration
    let map: VisionIngredientMap
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "VisionClassifier")

    /// Whether `VNClassifyImageRequest` can run in this process.
    ///
    /// Probed once, lazily, with a 32x32 image - cheap, and far more reliable
    /// than reasoning about the platform. `#if targetEnvironment(simulator)`
    /// alone would be a guess that stays wrong forever if a future simulator
    /// gains support; the probe notices. The compile-time check is used only
    /// to *classify* a failure, not to predict one.
    let capability: ClassificationCapability

    init(map: VisionIngredientMap, configuration: Configuration = .default) {
        self.map = map
        self.configuration = configuration
        let started = Date()
        self.capability = Self.probeCapability()
        Logger(subsystem: "com.Fridge.FridgeFit", category: "VisionClassifier").info("""
        CAPABILITY probe=\(String(describing: self.capability), privacy: .public) \
        probeMs=\(Int(Date().timeIntervalSince(started) * 1000)) \
        vocabulary=\(map.entries.count)
        """)
    }

    /// For tests that need to drive a specific capability without the probe.
    init(
        map: VisionIngredientMap,
        configuration: Configuration = .default,
        capability: ClassificationCapability
    ) {
        self.map = map
        self.configuration = configuration
        self.capability = capability
    }

    /// Runs one tiny classification to find out whether the API works here.
    static func probeCapability() -> ClassificationCapability {
        let side = 32
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .failed("could not build a probe image")
        }
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let probe = context.makeImage() else {
            return .failed("could not build a probe image")
        }

        do {
            try VNImageRequestHandler(cgImage: probe, options: [:])
                .perform([VNClassifyImageRequest()])
            return .available
        } catch {
            let detail = error.localizedDescription
            #if targetEnvironment(simulator)
            // Expected: the simulator has no Espresso (Core ML inference)
            // context for Apple's built-in classifier.
            return .unavailableInSimulator(detail)
            #else
            // On real hardware this should work. Anything else is a fault and
            // must be reported, not quietly treated as "no classifier".
            return .failed(detail)
            #endif
        }
    }

    /// Loads the bundled identifier map and builds a classifier.
    convenience init(bundle: Bundle = .main, configuration: Configuration = .default) throws {
        self.init(map: try VisionIngredientMap.load(in: bundle), configuration: configuration)
    }

    // MARK: - Classification

    func classify(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> ClassificationResult {
        try perform(VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]))
    }

    func classify(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> ClassificationResult {
        try perform(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]))
    }

    /// Convenience for the captured-photo path, which holds `UIImage`s.
    ///
    /// Uses the image's own `imageOrientation` so a photo captured in
    /// landscape is classified upright rather than on its side.
    func classify(_ image: UIImage) throws -> ClassificationResult {
        guard let cgImage = image.cgImage else {
            throw VisionClassificationError.unreadableImage
        }
        return try classify(cgImage, orientation: image.cgImagePropertyOrientation)
    }

    private func perform(_ handler: VNImageRequestHandler) throws -> ClassificationResult {
        // Refuse rather than return empty. An empty result means "looked and
        // found nothing", which is a claim about the image; this is a claim
        // about the platform. Conflating them would let the UI report "no
        // ingredients" for a photo nothing ever examined.
        guard capability.isAvailable else {
            throw VisionClassificationError.classifierUnavailable(capability)
        }

        let request = VNClassifyImageRequest()
        do {
            try handler.perform([request])
        } catch {
            throw VisionClassificationError.requestFailed(reason: error.localizedDescription)
        }

        guard let observations = request.results else { return .empty }

        var ingredients: [ClassifiedIngredient] = []
        var rejected: [String] = []
        var seen = Set<String>()

        for observation in observations
        where observation.hasMinimumRecall(0, forPrecision: VNConfidence(configuration.minimumPrecision)) {
            guard observation.confidence >= VNConfidence(configuration.confidenceThreshold) else { continue }

            switch map.kind(of: observation.identifier) {
            case .ingredient(let entry):
                // Several identifiers can share one ingredient ("melon" and
                // "cantaloupe"). Keep the most confident; observations
                // arrive sorted, so the first wins.
                guard seen.insert(entry.ingredient).inserted else { continue }
                ingredients.append(ClassifiedIngredient(
                    ingredientId: entry.ingredient,
                    displayName: entry.display,
                    category: entry.category,
                    confidence: Float(observation.confidence),
                    rawIdentifier: entry.identifier,
                    requiresReview: entry.requiresReview
                ))
            case .wrongFood:
                rejected.append(observation.identifier)
            case .ignored:
                continue
            }
        }

        return ClassificationResult(
            ingredients: Array(
                ingredients.sorted { $0.confidence > $1.confidence }
                    .prefix(configuration.maximumIngredients)
            ),
            rejectedFoodClaims: rejected
        )
    }
}

// MARK: - Errors

nonisolated enum VisionClassificationError: LocalizedError, Equatable {
    case unreadableImage
    case requestFailed(reason: String)
    /// Classification was not attempted because it cannot run here.
    case classifierUnavailable(ClassificationCapability)

    var message: String {
        switch self {
        case .unreadableImage:
            return "That image could not be read for classification."
        case .requestFailed(let reason):
            return "Image classification failed: \(reason)"
        case .classifierUnavailable(let capability):
            return capability.userMessage ?? "Image classification is unavailable."
        }
    }

    /// Whether this is a platform limitation rather than a fault - the
    /// difference between degrading quietly and reporting a problem.
    var isExpectedLimitation: Bool {
        if case .classifierUnavailable(let capability) = self {
            return capability.isExpectedLimitation
        }
        return false
    }

    var errorDescription: String? { message }
}

// MARK: - Orientation

nonisolated extension UIImage {
    /// `UIImage.Orientation` expressed the way Vision wants it.
    ///
    /// The two enumerations are not interchangeable - their raw values differ
    /// - and passing one for the other silently rotates every result.
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
