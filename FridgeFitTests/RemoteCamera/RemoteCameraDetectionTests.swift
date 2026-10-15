//
//  RemoteCameraDetectionTests.swift
//  FridgeFitTests
//

import CoreVideo
import ImageIO
import XCTest
@preconcurrency import WebRTC
@testable import FridgeFit

/// Detection as the Controller screen drives it: starting when video
/// arrives, the toggle, and - the part most likely to go wrong - clearing up
/// on disconnect, reconnect and camera switch.
///
/// Uses a real `RTCVideoTrack` (from `SyntheticVideoSource`) so the tap is
/// genuinely attached and detached, with a stub detector so results are
/// deterministic.
@MainActor
final class RemoteCameraDetectionTests: XCTestCase {

    /// Returns whatever it is told to, immediately.
    private final class StubDetector: FrameDetecting, @unchecked Sendable {
        let objects: [DetectedObject]
        init(objects: [DetectedObject] = []) { self.objects = objects }

        func detect(
            in pixelBuffer: CVPixelBuffer,
            orientation: CGImagePropertyOrientation,
            orientedSize: CGSize
        ) throws -> DetectionFrame {
            DetectionFrame(objects: objects, sourceSize: orientedSize)
        }
    }

    private let identity = DeviceIdentity(deviceId: "controller", deviceName: "Pocket iPhone")
    private var videoSource: SyntheticVideoSource?

    override func tearDown() async throws {
        videoSource?.stop()
        videoSource = nil
        try await super.tearDown()
    }

    /// A real video track, so `track.add(tap)` / `track.remove(tap)` are the
    /// real calls rather than a stand-in.
    private func makeTrack(id: String = "test-track") -> RTCVideoTrack {
        let source = SyntheticVideoSource(trackId: id)
        videoSource = source
        return source.videoTrack
    }

    private func makeViewModel(
        detector: (any FrameDetecting)? = StubDetector(),
        detectorError: Error? = nil,
        source: DetectionSource = .ingredientDetector
    ) -> RemoteCameraViewModel {
        RemoteCameraViewModel(
            identity: identity,
            registry: InMemoryDeviceRegistry(),
            transport: InMemorySignalingTransport(),
            makeDetector: {
                if let detectorError { throw detectorError }
                // A permissive policy: these tests are about lifecycle, not
                // filtering, so stub detections should survive normalisation
                // *and* the display filter.
                var policy = DetectionFilterPolicy.default
                policy.candidateThreshold = 0.0
                policy.displayThreshold = 0.0
                policy.displayReleaseThreshold = 0.0
                return ResolvedDetector(
                    detector: detector!,
                    normalizer: IngredientNormalizer(taxonomy: .coco, policy: policy),
                    source: source,
                    fallbackReason: nil
                )
            }
        )
    }

