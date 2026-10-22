//
//  URLSessionRecipeImageDownloader.swift
//  FridgeFit
//

import Foundation
import UIKit

/// Downloads a recipe photo and shrinks it before it is stored.
///
/// Rules:
/// - Only `https` URLs; anything else returns `nil`.
/// - The response must be 2xx with an `image/*` content type, and no
///   larger than `maxDownloadBytes`.
/// - The image is redrawn so its longest side is at most `maxDimension`
///   points (at scale 1) and re-encoded as JPEG, so a saved photo costs
///   tens of kilobytes rather than the original's size.
///
/// Spoonacular photos come from its image CDN (`img.spoonacular.com`), which
/// is not an API endpoint, so this spends no API quota.
nonisolated final class URLSessionRecipeImageDownloader: RecipeImageDownloading {
    static let maxDownloadBytes = 5 * 1024 * 1024
    static let maxDimension: CGFloat = 800
    static let jpegQuality: CGFloat = 0.8
    private static let timeout: TimeInterval = 15

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func imageData(from url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https" else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout

        guard
            let result = try? await session.data(for: request),
            let http = result.1 as? HTTPURLResponse,
            (200 ..< 300).contains(http.statusCode),
            http.mimeType?.lowercased().hasPrefix("image/") == true,
            !result.0.isEmpty,
            result.0.count <= Self.maxDownloadBytes
        else { return nil }

        return Self.downscaledJPEG(from: result.0)
    }

    /// `nil` when `data` isn't a decodable image.
    static func downscaledJPEG(from data: Data, maxDimension limit: CGFloat = URLSessionRecipeImageDownloader.maxDimension) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }

        let longest = max(image.size.width, image.size.height)
        let scale = min(1, limit / longest)
        let target = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: URLSessionRecipeImageDownloader.jpegQuality)
    }
}
