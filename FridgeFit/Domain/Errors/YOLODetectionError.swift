//
//  YOLODetectionError.swift
//  FridgeFit
//

import Foundation

/// Why on-device detection isn't working.
///
/// Every case here means "no boxes are being drawn, and here is why". None of
/// them falls back to invented results - a detector that cannot run says so.
nonisolated enum YOLODetectionError: Error, Equatable, Sendable {
    /// The `.mlmodelc` isn't in the bundle. Almost always means the export
    /// script hasn't been run.
    case modelMissing(name: String)
    /// The model is present but Core ML or Vision refused it.
    case modelLoadFailed(reason: String)
    /// The decoded frame isn't backed by a `CVPixelBuffer`.
    case unsupportedPixelFormat
    /// The frame could not be read.
    case frameConversionFailed
    /// Vision ran and threw.
    case inferenceFailed(reason: String)

    var message: String {
        switch self {
        case .modelMissing(let name):
            return """
            The \(name) detection model isn't bundled with this build. Run \
            tools/yolo-export/setup.sh and rebuild to enable food detection.
            """
        case .modelLoadFailed(let reason):
            return "The detection model couldn't be loaded: \(reason)"
        case .unsupportedPixelFormat:
            return """
            The incoming video is in a format this device can't run detection \
            on. Video keeps playing; detection is off for this session.
            """
        case .frameConversionFailed:
            return "A video frame couldn't be read for detection."
        case .inferenceFailed(let reason):
            return "Detection failed: \(reason)"
        }
    }

    /// Whether it is worth trying again on the next frame.
    ///
    /// A missing or unloadable model will not fix itself, and retrying it 3
    /// times a second would just fill the log. A single bad frame might.
    var isRecoverable: Bool {
        switch self {
        case .modelMissing, .modelLoadFailed, .unsupportedPixelFormat:
            return false
        case .frameConversionFailed, .inferenceFailed:
            return true
        }
    }
}