    private func poll(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Defaults

    func test_detectionIsOnByDefaultAndWaitingForVideo() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.isDetectionEnabled)
        XCTAssertEqual(viewModel.detectionStatus, .waitingForVideo)
        XCTAssertTrue(viewModel.ingredients.isEmpty)
        XCTAssertEqual(viewModel.detectionCount, 0)
    }

    /// The listed ingredients come from whichever taxonomy is loaded, so the
    /// UI describes the model that is actually running.
    func test_theListedIngredientsComeFromTheLoadedTaxonomy() {
        let viewModel = makeViewModel()
        viewModel.adoptRemoteVideoTrack(makeTrack())

        // This harness loads the COCO taxonomy.
        XCTAssertEqual(viewModel.detectableIngredientCount, 10)
        XCTAssertTrue(viewModel.detectableIngredients(in: .fruit).contains("Banana"))
        XCTAssertTrue(viewModel.detectableIngredients(in: .dairy).isEmpty,
                      "COCO has no dairy classes and must not claim any")
    }

    func test_theDetectionSourceIsReported() {
        let viewModel = makeViewModel(source: .cocoFallback)
        viewModel.adoptRemoteVideoTrack(makeTrack())

        XCTAssertEqual(viewModel.detectionSource, .cocoFallback)
    }

    // MARK: - Starting

    func test_adoptingATrackStartsDetection() {
        let viewModel = makeViewModel()
        let track = makeTrack()

        viewModel.adoptRemoteVideoTrack(track)

        XCTAssertIdentical(viewModel.remoteVideoTrack, track)
        // Video isn't confirmed yet, so it is attached but still waiting.
        XCTAssertEqual(viewModel.detectionStatus, .waitingForVideo)
    }

    /// The real pipeline end to end: synthetic frames flow through the track,
    /// the tap samples one, and the result reaches the view model.
    func test_detectionsFromTheTrackReachTheViewModel() async {
        let viewModel = makeViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "banana", confidence: 0.9,
                           boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
        ]))
        let source = SyntheticVideoSource(trackId: "live")
        videoSource = source

        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }

        XCTAssertEqual(viewModel.ingredients.ingredients.first?.ingredientId, "banana")
        XCTAssertEqual(viewModel.detectionCount, 1)
        XCTAssertEqual(viewModel.ingredients.sourceSize, CGSize(width: 320, height: 240))
    }

    func test_detectionIsNotStartedWhenTheToggleIsOff() {
        let viewModel = makeViewModel()
        viewModel.isDetectionEnabled = false

        viewModel.adoptRemoteVideoTrack(makeTrack())

        XCTAssertEqual(viewModel.detectionStatus, .off)
        XCTAssertTrue(viewModel.ingredients.isEmpty)
    }

    // MARK: - The stages stay separate

    /// A view model running the *shipped* policy, so the stage boundaries are
    /// the real ones rather than a permissive test configuration.
    private func makeShippedPolicyViewModel(
        detector: any FrameDetecting
    ) -> RemoteCameraViewModel {
        RemoteCameraViewModel(
            identity: identity,
            registry: InMemoryDeviceRegistry(),
            transport: InMemorySignalingTransport(),
            makeDetector: {
                ResolvedDetector(
                    detector: detector,
                    normalizer: IngredientNormalizer(taxonomy: .coco, policy: .default),
                    source: .ingredientDetector,
                    fallbackReason: nil
                )
            }
        )
    }

    /// The Controller sees fewer boxes than the pipeline accepted, and the
    /// difference is not thrown away - it is what the snapshot analysis works
    /// from.
    func test_theOverlayIsNarrowerThanTheCandidateList() async {
        let viewModel = makeShippedPolicyViewModel(detector: StubDetector(objects: [
            // Above the 0.40 display floor.
            DetectedObject(label: "banana", confidence: 0.72,
                           boundingBox: .init(x: 0.05, y: 0.05, width: 0.15, height: 0.15)),
            // Above the 0.30 candidate floor, below the display floor.
            DetectedObject(label: "apple", confidence: 0.34,
                           boundingBox: .init(x: 0.60, y: 0.60, width: 0.15, height: 0.15)),
        ]))
        let source = SyntheticVideoSource(trackId: "stages")
        videoSource = source

        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.candidateIngredients.isEmpty }

        XCTAssertEqual(viewModel.candidateIngredients.ingredients.count, 2,
                       "both clear the candidate floor")
        XCTAssertEqual(viewModel.ingredients.ingredients.map(\.ingredientId), ["banana"],
                       "only one clears the display floor")
        XCTAssertEqual(viewModel.detectionCount, 1)
    }

    /// One ingredient with many instances must not fill the overlay and push
    /// the others out - the measured regression this change exists to fix.
    func test_theOverlayKeepsRoomForEveryIngredientItFound() async {
        var objects = (0..<10).map { index in
            DetectedObject(
                label: "apple", confidence: 0.90 - Float(index) * 0.01,
                boundingBox: .init(x: CGFloat(index) * 0.09, y: 0.05, width: 0.05, height: 0.05)
            )
        }
        objects.append(DetectedObject(label: "banana", confidence: 0.55,
                                      boundingBox: .init(x: 0.1, y: 0.7, width: 0.1, height: 0.1)))
        objects.append(DetectedObject(label: "carrot", confidence: 0.52,
                                      boundingBox: .init(x: 0.5, y: 0.7, width: 0.1, height: 0.1)))
        let viewModel = makeShippedPolicyViewModel(detector: StubDetector(objects: objects))
        let source = SyntheticVideoSource(trackId: "budget")
        videoSource = source

        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }

        let drawn = Set(viewModel.ingredients.ingredients.map(\.ingredientId))
        XCTAssertEqual(drawn, ["apple", "banana", "carrot"])
        XCTAssertEqual(
            viewModel.ingredients.ingredients.filter { $0.ingredientId == "apple" }.count, 3,
            "apples are budgeted, not suppressed - three of the real ones are kept"
        )
    }

    /// Nothing the live path publishes may be presented as confirmed.
    func test_noLiveDetectionIsMarkedVerified() async {
        let viewModel = makeShippedPolicyViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "banana", confidence: 0.98,
                           boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
        ]))
        let source = SyntheticVideoSource(trackId: "verified")
        videoSource = source

        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }

        XCTAssertTrue(viewModel.ingredients.ingredients.allSatisfy { !$0.isVerified })
        XCTAssertTrue(viewModel.ingredients.ingredients.allSatisfy(\.requiresConfirmation))
    }

    /// Boxes measured against a frame that has stopped arriving describe
    /// pixels that are no longer on screen, so they are cleared rather than
    /// left to drift.
    func test_detectionsAreClearedWhenResultsStopArriving() async {
        let viewModel = makeShippedPolicyViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "banana", confidence: 0.72,
                           boundingBox: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
        ]))
        let source = SyntheticVideoSource(trackId: "stale")
        videoSource = source

        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }

        // Stop the stream; nothing further reaches the tap.
        source.stop()
        videoSource = nil

        await poll(timeout: .seconds(6)) { viewModel.ingredients.isEmpty }
        XCTAssertTrue(viewModel.ingredients.isEmpty,
                      "the overlay should empty itself within the staleness window")
        XCTAssertTrue(viewModel.candidateIngredients.isEmpty)
    }

    // MARK: - The toggle

    func test_turningDetectionOffClearsTheBoxes() async {
        let viewModel = makeViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "apple", confidence: 0.8, boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
        ]))
        let source = SyntheticVideoSource(trackId: "toggle")
        videoSource = source
        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }

        viewModel.isDetectionEnabled = false

        XCTAssertTrue(viewModel.ingredients.isEmpty, "stale boxes must not linger after switching off")
        XCTAssertEqual(viewModel.detectionStatus, .off)
    }

    func test_turningDetectionBackOnResumes() async {
        let viewModel = makeViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "apple", confidence: 0.8, boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
        ]))
        let source = SyntheticVideoSource(trackId: "resume")
        videoSource = source
        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }
        viewModel.isDetectionEnabled = false

        viewModel.isDetectionEnabled = true
        await poll { !viewModel.ingredients.isEmpty }

        XCTAssertFalse(viewModel.ingredients.isEmpty)
        XCTAssertNotEqual(viewModel.detectionStatus, .off)
    }

    /// Toggling on before any video exists must not crash or claim to run.
    func test_togglingWithNoTrackJustWaits() {
        let viewModel = makeViewModel()

        viewModel.isDetectionEnabled = false
        viewModel.isDetectionEnabled = true

        XCTAssertEqual(viewModel.detectionStatus, .waitingForVideo)
    }

    func test_settingTheSameToggleValueIsANoOp() {
        let viewModel = makeViewModel()
        viewModel.adoptRemoteVideoTrack(makeTrack())
        let before = viewModel.detectionStatus

        viewModel.isDetectionEnabled = true

        XCTAssertEqual(viewModel.detectionStatus, before)
    }

    // MARK: - Teardown

    func test_disconnectingClearsDetections() async {
        let viewModel = makeViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "orange", confidence: 0.9, boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
        ]))
        let source = SyntheticVideoSource(trackId: "disconnect")
        videoSource = source
        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }

        await viewModel.disconnect()

        XCTAssertTrue(viewModel.ingredients.isEmpty, "boxes must be cleared on disconnect")
        XCTAssertNil(viewModel.remoteVideoTrack)
    }

    /// After disconnecting, frames still flowing on the old track must not
    /// produce new boxes - the tap has to be off the track, not just idle.
    func test_detectionStopsAfterDisconnectEvenIfFramesKeepFlowing() async {
        let viewModel = makeViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "orange", confidence: 0.9, boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
        ]))
        let source = SyntheticVideoSource(trackId: "after-disconnect")
        videoSource = source
        viewModel.adoptRemoteVideoTrack(source.videoTrack)
        source.start()
        await poll { !viewModel.ingredients.isEmpty }

        await viewModel.disconnect()
        // The camera side keeps sending for a while after we hang up.
        try? await Task.sleep(for: .milliseconds(600))

        XCTAssertTrue(viewModel.ingredients.isEmpty, "a detached tap must not deliver results")
    }

    /// Reconnecting hands over a different track; the tap must move with it
    /// rather than staying on the old one.
    func test_adoptingANewTrackMovesTheTap() async {
        let viewModel = makeViewModel(detector: StubDetector(objects: [
            DetectedObject(label: "pizza", confidence: 0.7, boundingBox: .init(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
        ]))

        let first = SyntheticVideoSource(trackId: "first")
        viewModel.adoptRemoteVideoTrack(first.videoTrack)
        first.start()
        await poll { !viewModel.ingredients.isEmpty }
        first.stop()

        // Reconnect: a brand new track.
        let second = SyntheticVideoSource(trackId: "second")
        videoSource = second
        viewModel.adoptRemoteVideoTrack(second.videoTrack)

        // Switching tracks clears what the previous one produced.
        XCTAssertTrue(viewModel.ingredients.isEmpty)
        XCTAssertIdentical(viewModel.remoteVideoTrack, second.videoTrack)

        second.start()
        await poll { !viewModel.ingredients.isEmpty }
        XCTAssertEqual(viewModel.ingredients.ingredients.first?.ingredientId, "pizza")
    }

    // MARK: - Model unavailable

    /// A missing model must be reported, never papered over with invented
    /// detections, and must not stop the video.
    func test_aMissingModelIsReportedAndNothingIsFaked() {
        let viewModel = makeViewModel(detectorError: YOLODetectionError.modelMissing(name: "YOLO11n"))

        viewModel.adoptRemoteVideoTrack(makeTrack())

        guard case .unavailable(let reason) = viewModel.detectionStatus else {
            return XCTFail("expected unavailable, got \(viewModel.detectionStatus)")
        }
        XCTAssertTrue(reason.contains("yolo-export"), reason)
        XCTAssertTrue(viewModel.ingredients.isEmpty)
        // The video track is still published, so playback is unaffected.
        XCTAssertNotNil(viewModel.remoteVideoTrack)
    }

    func test_aModelLoadFailureIsReported() {
        let viewModel = makeViewModel(detectorError: YOLODetectionError.modelLoadFailed(reason: "corrupt"))

        viewModel.adoptRemoteVideoTrack(makeTrack())

        XCTAssertNotNil(viewModel.detectionStatus.unavailableReason)
        XCTAssertTrue(viewModel.ingredients.isEmpty)
    }

    func test_aNilDetectorFactoryMeansDetectionIsUnavailable() {
        let viewModel = RemoteCameraViewModel(
            identity: identity,
            registry: InMemoryDeviceRegistry(),
            transport: InMemorySignalingTransport(),
            makeDetector: nil
        )

        viewModel.adoptRemoteVideoTrack(makeTrack())

        XCTAssertNotNil(viewModel.detectionStatus.unavailableReason)
    }

    // MARK: - Status presentation

    func test_statusNamesAreDistinct() {
        let statuses: [DetectionStatus] = [
            .off, .waitingForVideo, .running, .unavailable(reason: "x"),
        ]
        XCTAssertEqual(Set(statuses.map(\.displayName)).count, statuses.count)
        XCTAssertTrue(DetectionStatus.running.isRunning)
        XCTAssertFalse(DetectionStatus.off.isRunning)
        XCTAssertEqual(DetectionStatus.unavailable(reason: "why").unavailableReason, "why")
        XCTAssertNil(DetectionStatus.running.unavailableReason)
    }
}
