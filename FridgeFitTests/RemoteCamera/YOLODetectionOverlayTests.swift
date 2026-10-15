//
//  YOLODetectionOverlayTests.swift
//  FridgeFitTests
//

import SwiftUI
import UIKit
import XCTest
@testable import FridgeFit

/// Renders the overlay and inspects the pixels.
///
/// `YOLODetectionGeometryTests` proves the arithmetic; this proves the view
/// actually draws where the arithmetic says it should. Between them they
/// cover the acceptance criterion that boxes line up with what is on screen -
/// which is otherwise only checkable by eye on a device.
///
/// `ImageRenderer` is fine here: the overlay is shapes and text, with none of
/// the `NavigationStack`/`List` content `ImageRenderer` refuses to draw.
@MainActor
final class YOLODetectionOverlayTests: XCTestCase {

    private let viewSize = CGSize(width: 360, height: 480)

    private func render(
        _ detections: IngredientDetectionFrame,
        size: CGSize? = nil
    ) throws -> UIImage {
        let canvas = size ?? viewSize
        let renderer = ImageRenderer(
            content: ZStack {
                Color.black
                YOLODetectionOverlay(detections: detections)
            }
            .frame(width: canvas.width, height: canvas.height)
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage, "overlay produced no image")
    }

    /// Whether any pixel in `rect` is predominantly green - the box stroke
    /// and label colour.
    private func containsGreen(_ image: UIImage, in rect: CGRect) throws -> Bool {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return false }

