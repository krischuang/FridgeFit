import Foundation
import Vision
import CoreGraphics
import ImageIO

/// Runs Apple's built-in offline image classifier (`VNClassifyImageRequest`)
/// and OCR (`VNRecognizeTextRequest`) over a directory of images, emitting
/// JSON for scoring against the shared annotation set.
///
/// Latency is wall-clock per request on this machine, measured after a warm-up
/// pass so the first request's model load does not pollute the numbers. These
/// are macOS figures; iPhone will differ.

struct Detection: Encodable {
    let identifier: String
    let confidence: Double
}

struct ImageResult: Encodable {
    let classifications: [Detection]
    let ocrLines: [String]
    let classifyMs: Double
    let ocrMs: Double
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: classify <image-dir>\n".utf8))
    exit(2)
}
let dir = CommandLine.arguments[1]
let files = try FileManager.default.contentsOfDirectory(atPath: dir)
    .filter { ["jpg", "jpeg", "png"].contains(($0 as NSString).pathExtension.lowercased()) }
    .sorted()

func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func elapsedMs(_ body: () throws -> Void) rethrows -> Double {
    let start = Date()
    try body()
    return Date().timeIntervalSince(start) * 1000
}

var results: [String: ImageResult] = [:]
var warmed = false

for file in files {
    let name = (file as NSString).deletingPathExtension
    guard let image = load("\(dir)/\(file)") else { continue }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])

    if !warmed {
        try? handler.perform([VNClassifyImageRequest()])
        try? handler.perform([VNRecognizeTextRequest()])
        warmed = true
    }

    let classify = VNClassifyImageRequest()
    let classifyMs = try elapsedMs { try handler.perform([classify]) }

    // Apple's documented filtering: keep identifiers the model is calibrated
    // to report at >= 50% precision, rather than applying a flat confidence
    // cut across a hierarchical multi-label taxonomy.
    let kept = (classify.results ?? [])
        .filter { $0.hasMinimumRecall(0.0, forPrecision: 0.5) }
        .prefix(25)
        .map { Detection(identifier: $0.identifier, confidence: Double($0.confidence)) }

    let text = VNRecognizeTextRequest()
    text.recognitionLevel = .accurate
    text.usesLanguageCorrection = true
    let ocrMs = try elapsedMs { try handler.perform([text]) }
    let lines = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }

    results[name] = ImageResult(
        classifications: kept, ocrLines: lines,
        classifyMs: classifyMs, ocrMs: ocrMs
    )
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(results))
