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
nonisolated final class RecipeThumbnailCache {
    private let cache = NSCache<NSUUID, UIImage>()

    init(countLimit: Int = 100) {
        cache.countLimit = countLimit
    }

    func image(for id: UUID) -> UIImage? {
        cache.object(forKey: id as NSUUID)
    }

    func insert(_ image: UIImage, for id: UUID) {
        cache.setObject(image, forKey: id as NSUUID)
    }

    func remove(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }
}

/// Turns stored photo bytes into display-ready images, off the main thread.
///
/// Uses ImageIO's thumbnail API, which downsamples while decoding and
/// returns an already-decoded bitmap (`kCGImageSourceShouldCacheImmediately`).
/// So SwiftUI only draws a ready image - no `UIImage(data:)` and no lazy
/// first-draw decode in a view body.
nonisolated enum RecipeThumbnailDecoder {
    /// Stored photos are at most 800px (see `URLSessionRecipeImageDownloader`),
    /// which also covers the detail hero.
    static let maxPixelSize = 800

    static func thumbnail(from data: Data, maxPixelSize limit: Int = RecipeThumbnailDecoder.maxPixelSize) -> UIImage? {
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

    /// Decodes every entry concurrently in child tasks, which run on the
    /// global executor rather than the caller's actor. Undecodable entries
    /// are dropped.
    static func thumbnails(from data: [UUID: Data]) async -> [UUID: UIImage] {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for (id, bytes) in data {
                group.addTask { (id, thumbnail(from: bytes)) }
            }
            var result: [UUID: UIImage] = [:]
            for await (id, image) in group {
                if let image { result[id] = image }
            }
            return result
        }
    }
}
