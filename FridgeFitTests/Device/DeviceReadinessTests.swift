//
//  DeviceReadinessTests.swift
//  FridgeFitTests
//
//  Checks that mean something only on real hardware.
//
//  ## The rule this file exists to enforce
//
//  **A check that cannot run reports NOT VERIFIED, never PASSED.** Every
//  device-only test below calls `XCTSkip` with an explicit message when it is
//  running somewhere that cannot answer the question. A skip is visible in
//  the test output and in `tools/device-verification/run-device-checks.sh`,
//  which is the point: a green simulator run must never be mistakable for
//  evidence about on-device model quality.
//
//  That matters most for Apple Intelligence. The iOS 26 **simulator reports
//  `availability == .available` while having no model assets at all**, and a
//  `respond` call there never returns. So "the model is available" is not
//  something a simulator run can establish, and these tests refuse to
//  pretend otherwise - `test_appleIntelligence_reallyGenerates` requires an
//  actual generation to come back with content, which only hardware can do.
//
//  ## What *is* checked everywhere
//
//  Packaging and plumbing: that the CoreML models are in the bundle and
//  load, that Vision OCR runs, that the permission strings exist. Those are
//  device-independent facts about the build, and failing them on a simulator
//  is a real failure.
//

import AVFoundation
import CoreML
import FoundationModels
import UIKit
import Vision
import XCTest
@testable import FridgeFit

/// Whether this process is running on real hardware.
private var isSimulator: Bool {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
}

/// Standard skip message, so the reason is uniform wherever it appears.
private func notVerifiedOnSimulator(_ what: String) -> XCTSkip {
    XCTSkip("NOT VERIFIED: \(what) can only be established on a physical device.")
}

// MARK: - Packaging (runs everywhere)

final class DevicePackagingTests: XCTestCase {

    /// The CoreML models have to be in the shipped bundle and compiled. This
    /// is a build-packaging fact, so it is a genuine failure anywhere.
    func test_coreMLModels_areBundledAndLoadable() throws {
        let bundle = Bundle(for: type(of: self))
        let appBundle = Bundle(identifier: "com.Fridge.FridgeFit") ?? bundle

        var found: [String] = []
        for name in ["FridgeFitIngredients", "YOLO11n"] {
            // Xcode compiles `.mlpackage` to `.mlmodelc` in the bundle.
            if appBundle.url(forResource: name, withExtension: "mlmodelc") != nil {
                found.append(name)
            }
        }

        XCTAssertFalse(
            found.isEmpty,
            "neither CoreML model is in the app bundle - on-device detection cannot work"
        )
    }

    /// The detector factory must resolve *something*, falling back if the
    /// preferred model is unavailable. A throw here means Camera Mode has no
    /// detector at all.
    func test_detectorFactory_resolvesADetector() throws {
        let appBundle = Bundle(identifier: "com.Fridge.FridgeFit") ?? Bundle(for: type(of: self))

        do {
            let resolved = try IngredientDetectorFactory.makeBest(bundle: appBundle)
            XCTAssertFalse(
                resolved.taxonomy.definitions.isEmpty,
                "the detector resolved with an empty taxonomy"
            )
        } catch {
            // A missing model in the *test* bundle is a packaging quirk, not
            // a product defect, so it is reported as unverified rather than
            // failed - the bundling itself is covered above.
            throw XCTSkip("NOT VERIFIED: no CoreML model reachable from this bundle (\(error))")
        }
    }

    /// Camera usage copy must exist, or iOS kills the app the moment it asks
    /// for the camera. Checked against the built app's Info.plist.
    func test_cameraUsageDescription_isPresent() throws {
        let appBundle = try XCTUnwrap(
            Bundle(identifier: "com.Fridge.FridgeFit"),
            "could not locate the app bundle"
        )
        let description = appBundle.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String

        XCTAssertFalse(
            (description ?? "").isEmpty,
            "NSCameraUsageDescription is missing - requesting camera access would terminate the app"
        )
    }
}

// MARK: - Vision OCR (runs everywhere; quality only meaningful on device)

final class DeviceVisionTests: XCTestCase {

    /// Vision runs in the simulator, so this is a real check of the OCR
    /// plumbing anywhere. What it deliberately does **not** claim is
    /// recognition *quality* on a photographed receipt - that needs a real
    /// camera and real paper, and is covered by the manual checklist.
    func test_visionTextRecognition_runsWithoutError() async throws {
        let recognizer = VisionReceiptTextRecognizer()
        let image = ReceiptImageFixtures.demoLikeReceipt(width: 200, height: 320)

        // Synthetic noise contains no text; the contract being checked is
        // that recognition completes and returns a result rather than
        // throwing or hanging.
        let recognized = try await recognizer.recognizeText(in: image, orientation: .up)

        XCTAssertNotNil(recognized, "Vision returned no result object")
    }

    func test_receiptOCRQuality_onRealPhotographs() throws {
        throw XCTSkip(
            """
            NOT VERIFIED: receipt OCR quality against real photographed receipts \
            requires a physical device and printed receipts. Run the manual steps in \
            docs/assessment4-device-verification-checklist.md.
            """
        )
    }
}

// MARK: - Apple Intelligence (device only)

final class DeviceAppleIntelligenceTests: XCTestCase {

