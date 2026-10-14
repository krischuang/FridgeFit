//
//  SnapshotIngredientAnalyzer.swift
//  FridgeFit
//

import CoreGraphics
import CoreImage
import Foundation
import OSLog
import UIKit

/// Which recognisers actually ran, and what went wrong if anything did.
///
/// Carried on every analysis so the UI can distinguish three outcomes that
/// look identical from the results alone: the classifier ran and found
/// nothing, the classifier could not run here, and the classifier broke.
nonisolated struct ClassificationOutcome: Equatable, Sendable {
    let capability: ClassificationCapability
    /// A whole-image classification that was attempted and failed.
    let sceneFailure: String?
    let regionsAttempted: Int
    let regionFailures: Int
    let regionFailure: String?
    /// OCR is independent of the classifier and usually works where the
    /// classifier does not, so its failure is reported separately.
    let packagingFailure: String?

    static let available = ClassificationOutcome(
        capability: .available, sceneFailure: nil,
        regionsAttempted: 0, regionFailures: 0, regionFailure: nil,
        packagingFailure: nil
    )

    /// Whether these results came from the detector alone.
    ///
    /// True when the classifier could not run, or ran and failed. In either
    /// case nothing can be in the agreed tier, and the user is being shown
    /// one method's opinion rather than two.
    var isDetectorOnly: Bool {
        !capability.isAvailable || sceneFailure != nil
    }

    /// A real fault, as opposed to a known platform limitation. `nil` in the
    /// simulator, where the classifier being absent is expected.
    var faultMessage: String? {
        if case .failed(let reason) = capability {
            return "Apple Vision classification failed: \(reason)"
        }
        if let sceneFailure { return sceneFailure }
        if let regionFailure, regionFailures > 0 {
            return "\(regionFailures) of \(regionsAttempted) regions failed: \(regionFailure)"
        }
        return nil
    }

    /// The headline to show, whether a limitation or a fault.
    var userMessage: String? { faultMessage ?? capability.userMessage }
}

/// Everything the captured-photo analysis produced.
nonisolated struct SnapshotAnalysis: Equatable, Sendable {
    /// Identity of the captured photo this analysis describes.
    ///
    /// The UI refuses to show an analysis whose id does not match the photo
    /// currently on screen. Without it, a second capture arriving while the
    /// first is still being analysed would leave the previous photo's boxes
    /// drawn over the new image - the boxes would be real, just measured
    /// against different pixels.
    let snapshotId: UUID
    /// Which recognisers ran, and what failed. Lets the UI say "YOLO-only"
    /// rather than implying two methods agreed when only one ran.
    let classification: ClassificationOutcome
    /// Fused detector + region-classifier results, plus scene-level claims.
    let fused: FusedDetectionFrame
    /// Whole-image classification on its own, kept as a separately reported
    /// baseline rather than folded into the fused result.
    let fullImageBaseline: ClassificationResult
    /// Packaging text and any ingredient terms matched in it.
    let packaging: PackagedFoodReading
    /// Wall-clock seconds the analysis took, for the diagnostics row.
    let duration: TimeInterval

    /// `classification` defaults to fully available so existing call sites
    /// and fixtures describe the normal case without restating it; the
    /// analyzer always passes what actually happened.
    init(
        snapshotId: UUID,
        classification: ClassificationOutcome = .available,
        fused: FusedDetectionFrame,
        fullImageBaseline: ClassificationResult,
        packaging: PackagedFoodReading,
        duration: TimeInterval
    ) {
        self.snapshotId = snapshotId
        self.classification = classification
        self.fused = fused
        self.fullImageBaseline = fullImageBaseline
        self.packaging = packaging
        self.duration = duration
    }

    static let empty = SnapshotAnalysis(
        snapshotId: UUID(), classification: .available, fused: .empty,
        fullImageBaseline: .empty, packaging: .empty, duration: 0
    )

    var isEmpty: Bool { fused.isEmpty && packaging.matches.isEmpty }

    /// Candidates for a future review sheet: fused claims first, then
    /// packaging matches that nothing else already named.
    ///
    /// Nothing in this list is confirmed, and nothing here writes to the
    /// Pantry. That step is the user's, and it is not implemented.
    var reviewCandidates: [FusedIngredient] {
        let claimed = Set(fused.all.map(\.ingredientId))
        let fromPackaging = packaging.matches
            .filter { !claimed.contains($0.ingredientId) }
            .map { match in
                FusedIngredient(
                    ingredientId: match.ingredientId,
                    displayName: match.displayName,
                    category: match.category,
                    tier: .singleSource,
                    sources: .packagingText,
                    boundingBox: nil,
                    reviewReason: .lowConfidence,
                    // Packaging text is evidence about a product, never a
                    // verified ingredient identity, so an OCR candidate is
                    // never preselected regardless of how clean the read was.
                    assertsIngredient: match.certainty == .likely
                )
            }
        return fused.all + fromPackaging
    }
}

