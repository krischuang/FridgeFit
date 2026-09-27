//
//  TestImage.swift
//  FridgeFitTests
//

import CoreGraphics
import UIKit

/// A throwaway image for driving the scan flow in unit tests.
///
/// The pixels are irrelevant - `MockIngredientRecognitionService` never looks
/// at them. It exists so the tests exercise the real
/// `UIImage` -> `CGImage` path the view model takes, instead of bypassing it.
enum TestImage {
    static func makeUIImage(size: CGSize = CGSize(width: 4, height: 4)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func make(size: CGSize = CGSize(width: 4, height: 4)) -> CGImage {
        // Force-unwrapped deliberately: a renderer-produced image always has
        // a backing CGImage, and a test that can't build its fixture should
        // fail loudly rather than silently skip.
        makeUIImage(size: size).cgImage!
    }
}
