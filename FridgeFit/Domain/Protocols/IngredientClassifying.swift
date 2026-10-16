//
//  IngredientClassifying.swift
//  FridgeFit
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// One ingredient a classifier believes is somewhere in the image.
///
/// Deliberately has **no bounding box**. `VNClassifyImageRequest` is a
/// whole-image classifier: it reports what is present, not where. Giving this
/// type a box would invite attaching a scene-level label to an unrelated
/// rectangle, which is precisely the mistake `DetectionFusionService`
/// refuses to make.
nonisolated struct ClassifiedIngredient: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Stable ingredient identity, shared with `DetectedIngredient.ingredientId`.
    let ingredientId: String
    let displayName: String
    let category: IngredientGroup
    let confidence: Float
    /// The raw Vision identifier, kept for diagnostics.
    let rawIdentifier: String
    /// True when the identifier is a hypernym that must not be read as a
    /// species claim - Vision's `meat`, `beef`, `poultry`.
    let requiresReview: Bool

    init(
        id: UUID = UUID(),
        ingredientId: String,
        displayName: String,
        category: IngredientGroup,
        confidence: Float,
        rawIdentifier: String,
        requiresReview: Bool
    ) {
        self.id = id
        self.ingredientId = ingredientId
        self.displayName = displayName
        self.category = category
        self.confidence = confidence
        self.rawIdentifier = rawIdentifier
        self.requiresReview = requiresReview
    }

    var confidencePercentage: Int { Int((confidence * 100).rounded()) }
}

/// Whether image classification can run here at all.
///
/// Three states, not two, because "this platform does not support it" and
/// "it tried and broke" need completely different handling. The first is an
/// expected, benign limitation of the iOS Simulator that should degrade the
/// pipeline quietly to YOLO-only; the second is a real defect that must be
/// reported in full. Collapsing them would mean either crying wolf on every
/// simulator run, or silently hiding a genuine on-device failure.
nonisolated enum ClassificationCapability: Equatable, Sendable {
    /// `VNClassifyImageRequest` ran successfully in a probe.
    case available
    /// Running in the iOS Simulator, where the request fails with
    /// "Failed to create espresso context". Verified with a 20-line
    /// reproduction containing no FridgeFit code: the same program returns
    /// 1303 classifications on macOS and fails under the simulator SDK.
    case unavailableInSimulator(String)
    /// The probe failed somewhere that *should* work. A real problem.
    case failed(String)

    var isAvailable: Bool { self == .available }

    /// Whether this is an expected platform limitation rather than a fault.
    var isExpectedLimitation: Bool {
        if case .unavailableInSimulator = self { return true }
        return false
    }

    /// What the user should be told, or `nil` when everything works.
    var userMessage: String? {
        switch self {
        case .available:
            return nil
        case .unavailableInSimulator:
            return "Apple Vision classification unavailable in Simulator"
        case .failed(let reason):
            return "Apple Vision classification failed: \(reason)"
        }
    }

    /// The underlying reason, for diagnostics.
    var diagnosticDetail: String? {
        switch self {
        case .available: return nil
        case .unavailableInSimulator(let detail), .failed(let detail): return detail
        }
    }
}

/// The result of classifying one image.
nonisolated struct ClassificationResult: Equatable, Sendable {
    let ingredients: [ClassifiedIngredient]
    /// Concrete food claims that are not FridgeFit ingredients - "brownie"
    /// on a photo of raw beef. Never shown to the user, but carried so
    /// evaluation can count them instead of silently discarding them.
    let rejectedFoodClaims: [String]

    static let empty = ClassificationResult(ingredients: [], rejectedFoodClaims: [])

    var isEmpty: Bool { ingredients.isEmpty }
}

/// Classifies a still image into candidate ingredients.
///
/// Separate from `FrameDetecting` because the two answer different questions:
/// a detector says *where* something is, a classifier says *what* is present.
/// Keeping them apart is what lets `DetectionFusionService` treat agreement
/// between them as evidence - two methods that share an implementation would
/// not be independent, and their agreement would mean nothing.
///
/// Implementations are synchronous and blocking, and must be safe to call
/// from a background queue one call at a time.
nonisolated protocol IngredientClassifying: Sendable {
    /// Whether classification can run at all here.
    ///
    /// Callers check this *before* asking for work, so an unsupported
    /// platform costs nothing and an empty result never gets mistaken for
    /// "looked and found nothing".
    var capability: ClassificationCapability { get }

    func classify(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> ClassificationResult
    func classify(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> ClassificationResult
}