/// Runs the full hybrid pipeline over one captured photo.
///
/// ## Why the captured photo and not the live stream
///
/// The live path stays exactly as it was: YOLO at 3 FPS, one inference in
/// flight, boxes drawn as they arrive. Classification and OCR are added
/// *here* instead, because:
///
/// - whole-image classification produces no boxes, so running it per frame
///   would cost work with nothing to draw;
/// - region classification costs one Vision request per box, which multiplies
///   per-frame work by the number of detections;
/// - OCR took 20-400 ms per image in measurement, far outside a 3 FPS budget.
///
/// Running all of it once, on a full-resolution still, off the main actor,
/// gets the accuracy without touching live video responsiveness.
///
/// Nothing here writes to the Pantry.
nonisolated struct SnapshotIngredientAnalyzer: Sendable {

    private let detector: YOLOFoodDetectionService
    private let normalizer: IngredientNormalizer
    private let source: DetectionSource
    private let classifier: AppleVisionIngredientClassifier
    private let regionClassifier: RegionIngredientClassifier
    private let textReader: PackagedFoodTextReader
    private let fusion: DetectionFusionService
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "SnapshotAnalysis")

    init(
        detector: YOLOFoodDetectionService,
        normalizer: IngredientNormalizer,
        source: DetectionSource,
        classifier: AppleVisionIngredientClassifier,
        fusion: DetectionFusionService = DetectionFusionService(),
        cropper: DetectionRegionCropper = DetectionRegionCropper()
    ) {
        self.detector = detector
        self.normalizer = normalizer
        self.source = source
        self.classifier = classifier
        self.regionClassifier = RegionIngredientClassifier(classifier: classifier, cropper: cropper)
        self.textReader = PackagedFoodTextReader(taxonomy: normalizer.taxonomy)
        self.fusion = fusion
    }

    /// Builds an analyzer from an already-resolved detector.
    ///
    /// Returns `nil` when the resolved detector is not a
    /// `YOLOFoodDetectionService` - a test double, for instance - since there
    /// is no still-image path to call on an arbitrary `FrameDetecting`.
    init?(
        resolved: ResolvedDetector,
        classifier: AppleVisionIngredientClassifier,
        fusion: DetectionFusionService = DetectionFusionService()
    ) {
        guard let yolo = resolved.detector as? YOLOFoodDetectionService else { return nil }
        self.init(
            detector: yolo,
            normalizer: resolved.normalizer,
            source: resolved.source,
            classifier: classifier,
            fusion: fusion
        )
    }

    /// Analyses one photo. Blocking; call it off the main actor.
    ///
    /// - Parameter snapshotId: identity of the photo, carried into the result
    ///   so the caller can tell whether it still describes what is on screen.
    func analyze(_ image: UIImage, snapshotId: UUID = UUID()) throws -> SnapshotAnalysis {
        guard let cgImage = image.cgImage else {
            throw VisionClassificationError.unreadableImage
        }
        return try analyze(
            cgImage, orientation: image.cgImagePropertyOrientation, snapshotId: snapshotId
        )
    }

    func analyze(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        snapshotId: UUID = UUID()
    ) throws -> SnapshotAnalysis {
        let started = Date()

        // 1. Detector: where things are.
        let detectStarted = Date()
        let raw: DetectionFrame
        do {
            raw = try detector.detect(in: image, orientation: orientation)
        } catch {
            // The one stage with no fallback: without boxes there is nothing
            // to crop, nothing to draw, and no analysis to return.
            logger.error("""
            ANALYSIS stage=detect result=failed \
            error=\((error as? YOLODetectionError)?.message ?? error.localizedDescription, privacy: .public)
            """)
            throw error
        }
        let detectMs = Date().timeIntervalSince(detectStarted) * 1000
        let detections = normalizer.normalize(raw, source: source)

        // 2. Region classification: what is inside each of those boxes.
        //    Cropping the *normalised* list means decoys and sub-threshold
        //    boxes never cost a Vision request.
        let upright = uprightImage(image, orientation: orientation) ?? image
        let cropStarted = Date()
        let regionOutcome = regionClassifier.classifyRegions(
            in: upright, regions: detections.ingredients
        )
        let cropMs = Date().timeIntervalSince(cropStarted) * 1000

        // 3. Whole-image classification: what is present, with no location.
        //
        //    Deliberately NOT `try`. A classifier failure used to propagate
        //    out of this method and discard the YOLO detections computed in
        //    step 1 and skip the OCR in step 4 - one unavailable API threw
        //    away all the work that had succeeded. Degrading to YOLO-only is
        //    a worse result, but it is a *result*.
        var scene = ClassificationResult.empty
        var classifierFailure: String?
        let capability = classifier.capability

        let sceneStarted = Date()
        if capability.isAvailable {
            do {
                scene = try classifier.classify(upright, orientation: .up)
            } catch {
                classifierFailure = (error as? VisionClassificationError)?.message
                    ?? error.localizedDescription
                logger.error("""
                ANALYSIS stage=classify result=failed \
                error=\(classifierFailure!, privacy: .public)
                """)
            }
        }
        let sceneMs = Date().timeIntervalSince(sceneStarted) * 1000

        // 4. Packaging text. Self-gating - produces nothing on loose produce.
        //    Independent of the classifier: OCR is a different Vision request
        //    and works in the simulator, so it must not be gated on something
        //    that does not.
        var packaging = PackagedFoodReading.empty
        var textFailure: String?
        let ocrStarted = Date()
        do {
            packaging = try textReader.read(upright, orientation: .up)
        } catch {
            textFailure = (error as? VisionClassificationError)?.message
                ?? error.localizedDescription
            logger.error("""
            ANALYSIS stage=ocr result=failed error=\(textFailure!, privacy: .public)
            """)
        }
        let ocrMs = Date().timeIntervalSince(ocrStarted) * 1000

        // With no classifier there are no region results either, so every
        // fused claim is single-source. Nothing here invents an agreement or
        // a confidence the classifier never produced.
        let fused = fusion.fuse(
            detections: detections,
            regionClassifications: regionOutcome.results,
            sceneClassification: scene
        )

        let duration = Date().timeIntervalSince(started)
        // One structured line per analysis, greppable with
        //   log stream --predicate 'subsystem == "com.Fridge.FridgeFit"'
        //
        // Privacy: counts, durations, capability states and error *codes*
        // only. No image data, no ingredient names, no user identifiers -
        // every interpolation here is a number or a fixed enum case, and the
        // ones that are not are marked `.public` deliberately because they
        // are framework error strings, not user content.
        logger.info("""
        ANALYSIS stage=complete totalMs=\(Int(duration * 1000)) \
        detectMs=\(Int(detectMs)) sceneMs=\(Int(sceneMs)) \
        cropMs=\(Int(cropMs)) ocrMs=\(Int(ocrMs)) \
        capability=\(String(describing: capability), privacy: .public) \
        boxes=\(detections.ingredients.count) \
        localised=\(fused.localised.count) agreed=\(fused.agreedCount) \
        conflicting=\(fused.conflictCount) scene=\(fused.sceneLevel.count) \
        regionsAttempted=\(regionOutcome.attempted) regionFailures=\(regionOutcome.failureCount) \
        textLines=\(packaging.lines.count) \
        sceneFailure=\(classifierFailure ?? "none", privacy: .public) \
        ocrFailure=\(textFailure ?? "none", privacy: .public)
        """)

        return SnapshotAnalysis(
            snapshotId: snapshotId,
            classification: ClassificationOutcome(
                capability: capability,
                sceneFailure: classifierFailure,
                regionsAttempted: regionOutcome.attempted,
                regionFailures: regionOutcome.failureCount,
                regionFailure: regionOutcome.failure,
                packagingFailure: textFailure
            ),
            fused: fused,
            fullImageBaseline: scene,
            packaging: packaging,
            duration: duration
        )
    }

    /// Applies `orientation` once so every later step works on upright pixels.
    ///
    /// Without this, the crops would be cut from the unrotated image using
    /// boxes measured against the rotated one.
    private func uprightImage(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        guard orientation != .up else { return image }
        let ciImage = CIImage(cgImage: image).oriented(orientation)
        return CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent)
    }
}
