//
//  LocalImageAnalysisTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import FridgeFit

/// Analysing a photo from this iPhone's library, with no second device.
///
/// Exists because the remote-camera flow needs two iPhones, which makes the
/// single thing most in need of device testing - whether Apple Vision
/// classification works on hardware - the hardest to reach. This path needs
/// one device, no WebRTC session and no network.
@MainActor
final class LocalImageAnalysisTests: XCTestCase {

    private func makeViewModel() -> RemoteCameraViewModel {
        RemoteCameraViewModel(
            identity: DeviceIdentity(deviceId: "test-controller", deviceName: "Test"),
            registry: InMemoryDeviceRegistry(seedDevices: []),
            transport: InMemorySignalingTransport()
        )
    }

    private func photo() throws -> UIImage {
        let cgImage = try HybridEvaluation.image(named: "fruits_mixed")
        return UIImage(cgImage: cgImage)
    }

    // MARK: - The real pipeline

    /// Not a mock path: the shipped YOLO model, the real classifier, the real
    /// fusion. The same analyzer the capture flow uses.
    func test_aLocalPhotoRunsTheRealPipeline() async throws {
        let viewModel = makeViewModel()

        await viewModel.analyseLocalImage(try photo())

        let analysis = try XCTUnwrap(
            viewModel.currentAnalysis,
            "analysis failed: \(viewModel.analysisPhase.failureReason ?? "no reason given")"
        )
        XCTAssertFalse(analysis.fused.localised.isEmpty,
                       "the detector should find fruit in a photo of fruit")
        for item in analysis.fused.localised {
            XCTAssertNotNil(item.boundingBox, "boxes come from the detector, not from nowhere")
        }
    }

    /// The photo must become the displayed snapshot, so the review sheet and
    /// its thumbnail describe the image that was analysed.
    func test_theAnalysedPhotoBecomesTheDisplayedSnapshot() async throws {
        let viewModel = makeViewModel()

        await viewModel.analyseLocalImage(try photo())

        XCTAssertNotNil(viewModel.snapshot)
        XCTAssertNotNil(viewModel.snapshotId)
        XCTAssertTrue(viewModel.isAnalysisCurrent,
                      "the result must be tied to the photo on screen")
    }

    /// A second photo invalidates the first result rather than leaving the
    /// old boxes over the new image.
    func test_asecondPhotoReplacesTheFirstAnalysis() async throws {
        let viewModel = makeViewModel()

        await viewModel.analyseLocalImage(try photo())
        let firstId = try XCTUnwrap(viewModel.snapshotId)

        await viewModel.analyseLocalImage(UIImage(cgImage: try HybridEvaluation.image(named: "veg_mixed")))

        XCTAssertNotEqual(viewModel.snapshotId, firstId)
        XCTAssertTrue(viewModel.isAnalysisCurrent)
        XCTAssertEqual(viewModel.currentAnalysis?.snapshotId, viewModel.snapshotId)
    }

    func test_itNeedsNoConnectionOrVideo() async throws {
        let viewModel = makeViewModel()

        XCTAssertFalse(viewModel.isConnected)
        XCTAssertFalse(viewModel.isReceivingVideo)

        await viewModel.analyseLocalImage(try photo())

        XCTAssertNotNil(viewModel.currentAnalysis,
                        "this path must work with no session at all")
    }

    /// Whatever the classifier's state, the result records it, so a YOLO-only
    /// run is labelled as one.
    func test_theResultRecordsWhichRecognisersRan() async throws {
        let viewModel = makeViewModel()

        await viewModel.analyseLocalImage(try photo())

        let analysis = try XCTUnwrap(viewModel.currentAnalysis)
        if analysis.classification.capability.isAvailable {
            XCTAssertFalse(analysis.classification.isDetectorOnly)
        } else {
            XCTAssertTrue(analysis.classification.isDetectorOnly)
            XCTAssertNotNil(analysis.classification.userMessage)
        }
    }

    func test_anUndecodablePhotoIsReportedRatherThanIgnored() {
        let viewModel = makeViewModel()

        viewModel.reportLocalImageFailure()

        XCTAssertNotNil(viewModel.analysisPhase.failureReason)
    }

    /// A second request while one is running must not start a second analysis.
    func test_overlappingRequestsDoNotRunTwice() async throws {
        let viewModel = makeViewModel()
        let image = try photo()

        async let first: Void = viewModel.analyseLocalImage(image)
        async let second: Void = viewModel.analyseLocalImage(image)
        _ = await (first, second)

        XCTAssertFalse(viewModel.isAnalyzingSnapshot)
        XCTAssertNotNil(viewModel.currentAnalysis)
    }

    // MARK: - Renderer diagnostics

    /// The blank-preview diagnostic: the on-screen renderer's own count, kept
    /// separate from the frame tap's.
    func test_theRendererStatusIsRecordedSeparatelyFromTheTap() {
        let viewModel = makeViewModel()
        XCTAssertNil(viewModel.renderedVideoStatus)

        viewModel.recordRenderedVideo(RenderedVideoStatus(
            framesRendered: 42,
            reportedSize: CGSize(width: 720, height: 1280),
            lastFrameSize: CGSize(width: 720, height: 1280),
            lastRotationDegrees: 90,
            viewSize: CGSize(width: 300, height: 400)
        ))

        let status = try! XCTUnwrap(viewModel.renderedVideoStatus)
        XCTAssertEqual(status.framesRendered, 42)
        XCTAssertEqual(status.lastRotationDegrees, 90)
        XCTAssertEqual(status.viewSize, CGSize(width: 300, height: 400))
        XCTAssertNil(viewModel.videoFrameStatistics,
                     "the tap's count is a different measurement and stays independent")
    }
}
