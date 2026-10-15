//
//  main.swift
//  vision-eval swift harness
//
//  Runs the *actual app source files* over the shared evaluation set and
//  prints the same metric the Python harness uses.
//
//  Why this exists: `VNClassifyImageRequest` cannot run in the iOS simulator
//  ("Failed to create espresso context"), so the XCTest suite can only skip
//  the classifier tests. This harness builds the same files for Mac Catalyst,
//  where UIKit and a working Vision classifier are both available, so the
//  Swift pipeline is measured rather than assumed. See build.sh.
//
//  No app code is duplicated here - every recogniser type comes from
//  FridgeFit/. Only `Shim.swift` adds anything, and only one unrelated enum.

import CoreGraphics
import Foundation
import ImageIO
import UIKit
import Vision

// Line-buffered, so a crash mid-run does not swallow everything printed
// before it. Diagnostics are useless if they vanish with the process.
setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Scoring (same definition as evaluate_vocabulary.py)

struct Annotation: Decodable {
    let category: String
    let present: [String]
}

struct Score {
    let label: String
    var perCategory: [String: (expected: Int, found: Int, fp: Int)] = [:]
    var found = 0, expected = 0, falsePositives = 0
    var missed: [String] = [], spurious: [String] = []

    var recall: Double { expected > 0 ? Double(found) / Double(expected) : 0 }
    var precision: Double {
        found + falsePositives > 0 ? Double(found) / Double(found + falsePositives) : 0
    }
    func recall(for category: String) -> Double {
        guard let s = perCategory[category], s.expected > 0 else { return 0 }
        return Double(s.found) / Double(s.expected)
    }
}

let CATEGORIES = ["fruit", "vegetable", "meat", "seafood", "dairy", "pantry"]

func score(_ detected: [String: Set<String>],
           _ annotations: [String: Annotation],
           _ label: String) -> Score {
    var result = Score(label: label)
    for (name, annotation) in annotations {
        let expected = Set(annotation.present)
        let got = detected[name] ?? []
        let found = expected.intersection(got)
        let spurious = got.subtracting(expected)

        var stats = result.perCategory[annotation.category] ?? (0, 0, 0)
        stats.expected += expected.count
        stats.found += found.count
        stats.fp += spurious.count
        result.perCategory[annotation.category] = stats

        result.expected += expected.count
        result.found += found.count
        result.falsePositives += spurious.count
        result.missed += expected.subtracting(found).map { "\(name):\($0)" }
        result.spurious += spurious.map { "\(name):\($0)" }
    }
    return result
}

func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s + " " : s + String(repeating: " ", count: w - s.count)
}

func report(_ scores: [Score]) {
    let header = pad("candidate", 28) + pad("recall", 16) + pad("prec", 8) + pad("FP", 5)
        + CATEGORIES.map { pad(String($0.prefix(4)), 7) }.joined()
    print("\n" + header)
    print(String(repeating: "-", count: header.count))
    for s in scores {
        let cats = CATEGORIES.map { String(format: "%4.0f%%  ", s.recall(for: $0) * 100) }.joined()
        print(pad(s.label, 28)
              + pad("\(s.found)/\(s.expected) (\(String(format: "%.1f", s.recall * 100))%)", 16)
              + pad(String(format: "%.1f%%", s.precision * 100), 8)
              + pad("\(s.falsePositives)", 5) + cats)
    }
    print("")
}

// MARK: - Setup

let arguments = CommandLine.arguments
guard arguments.count > 2 else {
    FileHandle.standardError.write(Data("usage: harness <resources-dir> <images-dir> [annotations.json]\n".utf8))
    exit(2)
}
let resourcesPath = arguments[1]
let imagesPath = arguments[2]
let annotationsPath = arguments.count > 3
    ? arguments[3]
    : imagesPath + "/../annotations.json"

guard let bundle = Bundle(path: resourcesPath) else {
    FileHandle.standardError.write(Data("cannot open resources at \(resourcesPath)\n".utf8))
    exit(1)
}

let annotations = try JSONDecoder().decode(
    [String: Annotation].self,
    from: try Data(contentsOf: URL(fileURLWithPath: annotationsPath))
)

