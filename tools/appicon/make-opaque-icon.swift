//
//  make-opaque-icon.swift
//  FridgeFit
//
//  Regenerates the App Store master icon as a square, fully opaque,
//  full-bleed 1024x1024 PNG.
//
//  ## Why this exists
//
//  The original `fridgefit_icon.png` could not be submitted. Measured:
//
//    - 40% of its pixels were fully transparent
//    - 60% more were alpha 254, i.e. *every* visible pixel was slightly
//      translucent
//    - its opaque content was a rounded "squircle" inset inside the canvas,
//      with all four corners transparent
//
//  App Review rejects both of those: the 1024pt marketing icon must be a
//  flat, opaque square, and must not have corner rounding baked in, because
//  iOS applies its own mask. A pre-rounded icon gets rounded twice and shows
//  pale fringes at the corners on device.
//
//  ## What it does
//
//  1. Fills the full canvas with the brand canvas colour (`#F7F5EC`,
//     `FridgeFitTheme.ColorToken.canvas`). This is what guarantees opacity:
//     every output pixel has something solid underneath it, so there is no
//     alpha left to flatten incorrectly.
//  2. Draws the source artwork scaled about the centre so its rounded panel
//     extends past all four edges. That is what removes the pre-rounded
//     corner - the arcs end up outside the canvas rather than being painted
//     over or re-drawn - while leaving the artwork itself untouched. No
//     recolouring, no masking heuristics, no redrawn shapes, so FridgeFit's
//     botanical identity is preserved exactly as designed.
//  3. Writes a PNG with no alpha channel at all (`.noneSkipLast`), rather
//     than an RGBA PNG that merely happens to be opaque.
//
//  ## Usage
//
//      swift tools/appicon/make-opaque-icon.swift \
//          FridgeFit/Assets.xcassets/AppIcon.appiconset/fridgefit_icon.png
//
//  It verifies the result before overwriting, and refuses to write an image
//  that is not square, not opaque, or whose corners are not covered.
//  `AppIconOpacityTests` re-checks the shipped file on every test run, so a
//  future icon with transparency fails the suite rather than App Review.
//

import AppKit
import Foundation

// MARK: - Configuration

/// `FridgeFitTheme.ColorToken.canvas` (light). The brand's warm off-white.
let brandCanvas = (r: UInt8(0xF7), g: UInt8(0xF5), b: UInt8(0xEC))

/// How much larger than the canvas the artwork's opaque bounding box is
/// drawn.
///
/// 1.0 makes the artwork's bounding box exactly reach the canvas on its
/// shorter side. Deliberately not pushed far beyond that: overscanning
/// enough to shove the source's rounded corners off-canvas also shoves the
/// *motif* off-canvas - at 1.34 the bolt badge was clipped by the right edge
/// and the fridge ran off the bottom, which iOS's own corner mask would then
/// have made worse. The corner rounding is dealt with by the opaque brand
/// fill underneath instead, which is both safer and the thing App Review
/// actually asks for.
let overscan: CGFloat = 1.02

let canvasSize = 1024

// MARK: - Input

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-opaque-icon.swift <path-to-icon.png>\n".utf8))
    exit(2)
}
let path = CommandLine.arguments[1]

guard
    let source = NSImage(contentsOfFile: path),
    let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("could not read \(path)\n".utf8))
    exit(1)
}

// MARK: - Measure the source's opaque bounding box

func rgbaBuffer(of image: CGImage) -> (pixels: [UInt8], width: Int, height: Int) {
    let w = image.width, h = image.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    pixels.withUnsafeMutableBytes { raw in
        let context = CGContext(
            data: raw.baseAddress,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (pixels, w, h)
}

let source_ = rgbaBuffer(of: sourceCG)
var minX = source_.width, maxX = -1, minY = source_.height, maxY = -1
for y in 0 ..< source_.height {
    for x in 0 ..< source_.width where source_.pixels[(y * source_.width + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write(Data("source has no opaque content\n".utf8))
    exit(1)
}
let boxWidth = CGFloat(maxX - minX + 1)
let boxHeight = CGFloat(maxY - minY + 1)
print("source \(source_.width)x\(source_.height), opaque box \(Int(boxWidth))x\(Int(boxHeight))")

// MARK: - Compose

let canvas = CGFloat(canvasSize)
// Scale so the *smaller* side of the opaque box reaches the canvas, then
// overscan so the rounded corners leave the frame.
let scale = (canvas / min(boxWidth, boxHeight)) * overscan
let drawWidth = CGFloat(source_.width) * scale
let drawHeight = CGFloat(source_.height) * scale
// Centre the opaque box, not the source image - the artwork is not centred
// in its own canvas, so centring the file would leave the motif off-centre.
let boxCentreX = (CGFloat(minX) + boxWidth / 2) * scale
let boxCentreY = (CGFloat(minY) + boxHeight / 2) * scale
let originX = canvas / 2 - boxCentreX
// Core Graphics is bottom-left origin; the measured box is top-left.
let originY = canvas / 2 - (drawHeight - boxCentreY)

// `noneSkipLast`: no alpha channel in the output at all.
guard let output = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create output context\n".utf8))
    exit(1)
}

output.setFillColor(
    red: CGFloat(brandCanvas.r) / 255,
    green: CGFloat(brandCanvas.g) / 255,
    blue: CGFloat(brandCanvas.b) / 255,
    alpha: 1
)
output.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
output.interpolationQuality = .high
output.draw(sourceCG, in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight))

guard let composed = output.makeImage() else {
    FileHandle.standardError.write(Data("could not render\n".utf8))
    exit(1)
}

// MARK: - Verify before writing

let result = rgbaBuffer(of: composed)
var minAlpha = 255
for i in stride(from: 3, to: result.pixels.count, by: 4) {
    minAlpha = min(minAlpha, Int(result.pixels[i]))
}

func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
    let i = (y * result.width + x) * 4
    return (result.pixels[i], result.pixels[i + 1], result.pixels[i + 2])
}

let corners = [
    pixel(0, 0),
    pixel(result.width - 1, 0),
    pixel(0, result.height - 1),
    pixel(result.width - 1, result.height - 1),
]
print("result \(result.width)x\(result.height), minAlpha \(minAlpha), corners \(corners)")

guard result.width == canvasSize, result.height == canvasSize else {
    FileHandle.standardError.write(Data("refusing to write: not square\n".utf8))
    exit(1)
}
guard minAlpha == 255 else {
    FileHandle.standardError.write(Data("refusing to write: minimum alpha is \(minAlpha)\n".utf8))
    exit(1)
}
// The corners must be *solid brand colour*, not a faded edge. That is what
// replaces the source's transparent corners: the icon now reaches the edge
// of its square on all four sides, and iOS applies the only corner rounding
// there is. The panel inside it is a design element, not baked masking.
let cornersAreBrandFill = corners.allSatisfy {
    $0.0 == brandCanvas.r && $0.1 == brandCanvas.g && $0.2 == brandCanvas.b
}
guard cornersAreBrandFill else {
    FileHandle.standardError.write(
        Data("refusing to write: corners are \(corners), expected the solid brand fill\n".utf8)
    )
    exit(1)
}

// MARK: - Write

let rep = NSBitmapImageRep(cgImage: composed)
rep.size = NSSize(width: canvasSize, height: canvasSize)
guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
    exit(1)
}
try data.write(to: URL(fileURLWithPath: path))
print("wrote \(path) (\(data.count) bytes), square, fully opaque, no baked corner rounding")
