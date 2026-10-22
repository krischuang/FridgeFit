//
//  ReceiptImageFingerprintTests.swift
//  FridgeFitTests
//

import CoreGraphics
import ImageIO
import XCTest
@testable import FridgeFit

/// The cache is only as safe as this fingerprint. These tests are split
/// between the two ways it can fail: refusing to recognise the demo receipt
/// (a slow demo), and recognising something that is not the demo receipt
/// (wrong data presented as a verified result). The second is the one that
/// matters.
final class ReceiptImageFingerprintTests: XCTestCase {

    // MARK: - The same picture matches

    func testSamePixelsProduceTheSameFingerprint() {
        let first = ReceiptImageFixtures.demoLikeReceipt()
        let second = ReceiptImageFixtures.demoLikeReceipt()

        XCTAssertEqual(ReceiptImageFingerprint.make(of: first), ReceiptImageFingerprint.make(of: second))
    }

    func testFingerprintSurvivesAPNGRoundTrip() throws {
        let original = ReceiptImageFixtures.demoLikeReceipt()
        let decoded = try XCTUnwrap(ReceiptImageFixtures.pngRoundTrip(original))

        XCTAssertEqual(
            ReceiptImageFingerprint.make(of: original),
            ReceiptImageFingerprint.make(of: decoded),
            "Encoding to PNG and back must not change the picture's identity."
        )
    }

    /// The property the spec calls "harmless metadata changes": the file's
    /// bytes differ, the picture does not.
    func testHarmlessMetadataChangeDoesNotChangeTheFingerprint() throws {
        let original = ReceiptImageFixtures.demoLikeReceipt()

        let plainData = try XCTUnwrap(ReceiptImageFixtures.pngData(original))
        let annotatedData = try XCTUnwrap(ReceiptImageFixtures.pngDataWithExtraMetadata(original))
        XCTAssertNotEqual(plainData, annotatedData, "Fixture precondition: the stored bytes should differ.")

        let plain = try XCTUnwrap(ReceiptImageFixtures.decode(plainData))
        let annotated = try XCTUnwrap(ReceiptImageFixtures.decode(annotatedData))

        XCTAssertEqual(
            ReceiptImageFingerprint.make(of: plain),
            ReceiptImageFingerprint.make(of: annotated),
            "A file SHA-256 would miss here; a canonical pixel fingerprint must not."
        )
    }

    /// A fingerprint has no filename input at all, so this is really a
    /// statement about the API's shape - there is nowhere for a name to
    /// enter. The test pins that: two differently-named files of the same
    /// picture agree, and the *same* name over different pictures does not.
    func testFingerprintDoesNotDependOnFilename() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let demo = ReceiptImageFixtures.demoLikeReceipt()
        let demoData = try XCTUnwrap(ReceiptImageFixtures.pngData(demo))
        let otherData = try XCTUnwrap(ReceiptImageFixtures.pngData(ReceiptImageFixtures.visuallySimilarDifferentReceipt()))

        let asColesName = directory.appendingPathComponent("Coles Receipt on White Background.png")
        let asRandomName = directory.appendingPathComponent("IMG_4821.png")
        let impostorWithColesName = directory.appendingPathComponent("Coles Receipt on White Background(1).png")

        try demoData.write(to: asColesName)
        try demoData.write(to: asRandomName)
        try otherData.write(to: impostorWithColesName)

        let fromColesName = try fingerprint(ofFileAt: asColesName)
        let fromRandomName = try fingerprint(ofFileAt: asRandomName)
        let fromImpostor = try fingerprint(ofFileAt: impostorWithColesName)