func loadImage(_ name: String) -> CGImage? {
    let url = URL(fileURLWithPath: "\(imagesPath)/\(name).jpg")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: bundle)
guard let detector = resolved.detector as? YOLOFoodDetectionService else {
    FileHandle.standardError.write(Data("expected a YOLOFoodDetectionService\n".utf8))
    exit(1)
}
let visionMap = try VisionIngredientMap.load(in: bundle)
let textReader = PackagedFoodTextReader(taxonomy: resolved.taxonomy, configuration: .matching)
let fusion = DetectionFusionService()

print("resources  : \(resourcesPath)")
print("vocabulary : \(resolved.taxonomy.definitions.count) terms, \(resolved.taxonomy.ingredientCount) ingredients")
print("vision map : \(visionMap.entries.count) identifiers -> \(visionMap.ingredientCount) ingredients")

func classifier(_ threshold: Float, cap: Int = 50) -> AppleVisionIngredientClassifier {
    var configuration = AppleVisionIngredientClassifier.Configuration.default
    configuration.confidenceThreshold = threshold
    configuration.maximumIngredients = cap
    return AppleVisionIngredientClassifier(map: visionMap, configuration: configuration)
}

// MARK: - Explain mode
//
// `harness <resources> <images> <annotations> explain [name...]` dumps every
// stage separately for the named images, so a wrong label can be traced to
// the component that produced it rather than guessed at.

func fixed(_ value: Double, _ places: Int = 3) -> String {
    String(format: "%.\(places)f", value)
}

if arguments.count > 4, arguments[4] == "explain" {
    let wanted = arguments.count > 5 ? Array(arguments[5...]) : annotations.keys.sorted()
    let sceneAll = classifier(0.0, cap: 100)
    let cropAll = RegionIngredientClassifier(classifier: classifier(0.0, cap: 100))
    let textReaderMatching = PackagedFoodTextReader(
        taxonomy: resolved.taxonomy, configuration: .matching
    )

    for name in wanted {
        guard let image = loadImage(name) else { print("missing \(name)"); continue }
        print("\n================ \(name) ================")
        print("expected: \(annotations[name]?.present ?? [])")

        // 1. YOLO-World, raw terms before normalisation.
        let raw = try detector.detect(in: image)
        print("\n-- 1. YOLO-World raw (model terms, pre-normalisation) --")
        for object in raw.objects.sorted(by: { $0.confidence > $1.confidence }).prefix(12) {
            let box = object.boundingBox
            print("   " + pad(object.label, 26) + fixed(Double(object.confidence))
                  + "  box=(" + fixed(box.minX, 2) + ", " + fixed(box.minY, 2)
                  + ", " + fixed(box.width, 2) + ", " + fixed(box.height, 2) + ")")
        }
        if raw.objects.isEmpty { print("   (nothing)") }

        let normalised = resolved.normalizer.normalize(raw, source: resolved.source)
        print("\n-- 2. after IngredientNormalizer (what the app would show) --")
        for item in normalised.ingredients {
            let review = item.reviewReason.map { String(describing: $0) } ?? "none"
            print("   " + pad(item.ingredientId, 26) + fixed(Double(item.confidence))
                  + "  review=" + review)
        }
        if normalised.ingredients.isEmpty { print("   (nothing)") }

        // 3. Apple Vision, whole image, unfiltered.
        let scene = try sceneAll.classify(image, orientation: .up)
        print("\n-- 3. Apple Vision full-image (threshold 0, top 12) --")
        for item in scene.ingredients.prefix(12) {
            print("   " + pad(item.ingredientId, 26) + fixed(Double(item.confidence))
                  + "  (raw id: " + item.rawIdentifier + ")")
        }
        if !scene.rejectedFoodClaims.isEmpty {
            print("   rejected food claims: \(scene.rejectedFoodClaims)")
        }
        if scene.ingredients.isEmpty { print("   (nothing above 0)") }

        // 4. Apple Vision on each YOLO box.
        print("\n-- 4. Apple Vision crop-based (one per YOLO box) --")
        let outcome = cropAll.classifyRegions(in: image, regions: normalised.ingredients)
        if normalised.ingredients.isEmpty { print("   (no boxes to crop)") }
        for item in normalised.ingredients {
            let top = outcome.results[item.id]?.ingredients.first
            let answer = top.map { $0.ingredientId + " " + fixed(Double($0.confidence)) } ?? "nothing"
            print("   box '" + item.ingredientId + "' -> " + answer)
        }

        // 5. Fusion.
        let fused = fusion.fuse(
            detections: normalised, regionClassifications: outcome.results,
            sceneClassification: try classifier(0.30).classify(image, orientation: .up)
        )
        print("\n-- 5. DetectionFusionService (shipped config) --")
        for item in fused.all {
            let other = item.conflictingClaim.map { " (other said " + $0 + ")" } ?? ""
            print("   " + pad(item.ingredientId, 22)
                  + pad("tier=" + String(describing: item.tier), 20)
                  + item.sources.displayNames.joined(separator: "+") + other)
        }
        if fused.all.isEmpty { print("   (nothing)") }

        // 6. OCR.
        let reading = try textReaderMatching.read(image, orientation: .up)
        print("\n-- 6. OCR --")
        print("   \(reading.lines.count) lines, \(reading.nonLatinLines.count) non-Latin, "
              + "matches \(reading.matches.map(\.ingredientId))")
    }
    exit(0)
}

