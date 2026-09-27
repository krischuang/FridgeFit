//
//  CameraPicker.swift
//  FridgeFit
//

import AVFoundation
import SwiftUI
import UIKit

/// The camera, wrapped for SwiftUI.
///
/// Uses `UIImagePickerController` rather than a hand-rolled `AVFoundation`
/// capture session: a single still photo of a fridge doesn't need a custom
/// camera, and the system picker brings its own shutter, preview, retake and
/// permission flow. No third-party dependency either way.
///
/// Photo library selection doesn't need this - `PhotosPicker` runs out of
/// process and needs no permission at all, so `IngredientScannerView` uses
/// it directly.
struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the captured photo. Not called if the user cancels.
    let onCapture: (UIImage) -> Void
    /// Called when a capture came back with nothing usable, so the scanner
    /// can show its normal error instead of silently doing nothing.
    let onFailure: () -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFailure: onFailure, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFailure: () -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFailure: @escaping () -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFailure = onFailure
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onFailure()
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

/// Camera permission, in the three states the scanner has to behave
/// differently for.
enum CameraAccess {
    case granted
    case denied
    /// No camera at all - Simulator, or an iPad without one.
    case unavailable

    static var isCameraPresent: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Resolves camera access, prompting the user the first time.
    ///
    /// Asked before presenting `CameraPicker` so a denied permission shows
    /// an explanation instead of a black viewfinder.
    static func request() async -> CameraAccess {
        guard isCameraPresent else { return .unavailable }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    var explanation: String? {
        switch self {
        case .granted:
            return nil
        case .denied:
            return "FridgeFit needs camera access to photograph your fridge. You can turn it on in Settings, or choose a photo from your library instead."
        case .unavailable:
            return "This device doesn't have a camera available. Choose a photo from your library instead."
        }
    }
}