        XCTAssertEqual(fromColesName, fromRandomName, "The name must not matter when the pixels agree.")
        XCTAssertNotEqual(
            fromColesName,
            fromImpostor,
            "A different receipt must not inherit the demo's identity by being named like it."
        )
    }

    /// The same photograph written sideways with an EXIF tag, as a camera
    /// does, must still be the same photograph.
    func testOrientationIsNormalised() throws {
        let upright = ReceiptImageFixtures.demoLikeReceipt()
        let expected = try XCTUnwrap(ReceiptImageFingerprint.make(of: upright, orientation: .up))

        let orientations: [CGImagePropertyOrientation] = [
            .up, .upMirrored, .down, .downMirrored,
            .left, .leftMirrored, .right, .rightMirrored
        ]

        for orientation in orientations {
            let stored = ReceiptImageFixtures.reoriented(upright, as: orientation)
            let actual = ReceiptImageFingerprint.make(of: stored, orientation: orientation)
            XCTAssertEqual(actual, expected, "Orientation \(orientation) should normalise to the upright picture.")
        }
    }

    /// Canonicalisation has to survive the source being stored in a
    /// different memory layout - an opaque image with no alpha channel is
    /// the same picture as one with alpha pinned to 255.
    func testAlphaLayoutDoesNotChangeTheFingerprint() {
        let premultiplied = ReceiptImageFixtures.demoLikeReceipt()
        let opaque = ReceiptImageFixtures.image(
            width: premultiplied.width,
            height: premultiplied.height,
            alphaInfo: .noneSkipLast
        ) { x, y in
            let value = UInt8((x &* 5 &+ y &* 3) % 256)
            return (value, value &+ 90, value &+ 180)
        }

        XCTAssertEqual(
            ReceiptImageFingerprint.make(of: premultiplied),
            ReceiptImageFingerprint.make(of: opaque)
        )
    }

    // MARK: - A different picture must not match

    func testADifferentReceiptDoesNotMatch() {
        let demo = ReceiptImageFixtures.demoLikeReceipt()
        let other = ReceiptImageFixtures.visuallySimilarDifferentReceipt()

        XCTAssertNotEqual(
            ReceiptImageFingerprint.make(of: demo),
            ReceiptImageFingerprint.make(of: other),
            "A visually similar receipt must never reuse the demo's cached result."
        )
    }

    /// The headline safety property: matching is exact, not perceptual.
    func testASingleChangedPixelDoesNotMatch() {
        let demo = ReceiptImageFixtures.demoLikeReceipt()
        let edited = ReceiptImageFixtures.demoReceiptWithOnePixelChanged()

        XCTAssertNotEqual(
            ReceiptImageFingerprint.make(of: demo),
            ReceiptImageFingerprint.make(of: edited),
            "Changed receipt contents must produce a different identity."
        )
    }

    func testACroppedReceiptDoesNotMatch() {
        let demo = ReceiptImageFixtures.demoLikeReceipt()
        let cropped = demo.cropping(to: CGRect(x: 0, y: 0, width: demo.width, height: demo.height - 4))

        XCTAssertNotNil(cropped)
        XCTAssertNotEqual(
            ReceiptImageFingerprint.make(of: demo),
            cropped.flatMap { ReceiptImageFingerprint.make(of: $0) },
            "A crop of the demo receipt is a different image and must miss the cache."
        )
    }

    /// Dimensions are hashed alongside the pixels, so two images cannot
    /// collide by sharing a byte sequence at different shapes.
    func testDimensionsArePartOfTheIdentity() {
        let wide = ReceiptImageFixtures.image(width: 16, height: 4) { _, _ in (7, 7, 7) }
        let tall = ReceiptImageFixtures.image(width: 4, height: 16) { _, _ in (7, 7, 7) }

        XCTAssertNotEqual(
            ReceiptImageFingerprint.make(of: wide),
            ReceiptImageFingerprint.make(of: tall)
        )
    }

    // MARK: - Shape

    func testFingerprintIsVersionTaggedHex() throws {
        let value = try XCTUnwrap(ReceiptImageFingerprint.make(of: ReceiptImageFixtures.demoLikeReceipt())).value
        let parts = value.split(separator: ":")

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.first, "v\(ReceiptImageFingerprint.algorithmVersion)")
        XCTAssertEqual(parts.last?.count, 64, "SHA-256 renders as 64 hex characters.")
        XCTAssertTrue(parts.last?.allSatisfy(\.isHexDigit) == true)
    }

    func testFingerprintSurvivesACodableRoundTrip() throws {
        let original = try XCTUnwrap(ReceiptImageFingerprint.make(of: ReceiptImageFixtures.demoLikeReceipt()))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReceiptImageFingerprint.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Helpers

    private func fingerprint(ofFileAt url: URL) throws -> ReceiptImageFingerprint {
        let data = try Data(contentsOf: url)
        let image = try XCTUnwrap(ReceiptImageFixtures.decode(data))
        return try XCTUnwrap(ReceiptImageFingerprint.make(of: image))
    }
}