// MARK: - Confidence-band mode
//
// `harness <res> <img> <ann> bands` measures whether a *high* YOLO-World
// confidence is actually more trustworthy than a low one. The normaliser
// marks anything above `trustThreshold` (0.60) as needing no review; that
// number was never validated against outcomes.

if arguments.count > 4, arguments[4] == "bands" {
    struct Band { let lower: Float; let upper: Float; var right = 0; var wrong = 0 }
    var bands = [
        Band(lower: 0.40, upper: 0.50), Band(lower: 0.50, upper: 0.60),
        Band(lower: 0.60, upper: 0.70), Band(lower: 0.70, upper: 0.80),
        Band(lower: 0.80, upper: 1.01),
    ]

    for name in annotations.keys.sorted() {
        guard let image = loadImage(name) else { continue }
        let expected = Set(annotations[name]?.present ?? [])
        let raw = try detector.detect(in: image)
        let normalised = resolved.normalizer.normalize(raw, source: resolved.source)
        for item in normalised.ingredients {
            guard let index = bands.firstIndex(where: {
                item.confidence >= $0.lower && item.confidence < $0.upper
            }) else { continue }
            if expected.contains(item.ingredientId) { bands[index].right += 1 }
            else { bands[index].wrong += 1 }
        }
    }

    print("\nYOLO-World detection precision by confidence band")
    print("(a detection is 'right' when its ingredient is in the annotation)\n")
    print(pad("band", 14) + pad("right", 8) + pad("wrong", 8) + "precision")
    print(String(repeating: "-", count: 44))
    for band in bands {
        let total = band.right + band.wrong
        let precision = total > 0 ? Double(band.right) / Double(total) * 100 : 0
        print(pad(fixed(Double(band.lower), 2) + "-" + fixed(Double(band.upper), 2), 14)
              + pad("\(band.right)", 8) + pad("\(band.wrong)", 8)
              + (total > 0 ? fixed(precision, 1) + "%" : "-"))
    }
    let trusted = bands.filter { $0.lower >= 0.60 }
    let trustedRight = trusted.reduce(0) { $0 + $1.right }
    let trustedWrong = trusted.reduce(0) { $0 + $1.wrong }
    let flagged = bands.filter { $0.lower < 0.60 }
    let flaggedRight = flagged.reduce(0) { $0 + $1.right }
    let flaggedWrong = flagged.reduce(0) { $0 + $1.wrong }
    func pct(_ r: Int, _ w: Int) -> String {
        r + w > 0 ? fixed(Double(r) / Double(r + w) * 100, 1) + "%" : "-"
    }
    print("\n  marked 'no review needed' (>= 0.60): \(trustedRight) right, \(trustedWrong) wrong -> \(pct(trustedRight, trustedWrong))")
    print("  marked 'please confirm'     (< 0.60): \(flaggedRight) right, \(flaggedWrong) wrong -> \(pct(flaggedRight, flaggedWrong))")
    exit(0)
}

