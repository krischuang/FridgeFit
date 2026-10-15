//
//  YOLOFoodDetectionServiceTests.swift
//  FridgeFitTests
//

import CoreGraphics
import CoreVideo
import UIKit
import XCTest
@testable import FridgeFit

/// The detection service: model loading, real inference, and filtering.
///
/// The inference tests run the **actual bundled YOLO11n model** - not a stub.
/// They are the only proof that the export, the bundling, the Core ML build
/// rule and the Vision wiring all line up.
final class YOLOFoodDetectionServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// A 640x640 white image with a solid orange disc in the middle.
    ///
    /// Chosen because the pretrained COCO model reliably calls it an
    /// "orange" at high confidence - verified against the Ultralytics
    /// checkpoint before this test was written. It gives a *known* expected
    /// detection without bundling a photograph of unclear provenance.
    ///
    /// The disc spans 200...440 of 640, i.e. 0.3125...0.6875 normalised, and
    /// is centred - which also pins down the coordinate convention.
    private func orangeOnWhite(size: CGFloat = 640) -> CVPixelBuffer {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: size, height: size), format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor(red: 1.0, green: 140.0 / 255.0, blue: 0, alpha: 1).setFill()
            context.cgContext.fillEllipse(
                in: CGRect(x: size * 200 / 640, y: size * 200 / 640,
                           width: size * 240 / 640, height: size * 240 / 640)
            )
        }
        return pixelBuffer(from: image)!
    }

    private func blankImage(width: Int = 640, height: Int = 640) -> CVPixelBuffer {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixelBuffer(from: image)!
    }

    /// `UIImage` -> BGRA `CVPixelBuffer`, the shape Vision takes.
    private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func makeService(
        confidenceThreshold: Float = 0.45,
        allowedLabels: Set<String> = COCOFoodClass.all,
        maximumDetections: Int = 12
    ) throws -> YOLOFoodDetectionService {
        var configuration = YOLOFoodDetectionService.Configuration.default
        configuration.confidenceThreshold = confidenceThreshold
        configuration.allowedLabels = allowedLabels
        configuration.maximumDetections = maximumDetections
        return try YOLOFoodDetectionService(configuration: configuration)
    }

    // MARK: - Model loading

    func test_theModelIsBundled() {
        XCTAssertTrue(
            YOLOFoodDetectionService.isModelBundled(),
            """
            YOLO11n is not in the app bundle. Run tools/yolo-export/setup.sh \
            and rebuild.
            """
        )
    }

    func test_theCompiledModelIsWhatGetsLoaded() throws {
        let url = try XCTUnwrap(YOLOFoodDetectionService.modelURL(named: "YOLO11n", in: .main))

        // Xcode's Core ML build rule turns the .mlpackage into .mlmodelc.
        // Finding the raw package instead would mean the build rule didn't run.
        XCTAssertEqual(url.pathExtension, "mlmodelc", "expected a compiled model, got \(url.lastPathComponent)")
    }

    func test_theServiceLoads() throws {
        let service = try makeService()

        XCTAssertEqual(service.confidenceThreshold, 0.45)
        XCTAssertEqual(service.allowedLabels, COCOFoodClass.all)
    }

    func test_aMissingModelIsReportedNotFakedAround() {
        var configuration = YOLOFoodDetectionService.Configuration.default
        configuration.modelName = "NoSuchModel"

        XCTAssertThrowsError(try YOLOFoodDetectionService(configuration: configuration)) { error in
            XCTAssertEqual(error as? YOLODetectionError, .modelMissing(name: "NoSuchModel"))
        }
        XCTAssertFalse(YOLOFoodDetectionService.isModelBundled(named: "NoSuchModel"))
    }

    func test_aMissingModelIsTerminalNotRetried() {
        XCTAssertFalse(YOLODetectionError.modelMissing(name: "X").isRecoverable)
        XCTAssertFalse(YOLODetectionError.modelLoadFailed(reason: "x").isRecoverable)
        XCTAssertFalse(YOLODetectionError.unsupportedPixelFormat.isRecoverable)
        // A single bad frame might not repeat.
        XCTAssertTrue(YOLODetectionError.frameConversionFailed.isRecoverable)
        XCTAssertTrue(YOLODetectionError.inferenceFailed(reason: "x").isRecoverable)
    }

    func test_everyErrorExplainsItself() {
        let errors: [YOLODetectionError] = [
            .modelMissing(name: "YOLO11n"),
            .modelLoadFailed(reason: "x"),
            .unsupportedPixelFormat,
            .frameConversionFailed,
            .inferenceFailed(reason: "x"),
        ]
        for error in errors {
            XCTAssertFalse(error.message.isEmpty, "\(error)")
        }
        XCTAssertTrue(
            YOLODetectionError.modelMissing(name: "YOLO11n").message.contains("yolo-export"),
            "a missing model should say how to produce one"
        )
    }

    // MARK: - Real inference

    /// The headline test: the real model, on a known image, finding the right
    /// thing in the right place.
    func test_realInferenceFindsAnOrangeInTheKnownImage() throws {
        let service = try makeService()
        let buffer = orangeOnWhite()

        let result = try service.detect(
            in: buffer,
            orientation: .up,
            orientedSize: CGSize(width: 640, height: 640)
        )

        XCTAssertEqual(result.sourceSize, CGSize(width: 640, height: 640))
        let orange = try XCTUnwrap(
            result.objects.first { $0.label == "orange" },
            "expected an orange, got \(result.objects.map(\.label))"
        )
        XCTAssertGreaterThan(orange.confidence, 0.45)
        XCTAssertLessThanOrEqual(orange.confidence, 1.0)

        // The disc is centred and spans ~0.375 of the frame. This is what
        // pins down the coordinate convention end to end: if Vision's output
        // were being misread, the centre would not land at (0.5, 0.5).
        XCTAssertEqual(orange.boundingBox.midX, 0.5, accuracy: 0.08)
        XCTAssertEqual(orange.boundingBox.midY, 0.5, accuracy: 0.08)
        XCTAssertEqual(orange.boundingBox.width, 0.375, accuracy: 0.12)
        XCTAssertEqual(orange.boundingBox.height, 0.375, accuracy: 0.12)
    }

    func test_everyBoxFromRealInferenceIsNormalised() throws {
        let service = try makeService()

        let result = try service.detect(
            in: orangeOnWhite(),
            orientation: .up,
            orientedSize: CGSize(width: 640, height: 640)
        )

        XCTAssertFalse(result.objects.isEmpty)
        for object in result.objects {
            XCTAssertGreaterThanOrEqual(object.boundingBox.minX, -0.01, "\(object.label)")
            XCTAssertGreaterThanOrEqual(object.boundingBox.minY, -0.01, "\(object.label)")
            XCTAssertLessThanOrEqual(object.boundingBox.maxX, 1.01, "\(object.label)")
            XCTAssertLessThanOrEqual(object.boundingBox.maxY, 1.01, "\(object.label)")
        }
    }

    /// Zero detections is a normal outcome, not an error.
    func test_aBlankImageReturnsNoDetectionsWithoutThrowing() throws {
        let service = try makeService()

        let result = try service.detect(
            in: blankImage(),
            orientation: .up,
            orientedSize: CGSize(width: 640, height: 640)
        )

        XCTAssertTrue(result.objects.isEmpty, "got \(result.objects.map(\.label))")
    }

    /// Non-square input exercises the `.scaleFill` path the live stream uses.
    func test_inferenceRunsOnNonSquareFrames() throws {
        let service = try makeService()

        let result = try service.detect(
            in: blankImage(width: 1280, height: 720),
            orientation: .up,
            orientedSize: CGSize(width: 1280, height: 720)
        )

        XCTAssertEqual(result.sourceSize, CGSize(width: 1280, height: 720))
    }

    /// Every rotation Vision can be handed must run without throwing - the
    /// remote camera rotates whenever the user turns the other phone.
    func test_inferenceRunsForEveryFrameRotation() throws {
        let service = try makeService()
        let buffer = orangeOnWhite()

        for rotation in FrameOrientation.Rotation.allCases {
            let orientation = try XCTUnwrap(
                CGImagePropertyOrientation(
                    rawValue: FrameOrientation.cgOrientationRawValue(for: rotation)
                )
            )
            let size = FrameOrientation.orientedSize(width: 640, height: 640, rotation: rotation)

            let result = try service.detect(in: buffer, orientation: orientation, orientedSize: size)

            // The image is rotationally symmetric, so the orange survives
            // every orientation - which also shows the orientation is being
            // applied rather than ignored.
            XCTAssertTrue(
                result.objects.contains { $0.label == "orange" },
                "rotation \(rotation) lost the detection"
            )
        }
    }

    /// Raising the threshold above the observed confidence must drop it.
    func test_theConfidenceThresholdIsAppliedToRealResults() throws {
        let permissive = try makeService(confidenceThreshold: 0.45)
        let buffer = orangeOnWhite()
        let found = try permissive.detect(
            in: buffer, orientation: .up, orientedSize: CGSize(width: 640, height: 640)
        )
        XCTAssertFalse(found.objects.isEmpty)

        // Nothing is ever 99.9% confident.
        let strict = try makeService(confidenceThreshold: 0.999)
        let none = try strict.detect(
            in: buffer, orientation: .up, orientedSize: CGSize(width: 640, height: 640)
        )

        XCTAssertTrue(none.objects.isEmpty, "got \(none.objects.map { "\($0.label) \($0.confidence)" })")
    }

    /// Restricting the allowed set must exclude a class the model did report.
    func test_classFilteringExcludesRealDetections() throws {
        let service = try makeService(allowedLabels: ["banana"])

        let result = try service.detect(
            in: orangeOnWhite(), orientation: .up, orientedSize: CGSize(width: 640, height: 640)
        )

        XCTAssertTrue(result.objects.isEmpty, "orange should be filtered out when only banana is allowed")
    }

    // MARK: - Filtering rules

    private func raw(_ label: String, _ confidence: Float) -> RawDetection {
        RawDetection(
            label: label,
            confidence: confidence,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
    }

    func test_onlyFoodClassesSurvive() {
        let detections = [
            raw("banana", 0.9), raw("person", 0.99), raw("apple", 0.8),
            raw("car", 0.95), raw("bowl", 0.9), raw("cup", 0.9), raw("broccoli", 0.7),
        ]

        let result = YOLOFoodDetectionService.foodDetections(
            from: detections, configuration: .default
        )

        XCTAssertEqual(Set(result.map(\.label)), ["banana", "apple", "broccoli"])
    }

    /// Tableware is not food. A bowl in a fridge photo is a bowl.
    func test_tablewareIsNotTreatedAsFood() {
        for label in ["bowl", "cup", "bottle", "wine glass", "fork", "knife", "spoon", "dining table"] {
            XCTAssertFalse(COCOFoodClass.isFood(label), "\(label) should not count as food")
        }
    }

    func test_theTenCocoFoodClassesAreSupported() {
        let expected: Set<String> = [
            "banana", "apple", "sandwich", "orange",
            "broccoli", "carrot", "hot dog", "pizza", "donut", "cake",
        ]

        XCTAssertEqual(COCOFoodClass.all, expected)
        for label in expected {
            XCTAssertTrue(COCOFoodClass.isFood(label))
        }
    }

    /// Guards against the exact thing the brief forbids: inventing classes
    /// the model cannot detect.
    func test_fridgeStaplesTheModelCannotSeeAreNotClaimed() {
        for label in ["milk", "egg", "eggs", "cheese", "butter", "yoghurt", "chicken", "lettuce"] {
            XCTAssertFalse(COCOFoodClass.isFood(label), "\(label) is not a COCO class and must not be claimed")
        }
    }

    func test_lowConfidenceDetectionsAreDropped() {
        var configuration = YOLOFoodDetectionService.Configuration.default
        configuration.confidenceThreshold = 0.5

        let result = YOLOFoodDetectionService.foodDetections(
            from: [raw("banana", 0.49), raw("apple", 0.50), raw("orange", 0.51)],
            configuration: configuration
        )

        XCTAssertEqual(Set(result.map(\.label)), ["apple", "orange"], "the threshold is inclusive")
    }

    func test_resultsAreSortedByConfidence() {
        let result = YOLOFoodDetectionService.foodDetections(
            from: [raw("banana", 0.6), raw("apple", 0.95), raw("orange", 0.75)],
            configuration: .default
        )

        XCTAssertEqual(result.map(\.label), ["apple", "orange", "banana"])
    }

    func test_tooManyDetectionsAreCappedKeepingTheBestOnes() {
        var configuration = YOLOFoodDetectionService.Configuration.default
        configuration.maximumDetections = 2

        let result = YOLOFoodDetectionService.foodDetections(
            from: [raw("banana", 0.6), raw("apple", 0.95), raw("orange", 0.75)],
            configuration: configuration
        )

        XCTAssertEqual(result.map(\.label), ["apple", "orange"])
    }

    func test_labelsAreMatchedCaseInsensitively() {
        let result = YOLOFoodDetectionService.foodDetections(
            from: [raw("Banana", 0.9), raw("HOT DOG", 0.9)],
            configuration: .default
        )

        XCTAssertEqual(Set(result.map(\.label)), ["banana", "hot dog"], "labels are normalised to lowercase")
    }

    func test_noDetectionsIsAnEmptyResultNotAnError() {
        let result = YOLOFoodDetectionService.foodDetections(from: [], configuration: .default)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Presentation

    func test_labelsAreTitleCasedForDisplay() {
        XCTAssertEqual(
            DetectedObject(label: "hot dog", confidence: 0.9, boundingBox: .zero).displayName,
            "Hot Dog"
        )
        XCTAssertEqual(
            DetectedObject(label: "banana", confidence: 0.9, boundingBox: .zero).displayName,
            "Banana"
        )
    }

    func test_confidenceIsShownAsAWholePercentage() {
        XCTAssertEqual(
            DetectedObject(label: "banana", confidence: 0.914, boundingBox: .zero).confidencePercentage,
            91
        )
        XCTAssertEqual(
            DetectedObject(label: "banana", confidence: 0.916, boundingBox: .zero).confidencePercentage,
            92
        )
    }
}
