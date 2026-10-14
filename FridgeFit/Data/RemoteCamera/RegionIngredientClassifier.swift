//
//  RegionIngredientClassifier.swift
//  FridgeFit
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import OSLog

/// Classifies the contents of each region the detector found.
///
/// The crop-based half of the hybrid: YOLO proposes rectangles, this cuts
/// them out and asks Apple Vision what is in each one. The result is a
/// classification that is *about those pixels*, which is the only form
/// `DetectionFusionService` will attach to a box.
///
/// Costs one Vision request per crop. `DetectionRegionCropper` caps the
/// number of crops, and the caller decides when to run this at all - it is
/// deliberately not wired into the live 3 FPS path, where it would multiply
/// per-frame work by the number of boxes for no visible benefit.
nonisolated struct RegionIngredientClassifier: Sendable {

    private let classifier: any IngredientClassifying
    private let cropper: DetectionRegionCropper
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "RegionClassifier")

    init(classifier: any IngredientClassifying, cropper: DetectionRegionCropper = DetectionRegionCropper()) {
        self.classifier = classifier
        self.cropper = cropper
    }

    /// Classifies each region of an upright image.
    ///
    /// What one pass over the regions produced.
    nonisolated struct Outcome: Sendable {
        /// Results keyed by region id. A region whose crop was too small, or
        /// whose classification failed, is simply absent - fusion treats that
        /// as "detector only", which is the honest outcome.
        let results: [UUID: ClassificationResult]
        /// How many crops were attempted.
        let attempted: Int
        /// The first real failure, if any.
        ///
        /// Counted and surfaced rather than only logged: a device where every
        /// crop fails should report that, not quietly behave like a device
        /// with nothing in frame.
        let failure: String?
        /// How many crops failed.
        let failureCount: Int

        static let empty = Outcome(results: [:], attempted: 0, failure: nil, failureCount: 0)
    }

    /// Classifies each region of an upright image.
    func classifyRegions<Region: DetectedRegion>(
        in image: CGImage,
        regions: [Region]
    ) -> Outcome {
        outcome(for: cropper.crops(from: image, regions: regions))
    }

    /// Classifies each region of a video frame, applying `orientation` once.
    func classifyRegions<Region: DetectedRegion>(
        in pixelBuffer: CVPixelBuffer,
        regions: [Region],
        orientation: CGImagePropertyOrientation
    ) -> Outcome {
        outcome(for: cropper.crops(from: pixelBuffer, regions: regions, orientation: orientation))
    }

    private func outcome<Region: DetectedRegion>(
        for crops: [DetectionRegionCropper.Crop<Region>]
    ) -> Outcome {
        // Nothing to attempt if the classifier cannot run at all. Skipping
        // here means an unsupported platform costs zero Vision requests
        // instead of one failure per box.
        guard classifier.capability.isAvailable else { return .empty }

        var output: [UUID: ClassificationResult] = [:]
        var firstFailure: String?
        var failureCount = 0

        for crop in crops {
            do {
                // The crop was already rotated upright when it was cut, so
                // it is classified `.up`. Passing the frame's orientation
                // again here would rotate it twice.
                output[crop.region.id] = try classifier.classify(crop.image, orientation: .up)
            } catch {
                failureCount += 1
                if firstFailure == nil {
                    firstFailure = (error as? VisionClassificationError)?.message
                        ?? error.localizedDescription
                }
                logger.error("Region classification failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        return Outcome(
            results: output, attempted: crops.count,
            failure: firstFailure, failureCount: failureCount
        )
    }
}