// MARK: - Run every candidate

var detectorSets: [String: Set<String>] = [:]
// Before/after for the display policy, both built from the shipped source.
//
// "before" reproduces what the old `IngredientNormalizer` did in one step: a
// 0.40 floor and a flat top-12-by-confidence cap, with no per-ingredient
// budget. "after" is the shipped two-stage chain - candidates at 0.30, then
// `DetectionDisplayFilter`.
let beforeNormalizer: IngredientNormalizer = {
    var policy = DetectionFilterPolicy.default
    policy.candidateThreshold = policy.displayThreshold   // 0.40, as it was
    policy.maximumCandidates = policy.maximumDisplayedBoxes  // flat cap of 12
    return IngredientNormalizer(taxonomy: resolved.taxonomy, policy: policy)
}()
var beforeSets: [String: Set<String>] = [:]
var afterSets: [String: Set<String>] = [:]
var beforeBoxes: [String: Int] = [:]
var afterBoxes: [String: Int] = [:]

var fullImage30: [String: Set<String>] = [:]
var fullImage10: [String: Set<String>] = [:]
var cropSets: [String: Set<String>] = [:]
var agreedSets: [String: Set<String>] = [:]
var conflictCounts: [String: Int] = [:]
var ocrLines: [String: Int] = [:]
var ocrMatches: [String: [String]] = [:]
var ocrNonLatin: [String: Int] = [:]
var timings: [String: (detect: Double, scene: Double, crops: Double, ocr: Double)] = [:]

let sceneHigh = classifier(0.30)
let sceneLow = classifier(0.10)
let regionClassifier = RegionIngredientClassifier(classifier: classifier(0.20, cap: 10))

// Warm-up: the first Vision request of each kind pays model load.
if let warm = loadImage(annotations.keys.sorted().first ?? "") {
    _ = try? sceneHigh.classify(warm)
    _ = try? detector.detect(in: warm)
    _ = try? textReader.read(warm)
}

func elapsed(_ body: () throws -> Void) rethrows -> Double {
    let start = Date(); try body(); return Date().timeIntervalSince(start) * 1000
}

for name in annotations.keys.sorted() {
    guard let image = loadImage(name) else {
        print("missing image: \(name)")
        continue
    }

    var raw = DetectionFrame.empty
    let detectMs = try elapsed { raw = try detector.detect(in: image) }
    let normalised = resolved.normalizer.normalize(raw, source: resolved.source)
    detectorSets[name] = Set(normalised.ingredients.map(\.ingredientId))

    // Each image gets a fresh filter: these are 11 unrelated stills, so
    // carrying hysteresis between them would be meaningless.
    var displayFilter = DetectionDisplayFilter(policy: resolved.policy)
    let displayed = displayFilter.display(normalised)
    afterSets[name] = Set(displayed.ingredients.map(\.ingredientId))
    afterBoxes[name] = displayed.ingredients.count

    let before = beforeNormalizer.normalize(raw, source: resolved.source)
    beforeSets[name] = Set(before.ingredients.map(\.ingredientId))
    beforeBoxes[name] = before.ingredients.count

    var scene = ClassificationResult.empty
    let sceneMs = try elapsed { scene = try sceneHigh.classify(image, orientation: .up) }
    fullImage30[name] = Set(scene.ingredients.map(\.ingredientId))
        .union(scene.rejectedFoodClaims.map { "!\($0)" })

    let low = try sceneLow.classify(image, orientation: .up)
    fullImage10[name] = Set(low.ingredients.map(\.ingredientId))
        .union(low.rejectedFoodClaims.map { "!\($0)" })

    var regions: [UUID: ClassificationResult] = [:]
    let cropMs = elapsed {
        regions = regionClassifier.classifyRegions(in: image, regions: normalised.ingredients).results
    }
    cropSets[name] = Set(regions.values.flatMap { $0.ingredients.map(\.ingredientId) })

    let fused = fusion.fuse(
        detections: normalised, regionClassifications: regions, sceneClassification: scene
    )
    agreedSets[name] = Set(fused.localised.filter { $0.tier == .agreed }.map(\.ingredientId))
    conflictCounts[name] = fused.conflictCount

    var reading = PackagedFoodReading.empty
    let ocrMs = try elapsed { reading = try textReader.read(image, orientation: .up) }
    ocrLines[name] = reading.lines.count
    ocrMatches[name] = reading.matches.map { "\($0.ingredientId)[\($0.certainty.rawValue)]" }
    ocrNonLatin[name] = reading.nonLatinLines.count

    timings[name] = (detectMs, sceneMs, cropMs, ocrMs)
}

