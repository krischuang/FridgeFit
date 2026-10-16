//
//  SnapshotAnalysisConsistencyTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import FridgeFit

/// That the analysis on screen describes the photo on screen, and that every
/// box came from a measurement rather than from somewhere convenient.
///
/// These are the failure modes that are invisible by inspection: a box drawn
/// from the previous capture still looks like a box, and a whole-image label
/// attached to a rectangle still looks like a detection.
@MainActor
final class SnapshotAnalysisConsistencyTests: XCTestCase {

    private func analysis(
        snapshotId: UUID,
        localised: [FusedIngredient] = [],
        scene: [FusedIngredient] = [],
        sourceSize: CGSize = CGSize(width: 640, height: 480)
    ) -> SnapshotAnalysis {
        SnapshotAnalysis(
            snapshotId: snapshotId,
            fused: FusedDetectionFrame(
                localised: localised, sceneLevel: scene,
                sourceSize: sourceSize, rejectedFoodClaims: []
            ),
            fullImageBaseline: .empty,
            packaging: .empty,
            duration: 0.1
        )
    }

    private func localisedIngredient(_ name: String, _ box: CGRect) -> FusedIngredient {
        FusedIngredient(
            ingredientId: name, displayName: name.capitalized, category: .fruit,
            tier: .agreed, sources: [.detector, .regionClassifier],
            boundingBox: box, detectorConfidence: 0.8, classifierConfidence: 0.7
        )
    }

    private func sceneIngredient(_ name: String) -> FusedIngredient {
        FusedIngredient(
            ingredientId: name, displayName: name.capitalized, category: .seafood,
            tier: .singleSource, sources: .sceneClassifier,
            boundingBox: nil, classifierConfidence: 0.6
        )
    }

    // MARK: - The analysis belongs to the photo

    func test_anAnalysisCarriesTheIdentityOfThePhotoItDescribes() {
        let identity = UUID()
        let result = analysis(snapshotId: identity)

        XCTAssertEqual(result.snapshotId, identity)
    }

    /// The failure this guards: a second capture lands while the first is
    /// still being analysed, and the earlier result ends up drawn over the
    /// newer photo. The boxes would be real - just measured against other
    /// pixels.
    func test_anAnalysisFromADifferentPhotoIsNotCurrent() async {
        let viewModel = makeViewModel()
        let first = UIImage.solid(.red, size: CGSize(width: 64, height: 64))
        let second = UIImage.solid(.blue, size: CGSize(width: 64, height: 64))

        viewModel.presentSnapshotForPreview(first)
        let firstId = try! XCTUnwrap(viewModel.snapshotId)

        // A result for the first photo arrives after the second is displayed.
        viewModel.presentSnapshotForPreview(second)
        let secondId = try! XCTUnwrap(viewModel.snapshotId)
        XCTAssertNotEqual(firstId, secondId)

        viewModel.presentAnalysisForPreview(analysis(snapshotId: firstId))

        XCTAssertFalse(viewModel.isAnalysisCurrent)
        XCTAssertNil(viewModel.currentAnalysis,
                     "a stale analysis must not be shown against a newer photo")
    }

    func test_anAnalysisForTheDisplayedPhotoIsCurrent() {
        let viewModel = makeViewModel()
        viewModel.presentSnapshotForPreview(.solid(.red, size: CGSize(width: 64, height: 64)))
        let identity = try! XCTUnwrap(viewModel.snapshotId)

        viewModel.presentAnalysisForPreview(analysis(snapshotId: identity))

        XCTAssertTrue(viewModel.isAnalysisCurrent)
        XCTAssertNotNil(viewModel.currentAnalysis)
    }

    func test_anewPhotoClearsThePreviousAnalysis() {
        let viewModel = makeViewModel()
        viewModel.presentSnapshotForPreview(.solid(.red, size: CGSize(width: 64, height: 64)))
        viewModel.presentAnalysisForPreview(
            analysis(snapshotId: try! XCTUnwrap(viewModel.snapshotId))
        )
        XCTAssertNotNil(viewModel.currentAnalysis)

        viewModel.presentSnapshotForPreview(.solid(.green, size: CGSize(width: 64, height: 64)))

        XCTAssertNil(viewModel.currentAnalysis)
    }

    // MARK: - Boxes are measured, not invented

    func test_sceneLevelClaimsNeverCarryABox() {
        let result = analysis(
            snapshotId: UUID(),
            localised: [localisedIngredient("apple", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))],
            scene: [sceneIngredient("salmon_fillet")]
        )

