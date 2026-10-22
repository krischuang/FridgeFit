//
//  RecipeThumbnailCache.swift
//  FridgeFit
//

import Foundation
import ImageIO
import UIKit

/// Decoded thumbnails of saved-recipe photos, by recipe id.
///
/// Backed by `NSCache`, so the system can evict entries under memory
/// pressure; an evicted thumbnail is simply decoded again on the next load.
/// Thread-safe (`NSCache` is), so it can be shared freely.
///
/// ## Why a cost limit and not just a count
///
/// What is cached is a decoded bitmap, not the stored JPEG: a 400px thumbnail
/// is ~640 KB in memory where its JPEG is tens of kilobytes. A count limit
/// alone therefore says nothing about how much memory the cache may hold - at
/// 100 entries of hero-sized images it would be a quarter of a gigabyte. The
/// budget is expressed in bytes, and `countLimit` stays as a secondary bound.
nonisolated final class RecipeThumbnailCache {
    /// Memory budget for decoded list thumbnails: ~50 entries at
    /// `RecipeThumbnailDecoder.listPixelSize`, which is more saved recipes
    /// than a list shows between reloads.
    static let defaultTotalCostLimit = 32 * 1024 * 1024

    /// Decoded bitmaps here are 8-bit RGBA.
    private static let bytesPerPixel = 4

    private let cache = NSCache<NSUUID, UIImage>()

    init(countLimit: Int = 100, totalCostLimit: Int = RecipeThumbnailCache.defaultTotalCostLimit) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    /// The configured bounds, so tests can assert the budget rather than try
    /// to provoke an eviction - which `NSCache` makes no promises about.
    var countLimit: Int { cache.countLimit }
    var totalCostLimit: Int { cache.totalCostLimit }

    func image(for id: UUID) -> UIImage? {
        cache.object(forKey: id as NSUUID)
    }

    func insert(_ image: UIImage, for id: UUID) {
        cache.setObject(image, forKey: id as NSUUID, cost: Self.cost(of: image))
    }

    func remove(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }

    /// Bytes `image`'s decoded bitmap occupies.
    ///
    /// Measured from the backing `CGImage` where there is one - that is the
    /// actual allocation - and from `size * scale` otherwise. Never zero: an
    /// image too odd to measure still occupies an entry, and a zero cost would
    /// make it invisible to the byte budget forever.
    static func cost(of image: UIImage) -> Int {
        let pixelWidth: Int
        let pixelHeight: Int
        if let cgImage = image.cgImage {
            pixelWidth = cgImage.width
            pixelHeight = cgImage.height
        } else {
            pixelWidth = Int((image.size.width * image.scale).rounded())
            pixelHeight = Int((image.size.height * image.scale).rounded())
        }
        return max(1, max(0, pixelWidth) * max(0, pixelHeight) * bytesPerPixel)
    }
}

/// Turns stored photo bytes into display-ready images, off the main thread.
///
/// Uses ImageIO's thumbnail API, which downsamples while decoding and
/// returns an already-decoded bitmap (`kCGImageSourceShouldCacheImmediately`).
/// So SwiftUI only draws a ready image - no `UIImage(data:)` and no lazy
/// first-draw decode in a view body.
nonisolated enum RecipeThumbnailDecoder {
    /// Decoded size for list rows. `RecipeRow` and the catalogue cards draw
    /// their photo 132pt tall, so 400px covers a 3x screen with headroom -
    /// and costs a sixth of the memory of decoding the full stored image.
    static let listPixelSize = 400

    /// Decoded size for the detail hero, which draws 230pt tall and full
    /// width. Stored photos are at most 800px
    /// (see `URLSessionRecipeImageDownloader`), so this is the full stored
    /// size and loses nothing.
    static let heroPixelSize = 800

    /// How many photos may be decoded at the same time.
    ///
    /// Each in-flight decode holds a full decoded bitmap, so unbounded
    /// concurrency means a collection-sized memory spike on a cold load. Four
    /// keeps several cores busy without letting the peak scale with the
    /// number of saved recipes.
    static let maxConcurrentDecodes = 4

    static func thumbnail(from data: Data, maxPixelSize limit: Int = RecipeThumbnailDecoder.listPixelSize) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ] as [CFString: Any] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Decodes `data` in child tasks, which run on the global executor rather
    /// than the caller's actor, at most `maxConcurrent` at a time.
    ///
    /// The task group is kept to a sliding window of that width: each
    /// completed decode admits the next one, so peak memory is bounded by the
    /// window rather than by `data.count`, while several decodes still run in
    /// parallel. Undecodable entries are dropped.
    ///
    /// Cancellation is honoured both ways - a task that starts after
    /// cancellation skips its decode, and the loop stops admitting work - so
    /// leaving the screen does not pay for the rest of the collection.
    ///
    /// - Parameter decode: the decode step, injectable so tests can observe
    ///   how many run at once. Always `thumbnail(from:maxPixelSize:)` in the
    ///   app.
    static func thumbnails(
        from data: [UUID: Data],
        maxPixelSize limit: Int = RecipeThumbnailDecoder.listPixelSize,
        maxConcurrent: Int = RecipeThumbnailDecoder.maxConcurrentDecodes,
        decode: @escaping @Sendable (Data, Int) -> UIImage? = { thumbnail(from: $0, maxPixelSize: $1) }
    ) async -> [UUID: UIImage] {
        let entries = Array(data)
        guard !entries.isEmpty else { return [:] }
        let window = min(max(1, maxConcurrent), entries.count)

        return await withTaskGroup(of: (UUID, UIImage?).self) { group in
            var next = 0
            var result: [UUID: UIImage] = [:]
            result.reserveCapacity(entries.count)

            func admitNext() {
                let (id, bytes) = entries[next]
                next += 1
                group.addTask {
                    // A task admitted just before cancellation must not pay
                    // for a decode nobody will draw.
                    guard !Task.isCancelled else { return (id, nil) }
                    return (id, decode(bytes, limit))
                }
            }

            while next < window { admitNext() }

            while let (id, image) = await group.next() {
                if let image { result[id] = image }
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if next < entries.count { admitNext() }
            }
            return result
        }
    }
}