func union(_ a: [String: Set<String>], _ b: [String: Set<String>]) -> [String: Set<String>] {
    var out = a
    for (key, value) in b { out[key, default: []].formUnion(value) }
    return out
}

// MARK: - Conflict strategy comparison (Stage 2, Task 3)
//
// Re-runs fusion over the already-computed detector and region results with
// each strategy, and scores two things: the overall set, and - separately -
// only those regions where the two methods actually disagreed. The overall
// number hides the effect, because conflicts are a minority of regions.

print("\n=== conflict strategy comparison ===")
var strategyRows: [[String: Any]] = []

for strategy in DetectionFusionService.ConflictStrategy.allCases {
    let service = DetectionFusionService(configuration: .with(strategy))
    var asserted: [String: Set<String>] = [:]
    var conflictRight = 0, conflictWrong = 0, conflictDeferred = 0

    for name in annotations.keys.sorted() {
        guard let image = loadImage(name) else { continue }
        let raw = try detector.detect(in: image)
        let normalised = resolved.normalizer.normalize(raw, source: resolved.source)
        let regions = regionClassifier.classifyRegions(in: image, regions: normalised.ingredients).results
        let scene = try sceneHigh.classify(image, orientation: .up)
        let fused = service.fuse(
            detections: normalised, regionClassifications: regions, sceneClassification: scene
        )
        asserted[name] = fused.assertedIngredientIds

        let expected = Set(annotations[name]?.present ?? [])
        for item in fused.localised where item.tier == .conflicting {
            if !item.assertsIngredient { conflictDeferred += 1 }
            else if expected.contains(item.ingredientId) { conflictRight += 1 }
            else { conflictWrong += 1 }
        }
    }

    let overall = score(asserted, annotations, strategy.rawValue)
    let decided = conflictRight + conflictWrong
    let conflictAccuracy = decided > 0 ? Double(conflictRight) / Double(decided) : 0
    print(String(format: "  %-18s overall %2d/%2d (%.1f%%) prec %.1f%%  |  conflicts: %d right, %d wrong, %d deferred  (accuracy %.0f%%)",
                 (strategy.rawValue as NSString).utf8String!,
                 overall.found, overall.expected, overall.recall * 100, overall.precision * 100,
                 conflictRight, conflictWrong, conflictDeferred, conflictAccuracy * 100))
    strategyRows.append([
        "strategy": strategy.rawValue,
        "recall": overall.recall, "precision": overall.precision,
        "falsePositives": overall.falsePositives,
        "conflictRight": conflictRight, "conflictWrong": conflictWrong,
        "conflictDeferred": conflictDeferred,
    ])
}

let scores = [
    score(beforeSets, annotations, "overlay BEFORE (flat cap)"),
    score(afterSets, annotations, "overlay AFTER (budgeted)"),
    score(detectorSets, annotations, "yolo-world candidates"),
    score(fullImage30, annotations, "vision full-image @0.30"),
    score(fullImage10, annotations, "vision full-image @0.10"),
    score(cropSets, annotations, "vision crop-based @0.20"),
    score(union(detectorSets, cropSets), annotations, "hybrid: yolo + crops"),
    score(union(detectorSets, fullImage30), annotations, "hybrid: yolo + full-image"),
    score(agreedSets, annotations, "agreement (localised)"),
]
report(scores)

// Looked up by label rather than index, so adding a row above cannot silently
// relabel what is printed below.
func scored(_ label: String) -> Score { scores.first { $0.label == label }! }

