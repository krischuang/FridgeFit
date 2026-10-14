//
//  PackagingOCRTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import XCTest
@testable import FridgeFit

/// Packaging OCR over the shared evaluation images.
///
/// Separate from `HybridRecognitionEvaluationTests` because
/// `VNRecognizeTextRequest` *does* work in the iOS simulator, unlike
/// `VNClassifyImageRequest`. These measure rather than skip.
final class PackagingOCRTests: XCTestCase {

    /// Packaging OCR, on the images that actually have packaging.
    ///
    /// `VNRecognizeTextRequest` *does* work in the simulator, unlike the
    /// classifier, so this one measures rather than skips.
    func test_packagingTextIsReadWhereThereIsPackaging() throws {
        let annotations = try HybridEvaluation.annotations()
        let taxonomy = try IngredientTaxonomy.load(in: .main)
        let reader = PackagedFoodTextReader(taxonomy: taxonomy)

        var lineCounts: [String: Int] = [:]
        for name in annotations.keys {
            let reading = try reader.read(try HybridEvaluation.image(named: name))
            lineCounts[name] = reading.lines.count
        }
        print("OCR line counts: \(lineCounts.sorted { $0.key < $1.key })")

        // Self-gating is the property that lets OCR run unconditionally.
        XCTAssertGreaterThan(lineCounts["shelf_packaged"] ?? 0, 5,
                             "a shelf of packaged goods should yield text")
        for name in ["fruits_mixed", "veg_mixed", "beef_raw", "chicken_raw"] {
            XCTAssertEqual(lineCounts[name], 0,
                           "\(name) has no packaging, so OCR must find nothing")
        }
    }
}
