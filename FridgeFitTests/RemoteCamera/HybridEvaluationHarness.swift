//
//  HybridEvaluationHarness.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import ImageIO
import UIKit
import XCTest
@testable import FridgeFit

/// Scores recognisers against the same annotated images the Python harness
/// uses, with the same metric.
///
/// The metric is copied deliberately rather than reinvented, from
/// `tools/yolo-export/evaluate_vocabulary.py`:
///
///     recall    = |expected ∩ detected| / |expected|   per image, set-based
///     precision = found / (found + falsePositives)
///     falsePos  = |detected - expected|
///
/// Using the set of ingredient identifiers per image as the unit is what
/// makes a *detector* and a *classifier* comparable at all. A detector emits
/// boxes and a classifier emits labels; counting boxes would compare
/// different things and flatter whichever happens to emit more of them.
enum HybridEvaluation {

    /// One image's annotation.
    struct Annotation: Decodable {
        let category: String
        let present: [String]
    }

    struct Score {
        let label: String
        /// expected, found, falsePositives - per annotation category.
        var perCategory: [String: (expected: Int, found: Int, fp: Int)] = [:]
        var found = 0
        var expected = 0
        var falsePositives = 0
        /// Expected ingredients nothing named, for the false-negative report.
        var missed: [String] = []
        var spurious: [String] = []

        var recall: Double { expected > 0 ? Double(found) / Double(expected) : 0 }
        var precision: Double {
            found + falsePositives > 0
                ? Double(found) / Double(found + falsePositives) : 0
        }

        func recall(for category: String) -> Double {
            guard let stats = perCategory[category], stats.expected > 0 else { return 0 }
            return Double(stats.found) / Double(stats.expected)
        }
    }

    static let categories = ["fruit", "vegetable", "meat", "seafood", "dairy", "pantry"]

    // MARK: - Fixtures

    static func annotations() throws -> [String: Annotation] {
        let bundle = Bundle(for: BundleToken.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "eval_annotations", withExtension: "json"),
            "eval_annotations.json is not in the test bundle"
        )
        return try JSONDecoder().decode(
            [String: Annotation].self, from: try Data(contentsOf: url)
        )
    }

    static func image(named name: String) throws -> CGImage {
        let bundle = Bundle(for: BundleToken.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "jpg"),
            "\(name).jpg is not in the test bundle"
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    // MARK: - Scoring

    /// Scores a per-image set of ingredient identifiers.
    ///
    /// - Parameter detected: ingredient identifiers the recogniser produced,
    ///   keyed by image name. Identifiers must come from the same namespace
    ///   as the annotations.
    static func score(
        _ detected: [String: Set<String>],
        against annotations: [String: Annotation],
        label: String
    ) -> Score {
        var score = Score(label: label)

        for (name, annotation) in annotations {
            let expected = Set(annotation.present)
            let found = expected.intersection(detected[name] ?? [])
            let spurious = (detected[name] ?? []).subtracting(expected)

            var stats = score.perCategory[annotation.category] ?? (0, 0, 0)
            stats.expected += expected.count
            stats.found += found.count
            stats.fp += spurious.count
            score.perCategory[annotation.category] = stats

            score.expected += expected.count
            score.found += found.count
            score.falsePositives += spurious.count
            score.missed.append(contentsOf: expected.subtracting(found).map { "\(name):\($0)" })
            score.spurious.append(contentsOf: spurious.map { "\(name):\($0)" })
        }
        return score
    }

    /// Prints a comparison table. Evaluation output is the deliverable here,
    /// so it goes to the test log rather than being asserted away.
    static func report(_ scores: [Score]) {
        let header = "candidate".padded(30) + "recall".padded(16) + "prec".padded(8)
            + "FP".padded(5) + categories.map { String($0.prefix(4)).padded(7) }.joined()
        print("\n" + header)
        print(String(repeating: "-", count: header.count))
        for score in scores {
            let cats = categories.map {
                String(format: "%4.0f%%  ", score.recall(for: $0) * 100)
            }.joined()
            let recall = "\(score.found)/\(score.expected) (\(String(format: "%.1f", score.recall * 100))%)"
            print(score.label.padded(30)
                  + recall.padded(16)
                  + String(format: "%.1f%%", score.precision * 100).padded(8)
                  + "\(score.falsePositives)".padded(5)
                  + cats)
        }
        print("")
    }
}

private final class BundleToken {}

extension String {
    func padded(_ width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
}