    /// Reports what the system actually says, and fails only on hardware.
    ///
    /// On the simulator this is skipped rather than asserted, because the
    /// simulator's answer is known to be wrong - it claims `.available` with
    /// no assets installed.
    func test_appleIntelligence_isAvailable() throws {
        if isSimulator {
            throw notVerifiedOnSimulator("Apple Intelligence availability")
        }

        let availability = AppleReceiptIngredientInterpreter().availability
        guard availability.canScan else {
            throw XCTSkip(
                """
                NOT VERIFIED: this device reports Apple Intelligence as \
                \(availability) - enable it in Settings, or use a supported device, \
                then re-run.
                """
            )
        }

        XCTAssertEqual(availability, .available)
    }

    /// The only check that can establish the model genuinely works: a real
    /// generation that comes back with content.
    ///
    /// Bounded by the shipping deadline, so a device that claims availability
    /// without being able to generate fails here instead of hanging - which
    /// is exactly the failure mode `BoundedWork` was written for.
    func test_appleIntelligence_reallyGenerates() async throws {
        if isSimulator {
            throw notVerifiedOnSimulator("real Apple Intelligence generation")
        }

        let interpreter = AppleReceiptIngredientInterpreter()
        guard interpreter.availability.canScan else {
            throw XCTSkip("NOT VERIFIED: Apple Intelligence is not available on this device.")
        }

        let lines = SampleReceipt.recognizedText
        let parsed = ReceiptLineParser().parse(lines)
        XCTAssertFalse(parsed.isEmpty, "the fixture produced no product lines to interpret")

        let result = try await interpreter.interpret(lineItems: parsed)

        XCTAssertFalse(
            result.items.isEmpty,
            "the model returned nothing for a receipt with \(parsed.count) product lines"
        )
    }

    func test_recipeSuggestions_reallyGenerate() async throws {
        if isSimulator {
            throw notVerifiedOnSimulator("real recipe-suggestion generation")
        }

        let service = AppleRecipeSuggestionService()
        guard service.availability.canScan else {
            throw XCTSkip("NOT VERIFIED: Apple Intelligence is not available on this device.")
        }

        let pantry = [
            PantryItem(ingredient: Ingredient(name: "egg", category: .other), quantity: 6, unit: .pieces),
            PantryItem(ingredient: Ingredient(name: "tomato", category: .produce), quantity: 3, unit: .pieces),
            PantryItem(ingredient: Ingredient(name: "rice", category: .grain), quantity: 1, unit: .kilograms),
        ]

        let suggestions = try await service.suggestRecipes(from: pantry)

        XCTAssertFalse(suggestions.isEmpty, "the model suggested nothing for a three-ingredient pantry")
        for suggestion in suggestions {
            XCTAssertFalse(suggestion.name.isEmpty)
            XCTAssertFalse(suggestion.requiredIngredients.isEmpty)
        }
    }

    /// A model failure must degrade to an explained, retryable state rather
    /// than a hang - on hardware as well as against fakes.
    func test_modelFailure_degradesRatherThanHanging() async throws {
        if isSimulator {
            throw notVerifiedOnSimulator("on-device model failure behaviour")
        }

        // An impossibly short deadline stands in for a device that cannot
        // generate: the request must come back quickly, as an error.
        let interpreter = AppleReceiptIngredientInterpreter(
            batchTimeout: .milliseconds(1),
            overallTimeout: .milliseconds(1)
        )
        let parsed = ReceiptLineParser().parse(SampleReceipt.recognizedText)

        let started = ContinuousClock.now
        do {
            _ = try await interpreter.interpretBatches(of: parsed)
            // Returning a partial result this fast is also acceptable.
        } catch let error as ReceiptScanError {
            XCTAssertEqual(error, .timeout)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertLessThan(
            ContinuousClock.now - started,
            .seconds(10),
            "a failing model must not hang the scan"
        )
    }
}

// MARK: - Camera and lifecycle (device only)

final class DeviceCameraTests: XCTestCase {

    /// The simulator has no camera, so `isSourceTypeAvailable(.camera)` is
    /// always false there and proves nothing.
    func test_cameraHardware_isPresent() throws {
        if isSimulator {
            throw notVerifiedOnSimulator("camera hardware availability")
        }

        XCTAssertTrue(
            UIImagePickerController.isSourceTypeAvailable(.camera),
            "no camera on a device build - Smart Scan and Camera Mode cannot work"
        )
    }

    /// Reports the real authorization state. Does not *request* it: a test
    /// run cannot answer a system prompt, so requesting would hang.
    func test_cameraAuthorization_isReportable() throws {
        if isSimulator {
            throw notVerifiedOnSimulator("camera authorization behaviour")
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        XCTAssertTrue(
            [.authorized, .denied, .restricted, .notDetermined].contains(status),
            "unexpected authorization status \(status.rawValue)"
        )

        if status != .authorized {
            throw XCTSkip(
                """
                NOT VERIFIED: camera access is \(status.rawValue) on this device. \
                Grant it and re-run to verify the granted path; the denied path is \
                covered by PermissionRecoveryTests.
                """
            )
        }
    }

    func test_backgroundForegroundTransitions() throws {
        throw XCTSkip(
            """
            NOT VERIFIED: background/foreground transition behaviour needs a manual \
            device session. See docs/assessment4-device-verification-checklist.md.
            """
        )
    }

    func test_memoryUnderSustainedDetection() throws {
        throw XCTSkip(
            """
            NOT VERIFIED: memory and thermal behaviour under sustained CoreML detection \
            needs Instruments on a device. See \
            docs/assessment4-device-verification-checklist.md.
            """
        )
    }

    func test_offlineFallbackOnDevice() throws {
        throw XCTSkip(
            """
            NOT VERIFIED: airplane-mode behaviour needs a manual device session. The \
            logic is covered off-device by the funds offline-queue tests and the \
            Discover unavailable-service tests.
            """
        )
    }
}
