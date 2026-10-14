//
//  YOLOFoodDetectionService.swift
//  FridgeFit
//

import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ImageIO
import OSLog
import Vision

/// On-device food detection with a pretrained YOLO11n (COCO) Core ML model.
///
/// Runs entirely on the Controller iPhone - no network, no API, no account.
/// The model is the official Ultralytics pretrained checkpoint exported to
/// Core ML by `tools/yolo-export/setup.sh`; nothing here is trained or
/// fine-tuned.
///
/// ## Why Vision rather than raw Core ML
///
/// The export bakes NMS into the Core ML pipeline and emits the
/// `confidence` + `coordinates` output pair Vision recognises as an object
/// detector. That means `VNCoreMLRequest` hands back
/// `VNRecognizedObjectObservation`s with boxes already decoded and
/// suppressed, instead of us hand-rolling anchor decoding and NMS in Swift.
///
/// ## Thread safety
///
/// `detect` is synchronous and blocking, and is called from a background
/// queue owned by `RemoteVideoFrameTap`. The instance is **not** safe to call
/// concurrently - `VNCoreMLRequest` holds its results on the request object.
/// The tap guarantees one in-flight call at a time.
nonisolated final class YOLOFoodDetectionService: FrameDetecting, @unchecked Sendable {

    nonisolated struct Configuration: Sendable {
        /// Bundle resource name of the compiled model, without extension.
        var modelName: String = "YOLO11n"
        /// Detections below this are discarded.
        ///
        /// Applied in Swift on top of the model's own baked-in NMS threshold
        /// (0.25 from the export). Raising it here is always safe; lowering
        /// it below 0.25 has no effect, because the pipeline has already
        /// suppressed those.
        var confidenceThreshold: Float = 0.45
        /// Class names to keep. Everything else the model reports is dropped.
        var allowedLabels: Set<String> = COCOFoodClass.all
        /// Cap on boxes per frame, highest confidence first. A crowded frame
        /// shouldn't turn the overlay into a wall of rectangles.
        var maximumDetections: Int = 12

        static let `default` = Configuration()
    }

    private let configuration: Configuration
    private let visionModel: VNCoreMLModel
    private let request: VNCoreMLRequest
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "YOLO")

    /// Loads and compiles the model.
    ///
    /// - Throws: `YOLODetectionError.modelMissing` if the model isn't in the
    ///   bundle, `.modelLoadFailed` if Core ML or Vision rejects it. Both are
    ///   terminal - the caller reports them and stops, rather than retrying
    ///   per frame.
    init(configuration: Configuration = .default, bundle: Bundle = .main) throws {
        self.configuration = configuration

        guard let url = Self.modelURL(named: configuration.modelName, in: bundle) else {
            throw YOLODetectionError.modelMissing(name: configuration.modelName)
        }

        let mlConfiguration = MLModelConfiguration()
        // Let Core ML pick: Neural Engine where available, GPU or CPU
        // otherwise. YOLO11n runs comfortably on the ANE of any iPhone that
        // can run iOS 26.
        mlConfiguration.computeUnits = .all

        let loadStarted = Date()
        do {
            let model = try MLModel(contentsOf: url, configuration: mlConfiguration)
            visionModel = try VNCoreMLModel(for: model)
        } catch {
            // Core ML's own message carries the underlying code, which is the
            // part worth having when a model fails to load only on device.
            Logger(subsystem: "com.Fridge.FridgeFit", category: "YOLO").error("""
            MODEL stage=load result=failed name=\(configuration.modelName, privacy: .public) \
            error=\(error.localizedDescription, privacy: .public)
            """)
            throw YOLODetectionError.modelLoadFailed(reason: error.localizedDescription)
        }
        let loadMs = Int(Date().timeIntervalSince(loadStarted) * 1000)

        request = VNCoreMLRequest(model: visionModel)
        // `.scaleFill` stretches the frame to the model's square input.
        //
        // The alternative, `.scaleFit`, letterboxes - which matches how YOLO
        // was trained and is marginally more accurate - but Vision does not
        // consistently compensate for the padding when mapping boxes back,
        // so detections land offset from the object. `.centerCrop` would
        // discard the edges of the frame entirely.
        //
        // `.scaleFill` maps linearly onto the whole frame, so a normalised
        // box means exactly what `DetectionGeometry` assumes it means. For a
        // feature whose entire job is drawing boxes in the right place, that
        // predictability is worth more than the small accuracy difference.
        request.imageCropAndScaleOption = .scaleFill

        logger.info("""
        MODEL stage=load result=ok name=\(configuration.modelName, privacy: .public) \
        loadMs=\(loadMs) \
        threshold=\(configuration.confidenceThreshold) \
        classes=\(configuration.allowedLabels.count)
        """)
    }

    /// Where the compiled model lives.
    ///
    /// Xcode compiles a bundled `.mlpackage` into `.mlmodelc`. The
    /// `.mlpackage` fallback covers a build that copied it verbatim as a
    /// resource instead, which `MLModel` can still open.
    static func modelURL(named name: String, in bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: "mlmodelc")
            ?? bundle.url(forResource: name, withExtension: "mlpackage")
    }

    /// Whether the model is present without loading it. Used to report a
    /// missing model before a session starts.
    static func isModelBundled(named name: String = Configuration.default.modelName,
                               in bundle: Bundle = .main) -> Bool {
        modelURL(named: name, in: bundle) != nil
    }

    var confidenceThreshold: Float { configuration.confidenceThreshold }
    var allowedLabels: Set<String> { configuration.allowedLabels }

    // MARK: - Inference

    /// Runs detection on one frame.
    ///
    /// - Parameters:
    ///   - pixelBuffer: the decoded frame, used in place - no copy.
    ///   - orientation: how to rotate the buffer so it is upright. Vision
    ///     applies it, so the returned boxes are already in display space.
    ///   - orientedSize: the frame size after that rotation, carried through
    ///     to the result so the overlay maps boxes against the right geometry.
    /// - Returns: food detections above the threshold, highest confidence
    ///   first. An empty result is a normal outcome, not a failure.
    func detect(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        orientedSize: CGSize
    ) throws -> DetectionFrame {
        try detect(
            using: VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]
            ),
            orientedSize: orientedSize
        )
    }

    /// Runs detection on a still image.
    ///
    /// Same model, same thresholds, same output as the live path - only the
    /// input differs. Used by the captured-photo analysis, which works from a
    /// full-resolution `UIImage` rather than a bandwidth-adapted video frame.
    func detect(
        in image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        orientedSize: CGSize? = nil
    ) throws -> DetectionFrame {
        try detect(
            using: VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]),
            orientedSize: orientedSize ?? CGSize(width: image.width, height: image.height)
        )
    }

    private func detect(
        using handler: VNImageRequestHandler,
        orientedSize: CGSize
    ) throws -> DetectionFrame {
        do {
            try handler.perform([request])
        } catch {
            throw YOLODetectionError.inferenceFailed(reason: error.localizedDescription)
        }

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            // No results array at all means the model produced something
            // Vision couldn't read as detections - a wrong model, not a
            // frame with nothing in it.
            throw YOLODetectionError.inferenceFailed(
                reason: "the model did not return object detections"
            )
        }

        return DetectionFrame(
            objects: Self.foodDetections(from: Self.raw(from: observations), configuration: configuration),
            sourceSize: orientedSize
        )
    }

    /// Flattens Vision observations into plain values.
    ///
    /// `labels` is sorted by confidence, so the first entry is the model's
    /// pick for that box.
    static func raw(from observations: [VNRecognizedObjectObservation]) -> [RawDetection] {
        observations.compactMap { observation in
            guard let best = observation.labels.first else { return nil }
            return RawDetection(
                label: best.identifier,
                confidence: best.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    /// Filters and ranks detections.
    ///
    /// Takes `RawDetection` rather than `VNRecognizedObjectObservation`
    /// because the latter has no public initialiser that sets labels - there
    /// is no way to construct one in a test. Going through a plain value type
    /// makes the filtering rules, which are the part worth testing, actually
    /// testable.
    static func foodDetections(
        from detections: [RawDetection],
        configuration: Configuration
    ) -> [DetectedObject] {
        detections
            .compactMap { detection -> DetectedObject? in
                let label = detection.label.lowercased()
                guard configuration.allowedLabels.contains(label) else { return nil }
                guard detection.confidence >= configuration.confidenceThreshold else { return nil }

                return DetectedObject(
                    label: label,
                    confidence: detection.confidence,
                    boundingBox: detection.boundingBox
                )
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(configuration.maximumDetections)
            .map { $0 }
    }
}

/// One box as the model reported it, before food filtering.
///
/// Exists so the filtering rules can be tested without Vision - see
/// `YOLOFoodDetectionService.foodDetections(from:configuration:)`.
nonisolated struct RawDetection: Equatable, Sendable {
    let label: String
    let confidence: Float
    /// Normalised, Vision orientation.
    let boundingBox: CGRect
}
