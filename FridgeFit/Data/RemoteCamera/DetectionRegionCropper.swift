//
//  DetectionRegionCropper.swift
//  FridgeFit
//

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// Cuts the regions YOLO found out of a frame, so each can be classified on
/// its own.
///
/// This is what makes crop-based classification *spatial*. Full-image
/// classification says "there is an orange somewhere"; classifying the
/// contents of a specific box says "this box contains an orange", which is
/// the only form in which a classification may be attached to a rectangle.
///
/// ## Coordinate conventions
///
/// `DetectedObject.boundingBox` is normalised to the **oriented** frame in
/// **Vision** space: origin bottom-left, y growing upwards. `CGImage`
/// cropping is in pixels with the origin top-left. Getting that flip wrong
/// produces crops that are vertically mirrored about the frame centre - which
/// still *look* like plausible food crops, so it would not be obvious from
/// the results. `DetectionRegionCropperTests` pins it down with an asymmetric
/// test image.
nonisolated struct DetectionRegionCropper: Sendable {

    nonisolated struct Configuration: Sendable {
        /// Fraction of the box's size added on every side before cropping.
        ///
        /// A classifier trained on photographs does better with some context
        /// than with an object cropped flush to its own edge. 0.10 is a
        /// compromise: enough context to help, little enough that a
        /// neighbouring item does not dominate the crop.
        var margin: CGFloat = 0.10
        /// Crops smaller than this on either side are skipped. A 12-pixel
        /// sliver carries no classifiable detail and costs a Vision request.
        var minimumPixelSize: CGFloat = 32
        /// Most crops to produce per frame, largest box first. Bounds the
        /// work a crowded frame can create.
        var maximumCrops: Int = 8

        static let `default` = Configuration()
    }

    /// One cropped region, paired with the detection it came from.
    ///
    /// Generic over the region type so the same cropper serves raw
    /// `DetectedObject`s and normalised `DetectedIngredient`s. The live
    /// pipeline crops the *normalised* list, so decoys and sub-threshold
    /// boxes never cost a Vision request.
    nonisolated struct Crop<Region: DetectedRegion>: Sendable {
        let image: CGImage
        /// The detection whose box produced this crop. Carried so a
        /// classification of the crop can be compared against what the
        /// detector said about the same region.
        let region: Region
    }

    let configuration: Configuration
    private let context: CIContext

    init(configuration: Configuration = .default, context: CIContext = CIContext(options: nil)) {
        self.configuration = configuration
        self.context = context
    }

    /// Renders the frame upright once, then cuts every requested box out of it.
    ///
    /// The frame is converted a single time rather than per box: the
    /// conversion is the expensive part, and a crowded frame would otherwise
    /// pay for it eight times.
    func crops<Region: DetectedRegion>(
        from pixelBuffer: CVPixelBuffer,
        regions: [Region],
        orientation: CGImagePropertyOrientation
    ) -> [Crop<Region>] {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return [] }
        return crops(from: cgImage, regions: regions)
    }

    /// Cuts boxes out of an already-upright image.
    func crops<Region: DetectedRegion>(
        from image: CGImage,
        regions: [Region]
    ) -> [Crop<Region>] {
        let size = CGSize(width: image.width, height: image.height)
        guard size.width > 0, size.height > 0 else { return [] }

        return regions
            // Largest first: if the cap bites, the biggest objects are the
            // ones most likely to be classifiable at all.
            .sorted { $0.boundingBox.area > $1.boundingBox.area }
            .prefix(configuration.maximumCrops)
            .compactMap { region in
                guard let rect = pixelRect(for: region.boundingBox, in: size),
                      let cropped = image.cropping(to: rect)
                else { return nil }
                return Crop(image: cropped, region: region)
            }
    }

    /// Normalised Vision-space box to a pixel rect in the upright image.
    ///
    /// Exposed for testing: the y-flip here is the part worth pinning down.
    func pixelRect(for boundingBox: CGRect, in size: CGSize) -> CGRect? {
        guard size.width > 0, size.height > 0,
              boundingBox.width > 0, boundingBox.height > 0 else { return nil }

        let margined = boundingBox.insetBy(
            dx: -boundingBox.width * configuration.margin,
            dy: -boundingBox.height * configuration.margin
        )

        // Vision y is measured from the bottom; CGImage from the top.
        let flippedY = 1 - margined.maxY
        var rect = CGRect(
            x: margined.minX * size.width,
            y: flippedY * size.height,
            width: margined.width * size.width,
            height: margined.height * size.height
        )

        // The margin can push the rect past the frame; clamp rather than
        // discard, since a box against the edge is perfectly normal.
        rect = rect.intersection(CGRect(origin: .zero, size: size))
        guard !rect.isNull,
              rect.width >= configuration.minimumPixelSize,
              rect.height >= configuration.minimumPixelSize
        else { return nil }

        return rect.integral
    }
}

/// Anything with an identity and a normalised Vision-space box.
///
/// Lets one cropper serve both the raw detector output and the normalised
/// ingredient list without either type knowing about cropping.
nonisolated protocol DetectedRegion: Identifiable, Sendable where ID == UUID {
    var boundingBox: CGRect { get }
}

extension DetectedObject: DetectedRegion {}
extension DetectedIngredient: DetectedRegion {}

nonisolated extension CGRect {
    var area: CGFloat { width * height }
}
