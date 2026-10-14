//
//  DetectedObject.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// One object YOLO found in a frame.
///
/// `boundingBox` is **normalised to the oriented source frame**, in Vision's
/// coordinate space: origin bottom-left, x and y in 0...1. It is deliberately
/// *not* in view coordinates - the view size isn't known where detection
/// happens, and baking it in here would make the result stale the moment the
/// layout changed. `DetectionGeometry` does that conversion at draw time.
nonisolated struct DetectedObject: Identifiable, Equatable, Sendable {
    let id: UUID
    /// COCO class name, e.g. `"banana"`.
    let label: String
    /// 0...1, straight from the model.
    let confidence: Float
    let boundingBox: CGRect

    init(id: UUID = UUID(), label: String, confidence: Float, boundingBox: CGRect) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }

    /// Title case for display - COCO labels are lowercase ("hot dog").
    var displayName: String {
        label.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var confidencePercentage: Int {
        Int((confidence * 100).rounded())
    }
}

/// A set of detections together with the frame geometry they were measured
/// against.
///
/// The two travel as one value on purpose. Mapping boxes with a stale source
/// size is exactly what goes wrong when the remote camera switches between
/// portrait and landscape: the boxes keep arriving, the aspect ratio changes
/// underneath them, and everything lands in the wrong place for a frame or
/// two. Pairing them makes that impossible to get wrong.
nonisolated struct DetectionFrame: Equatable, Sendable {
    let objects: [DetectedObject]
    /// Size of the frame *after* rotation was applied - i.e. the size as
    /// displayed, which is what `RTCMTLVideoView` shows.
    let sourceSize: CGSize

    static let empty = DetectionFrame(objects: [], sourceSize: .zero)

    var isEmpty: Bool { objects.isEmpty }
}

/// What the detector is doing, for the status indicator.
nonisolated enum DetectionStatus: Equatable, Sendable {
    /// The user turned it off. Video keeps playing.
    case off
    /// On, but no video is arriving yet.
    case waitingForVideo
    /// On and sampling frames.
    case running
    /// Can't run at all - no model, or a format it can't read. Carries the
    /// reason so the UI explains itself instead of silently showing nothing.
    case unavailable(reason: String)

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .waitingForVideo: return "Waiting for video"
        case .running: return "Detecting"
        case .unavailable: return "Unavailable"
        }
    }

    var isRunning: Bool { self == .running }

    var unavailableReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// The COCO classes that are actually edible.
///
/// COCO has 80 classes and exactly ten of them are food. Anything else YOLO
/// reports - person, bottle, cup, bowl, dining table - is filtered out before
/// it reaches the UI.
///
/// Note what is *not* here: milk, eggs, cheese, and most of what is really in
/// a fridge. The pretrained COCO model cannot detect them, so the app does
/// not claim to. Recognising those needs a differently-trained model, which
/// is out of scope for this iteration.
nonisolated enum COCOFoodClass {
    /// Lowercase, exactly as the model emits them.
    static let all: Set<String> = [
        "banana",
        "apple",
        "sandwich",
        "orange",
        "broccoli",
        "carrot",
        "hot dog",
        "pizza",
        "donut",
        "cake",
    ]

    static func isFood(_ label: String) -> Bool {
        all.contains(label.lowercased())
    }

    /// For the UI, so the list of what the model can see is sourced from the
    /// same place the filter is.
    static var sortedDisplayNames: [String] {
        all.sorted().map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
}