        for y in Int(clipped.minY)..<Int(clipped.maxY) {
            for x in Int(clipped.minX)..<Int(clipped.maxX) {
                let offset = (y * width + x) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                // Green stroke on black: green clearly dominant.
                if green > 90 && green > red + 40 && green > blue + 40 { return true }
            }
        }
        return false
    }

    private func detection(
        _ box: CGRect,
        label: String = "banana",
        sourceSize: CGSize
    ) -> IngredientDetectionFrame {
        IngredientDetectionFrame(
            ingredients: [ingredient(label, box)],
            sourceSize: sourceSize,
            source: .ingredientDetector
        )
    }

    /// A confident ingredient, so the overlay draws a solid green box - the
    /// colour the pixel assertions look for.
    private func ingredient(_ name: String, _ box: CGRect) -> DetectedIngredient {
        DetectedIngredient(
            ingredientId: name, displayName: name.capitalized, category: .fruit,
            confidence: 0.9, boundingBox: box, source: .ingredientDetector,
            reviewReason: nil, rawTerm: name
        )
    }

    // MARK: - Placement

    /// A box drawn where the geometry says, and nowhere else.
    func test_aBoxIsDrawnAtTheComputedPosition() throws {
        // Square source in a 360x480 view: aspect-fill scales to cover the
        // height, so the sides are cropped.
        let sourceSize = CGSize(width: 480, height: 480)
        let box = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        let expected = try XCTUnwrap(
            DetectionGeometry.rect(for: box, sourceSize: sourceSize, viewSize: viewSize)
        )

        let image = try render(detection(box, sourceSize: sourceSize))

        // The stroke lies on the rect's edge; sample a band around the
        // left edge, away from the corners.
        let leftEdge = CGRect(
            x: expected.minX - 3, y: expected.midY - 10,
            width: 7, height: 20
        )
        XCTAssertTrue(try containsGreen(image, in: leftEdge), "no box edge at the computed position")
    }

    func test_nothingIsDrawnFarFromTheBox() throws {
        let sourceSize = CGSize(width: 480, height: 480)
        // Bottom-left in Vision terms, so the box is in the lower-left of the
        // view after the y flip.
        let box = CGRect(x: 0.05, y: 0.05, width: 0.2, height: 0.2)

        let image = try render(detection(box, sourceSize: sourceSize))

        // The diagonally opposite corner must be untouched.
        let oppositeCorner = CGRect(x: viewSize.width - 60, y: 0, width: 60, height: 60)
        XCTAssertFalse(
            try containsGreen(image, in: oppositeCorner),
            "something was drawn where no detection is"
        )
    }

    /// The y-flip, visually: a box at the bottom in Vision's coordinates must
    /// appear at the bottom of the view, not the top.
    func test_theVerticalAxisIsNotMirrored() throws {
        let sourceSize = CGSize(width: 360, height: 480)
        // Vision y near 0 = bottom of the image.
        let bottomBox = CGRect(x: 0.4, y: 0.02, width: 0.2, height: 0.12)

        let image = try render(detection(bottomBox, sourceSize: sourceSize))

        let lowerBand = CGRect(x: 0, y: viewSize.height * 0.75, width: viewSize.width, height: viewSize.height * 0.25)
        let upperBand = CGRect(x: 0, y: 0, width: viewSize.width, height: viewSize.height * 0.25)
        XCTAssertTrue(try containsGreen(image, in: lowerBand), "should be drawn near the bottom")
        XCTAssertFalse(try containsGreen(image, in: upperBand), "must not be mirrored to the top")
    }

    /// The horizontal axis must not be mirrored either - that is what a
    /// front-facing-camera mirroring bug would look like.
    func test_theHorizontalAxisIsNotMirrored() throws {
        let sourceSize = CGSize(width: 360, height: 480)
        let leftBox = CGRect(x: 0.02, y: 0.4, width: 0.2, height: 0.2)

        let image = try render(detection(leftBox, sourceSize: sourceSize))

        let leftBand = CGRect(x: 0, y: 0, width: viewSize.width * 0.3, height: viewSize.height)
        let rightBand = CGRect(x: viewSize.width * 0.7, y: 0, width: viewSize.width * 0.3, height: viewSize.height)
        XCTAssertTrue(try containsGreen(image, in: leftBand), "should be drawn on the left")
        XCTAssertFalse(try containsGreen(image, in: rightBand), "must not be mirrored to the right")
    }

    /// Portrait video in this view is cropped top and bottom. A centred
    /// object must still land centred.
    func test_aCentredObjectInCroppedPortraitVideoIsDrawnCentred() throws {
        let sourceSize = CGSize(width: 720, height: 1280)
        let box = CGRect(x: 0.42, y: 0.46, width: 0.16, height: 0.08)

        let image = try render(detection(box, sourceSize: sourceSize))

        let centre = CGRect(x: viewSize.width / 2 - 40, y: viewSize.height / 2 - 30, width: 80, height: 60)
        XCTAssertTrue(try containsGreen(image, in: centre), "a centred object should be drawn centred")
    }

    func test_landscapeVideoIsHandled() throws {
        let sourceSize = CGSize(width: 1280, height: 720)
        let box = CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)

        let image = try render(detection(box, sourceSize: sourceSize))

        let centre = CGRect(x: viewSize.width / 2 - 40, y: viewSize.height / 2 - 40, width: 80, height: 80)
        XCTAssertTrue(try containsGreen(image, in: centre))
    }

    // MARK: - Empty and degenerate states

    func test_anEmptyResultDrawsNothing() throws {
        let image = try render(IngredientDetectionFrame.empty)

        XCTAssertFalse(
            try containsGreen(image, in: CGRect(origin: .zero, size: viewSize)),
            "nothing should be drawn when there are no detections"
        )
    }

    func test_aResultWithNoSourceSizeDrawsNothing() throws {
        // Defensive: a frame whose geometry never arrived must not be mapped
        // against a zero size.
        let frame = IngredientDetectionFrame(
            ingredients: [ingredient("banana", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))],
            sourceSize: .zero,
            source: .ingredientDetector
        )

        let image = try render(frame)

        XCTAssertFalse(try containsGreen(image, in: CGRect(origin: .zero, size: viewSize)))
    }

    func test_multipleDetectionsAreAllDrawn() throws {
        let sourceSize = CGSize(width: 360, height: 480)
        let frame = IngredientDetectionFrame(
            ingredients: [
                ingredient("banana", CGRect(x: 0.05, y: 0.6, width: 0.2, height: 0.2)),
                ingredient("apple", CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.2)),
            ],
            sourceSize: sourceSize,
            source: .ingredientDetector
        )

        let image = try render(frame)

        let upperLeft = CGRect(x: 0, y: 0, width: viewSize.width * 0.4, height: viewSize.height * 0.5)
        let lowerRight = CGRect(x: viewSize.width * 0.6, y: viewSize.height * 0.5,
                                width: viewSize.width * 0.4, height: viewSize.height * 0.5)
        XCTAssertTrue(try containsGreen(image, in: upperLeft), "first box missing")
        XCTAssertTrue(try containsGreen(image, in: lowerRight), "second box missing")
    }
}