print("--- displayed boxes per image: before -> after ---")
var beforeTotal = 0, afterTotal = 0
for name in annotations.keys.sorted() {
    let b = beforeBoxes[name] ?? 0, a = afterBoxes[name] ?? 0
    beforeTotal += b
    afterTotal += a
    let names = afterSets[name]?.sorted().joined(separator: ", ") ?? ""
    print(String(format: "  %-16s %3d -> %3d   %@",
                 (name as NSString).utf8String!, b, a, names as NSString))
}
let imageCount = max(annotations.count, 1)
print(String(format: "  %-16s %3d -> %3d   (%.2f -> %.2f per image)",
             ("TOTAL" as NSString).utf8String!, beforeTotal, afterTotal,
             Double(beforeTotal) / Double(imageCount), Double(afterTotal) / Double(imageCount)))

print("--- false negatives: overlay AFTER ---")
print(scored("overlay AFTER (budgeted)").missed.sorted().joined(separator: ", "))
print("--- false positives: overlay BEFORE ---")
print(scored("overlay BEFORE (flat cap)").spurious.sorted().joined(separator: ", "))
print("--- false positives: overlay AFTER ---")
print(scored("overlay AFTER (budgeted)").spurious.sorted().joined(separator: ", "))
print("--- false negatives: vision full-image @0.30 ---")
print(scored("vision full-image @0.30").missed.sorted().joined(separator: ", "))
print("--- false positives: vision full-image @0.30 ---")
print(scored("vision full-image @0.30").spurious.sorted().joined(separator: ", "))
print("--- false positives: crop-based @0.20 ---")
print(scored("vision crop-based @0.20").spurious.sorted().joined(separator: ", "))
print("--- conflicts per image ---")
print(conflictCounts.filter { $0.value > 0 }.sorted { $0.key < $1.key }
        .map { "\($0.key):\($0.value)" }.joined(separator: ", "))
print("--- OCR ---")
for name in ocrLines.keys.sorted() where ocrLines[name]! > 0 {
    print("  \(name): \(ocrLines[name]!) lines (\(ocrNonLatin[name] ?? 0) non-Latin), matches \(ocrMatches[name] ?? [])")
}

let detectTimes = timings.values.map(\.detect).sorted()
let sceneTimes = timings.values.map(\.scene).sorted()
let cropTimes = timings.values.map(\.crops).sorted()
let ocrTimes = timings.values.map(\.ocr).sorted()
func median(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs[xs.count / 2] }
print(String(format: """
--- latency, Mac Catalyst on this machine, median (max) ms ---
  yolo detect     %6.1f (%6.1f)
  vision scene    %6.1f (%6.1f)
  region crops    %6.1f (%6.1f)
  packaging OCR   %6.1f (%6.1f)
""", median(detectTimes), detectTimes.last ?? 0,
     median(sceneTimes), sceneTimes.last ?? 0,
     median(cropTimes), cropTimes.last ?? 0,
     median(ocrTimes), ocrTimes.last ?? 0))

// Machine-readable, for the docs.
struct Row: Encodable {
    let label: String, recall: Double, precision: Double
    let found: Int, expected: Int, falsePositives: Int
    let perCategory: [String: Double]
}
let rows = scores.map { s in
    Row(label: s.label, recall: s.recall, precision: s.precision,
        found: s.found, expected: s.expected, falsePositives: s.falsePositives,
        perCategory: Dictionary(uniqueKeysWithValues: CATEGORIES.map { ($0, s.recall(for: $0)) }))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
struct Output: Encodable {
    let rows: [Row]
    let perImage: [String: [String: [String]]]
}
let perImage: [String: [String: [String]]] = [
    "overlayBefore": beforeSets.mapValues { $0.sorted() },
    "overlayAfter": afterSets.mapValues { $0.sorted() },
    "yolo": detectorSets.mapValues { $0.sorted() },
    "visionFull30": fullImage30.mapValues { $0.sorted() },
    "crops": cropSets.mapValues { $0.sorted() },
    "agreed": agreedSets.mapValues { $0.sorted() },
]
let outputURL = URL(fileURLWithPath: "tools/vision-eval/results_swift_hybrid.json")
try? encoder.encode(Output(rows: rows, perImage: perImage)).write(to: outputURL)
print("wrote \(outputURL.path)")