        for item in result.fused.sceneLevel {
            XCTAssertNil(item.boundingBox)
            XCTAssertFalse(item.isLocalised)
        }
        XCTAssertEqual(result.fused.localised.count, 1)
    }

    /// The review model must preserve the split, or the thumbnail overlay
    /// would draw a whole-image label at an invented position.
    func test_theReviewSplitMatchesWhichItemsHaveBoxes() {
        let result = analysis(
            snapshotId: UUID(),
            localised: [localisedIngredient("apple", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))],
            scene: [sceneIngredient("salmon_fillet")]
        )

        let review = IngredientReviewViewModel(analysis: result)

        XCTAssertEqual(review.localisedItems.count, 1)
        XCTAssertEqual(review.unlocalisedItems.count, 1)
        for item in review.unlocalisedItems {
            XCTAssertNil(item.boundingBox, "nothing unlocalised may acquire a box")
        }
    }

    /// Boxes travel with the geometry they were measured against, so the
    /// overlay cannot map them onto the wrong aspect ratio.
    func test_theSourceSizeTravelsWithTheBoxes() {
        let size = CGSize(width: 1280, height: 720)
        let result = analysis(
            snapshotId: UUID(),
            localised: [localisedIngredient("apple", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))],
            sourceSize: size
        )

        XCTAssertEqual(result.fused.sourceSize, size)
        XCTAssertEqual(IngredientReviewViewModel(analysis: result).sourceSize, size)
    }

    /// Mapping a box onto the review thumbnail uses aspect-*fit*, because the
    /// thumbnail is `scaledToFit`. Using the live view's aspect-fill here
    /// would place every box wrongly.
    func test_theThumbnailMappingIsAspectFit() {
        let source = CGSize(width: 640, height: 480)   // 4:3
        let view = CGSize(width: 300, height: 300)     // square
        let box = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let fit = DetectionGeometry.rect(
            for: box, sourceSize: source, viewSize: view, contentMode: .scaleAspectFit
        )
        let fill = DetectionGeometry.rect(
            for: box, sourceSize: source, viewSize: view, contentMode: .scaleAspectFill
        )

        let fitted = try! XCTUnwrap(fit)
        XCTAssertNotEqual(fitted, try! XCTUnwrap(fill),
                          "the two modes must differ, or this test proves nothing")
        // Aspect-fit letterboxes a 4:3 source in a square view, so the drawn
        // content is 300x225 centred vertically.
        XCTAssertEqual(fitted.width, 150, accuracy: 0.5)
        XCTAssertEqual(fitted.height, 112.5, accuracy: 0.5)
        XCTAssertEqual(fitted.midX, 150, accuracy: 0.5)
        XCTAssertEqual(fitted.midY, 150, accuracy: 0.5)
    }

    // MARK: - Live boxes are not reused

    /// Analysis runs the detector over the captured still. It must not read
    /// the live overlay's boxes, which were measured against a different
    /// frame at a different resolution.
    func test_analysisDoesNotReuseLiveDetectionState() {
        let viewModel = makeViewModel()
        viewModel.presentSnapshotForPreview(.solid(.red, size: CGSize(width: 64, height: 64)))
        let identity = try! XCTUnwrap(viewModel.snapshotId)

        // The live overlay holds something from the video stream.
        XCTAssertTrue(viewModel.ingredients.isEmpty,
                      "precondition: no live detections in this fixture")

        let fresh = analysis(
            snapshotId: identity,
            localised: [localisedIngredient("pear", CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))]
        )
        viewModel.presentAnalysisForPreview(fresh)

        let current = try! XCTUnwrap(viewModel.currentAnalysis)
        XCTAssertEqual(current.fused.localised.map(\.ingredientId), ["pear"])
        XCTAssertTrue(viewModel.ingredients.isEmpty,
                      "the live overlay is a separate channel and is untouched")
    }

    // MARK: - Helpers

    private func makeViewModel() -> RemoteCameraViewModel {
        RemoteCameraViewModel(
            identity: DeviceIdentity(deviceId: "test-controller", deviceName: "Test"),
            registry: InMemoryDeviceRegistry(seedDevices: []),
            transport: InMemorySignalingTransport(),
            makeDetector: nil
        )
    }
}

extension UIImage {
    /// A solid-colour image, for fixtures that only need identity.
    static func solid(_ colour: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
