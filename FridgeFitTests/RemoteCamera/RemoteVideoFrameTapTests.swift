//
//  RemoteVideoFrameTapTests.swift
//  FridgeFitTests
//

import CoreVideo
import ImageIO
import XCTest
@preconcurrency import WebRTC
@testable import FridgeFit

/// The frame tap's job is to protect the video: sample a few frames a
/// second, never queue work, never deliver results into a dead session.
///
/// Driven with a controllable clock and a stub detector so the throttling and
/// concurrency rules are deterministic rather than racing real inference.
@MainActor
final class RemoteVideoFrameTapTests: XCTestCase {

    // MARK: - Doubles

    /// A detector whose timing and outcome the test controls.
    private final class StubDetector: FrameDetecting, @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        private var _lastOrientation: CGImagePropertyOrientation?
        private var _lastOrientedSize: CGSize?

        /// Blocks `detect` until signalled, for the one-in-flight test.
        let gate = DispatchSemaphore(value: 0)
        var isGated = false
        var errorToThrow: Error?
        var objectsToReturn: [DetectedObject] = []

        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _callCount
        }
        var lastOrientation: CGImagePropertyOrientation? {
            lock.lock(); defer { lock.unlock() }
            return _lastOrientation
        }
        var lastOrientedSize: CGSize? {
            lock.lock(); defer { lock.unlock() }
            return _lastOrientedSize
        }

        func detect(
            in pixelBuffer: CVPixelBuffer,
            orientation: CGImagePropertyOrientation,
            orientedSize: CGSize
        ) throws -> DetectionFrame {
            lock.lock()
            _callCount += 1
            _lastOrientation = orientation
            _lastOrientedSize = orientedSize
            lock.unlock()

            if isGated { gate.wait() }
            if let errorToThrow { throw errorToThrow }
            return DetectionFrame(objects: objectsToReturn, sourceSize: orientedSize)
        }
    }

    /// A manually advanced clock, so throttling doesn't depend on wall time.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TimeInterval = 1_000

        var now: TimeInterval {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func advance(by interval: TimeInterval) {
            lock.lock(); value += interval; lock.unlock()
        }
    }

    /// Collects main-actor callbacks.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var _frames: [DetectionFrame] = []
        private var _errors: [YOLODetectionError] = []

        var frames: [DetectionFrame] {
            lock.lock(); defer { lock.unlock() }
            return _frames
        }
        var errors: [YOLODetectionError] {
            lock.lock(); defer { lock.unlock() }
            return _errors
        }
        func append(_ frame: DetectionFrame) {
            lock.lock(); _frames.append(frame); lock.unlock()
        }
        func append(_ error: YOLODetectionError) {
            lock.lock(); _errors.append(error); lock.unlock()
        }
    }

    // MARK: - Fixtures

    private func makeFrame(
        width: Int = 640,
        height: Int = 480,
        rotation: RTCVideoRotation = ._0
    ) -> RTCVideoFrame {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary,
            &buffer
        )
        return RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: buffer!),
            rotation: rotation,
            timeStampNs: 0
        )
    }

    /// An I420 frame - what a software VP8 decode produces. Not backed by a
    /// `CVPixelBuffer`.
    private func makeI420Frame(width: Int = 64, height: Int = 48) -> RTCVideoFrame {
        RTCVideoFrame(
            buffer: RTCI420Buffer(width: Int32(width), height: Int32(height)),
            rotation: ._0,
            timeStampNs: 0
        )
    }

    private struct Harness {
        let tap: RemoteVideoFrameTap
        let detector: StubDetector
        let clock: TestClock
        let sink: Sink
    }

    private func makeHarness(minimumInterval: TimeInterval = 1.0 / 3.0) -> Harness {
        let detector = StubDetector()
        let clock = TestClock()
        let sink = Sink()
        let tap = RemoteVideoFrameTap(
            detector: detector,
            minimumInterval: minimumInterval,
            now: { clock.now },
            onResult: { sink.append($0) },
            onFailure: { sink.append($0) }
        )
        return Harness(tap: tap, detector: detector, clock: clock, sink: sink)
    }

    /// Waits for the tap's background queue to catch up.
    ///
    /// Suspends rather than blocking: these tests run on the main actor, and
    /// the tap delivers its callbacks with `Task { @MainActor }`. Spinning on
    /// `usleep` here would starve exactly the thing being waited for.
    @discardableResult
    private func waitForInference(
        _ harness: Harness,
        toReach count: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        await poll(timeout: timeout) { harness.detector.callCount >= count }
    }

    /// Generic async poll.
    @discardableResult
    private func poll(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    /// Waits until no inference is in flight.
    ///
    /// `waitForInference` returns when the detector has been *entered*; the
    /// tap is still busy until it returns. Rendering a frame in that window
    /// gets it dropped by the one-in-flight rule, which is correct behaviour
    /// and a race in any test that doesn't account for it.
    private func waitUntilIdle(_ harness: Harness) async {
        await poll { !harness.tap.isBusy }
    }

    /// Lets queued work settle without blocking the main actor.
    private func letQueuedWorkSettle(_ duration: Duration = .milliseconds(60)) async {
        try? await Task.sleep(for: duration)
    }

    /// Feeds frames until the detector has run `count` times.
    ///
    /// Needed because `renderFrame` drops anything arriving while an earlier
    /// inference is still in flight - so a single call right after the
    /// previous one started is not guaranteed to be sampled.
    @discardableResult
    private func feed(
        _ harness: Harness,
        untilCallCount count: Int,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if harness.detector.callCount >= count { return true }
            harness.tap.renderFrame(makeFrame())
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return harness.detector.callCount >= count
    }

    // MARK: - Throttling

    /// The core protection: a 30 FPS stream must not mean 30 inferences a
    /// second.
    func test_framesArrivingFasterThanTheIntervalAreDropped() async {
        let harness = makeHarness(minimumInterval: 1.0 / 3.0)

        // Ten frames, all at the same instant.
        for _ in 0..<10 {
            harness.tap.renderFrame(makeFrame())
        }
        await waitForInference(harness, toReach: 1)

        XCTAssertEqual(harness.detector.callCount, 1, "only the first frame should be sampled")
        XCTAssertEqual(harness.tap.statistics.processed, 1)
        XCTAssertEqual(harness.tap.statistics.dropped, 9)
    }

    func test_aFrameAfterTheIntervalIsSampled() async {
        let harness = makeHarness(minimumInterval: 1.0 / 3.0)

        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)
        await waitUntilIdle(harness)

        harness.clock.advance(by: 0.34)
        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 2)

        XCTAssertEqual(harness.detector.callCount, 2)
    }

    func test_aFrameJustInsideTheIntervalIsStillDropped() async {
        let harness = makeHarness(minimumInterval: 1.0 / 3.0)
        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)
        await waitUntilIdle(harness)

        harness.clock.advance(by: 0.3) // < 1/3
        harness.tap.renderFrame(makeFrame())
        await letQueuedWorkSettle()

        XCTAssertEqual(harness.detector.callCount, 1)
    }

    /// At the default 3 FPS against 30 FPS video, roughly nine frames in ten
    /// are dropped.
    func test_theDefaultRateSamplesAboutThreeFramesPerSecond() async {
        let harness = makeHarness(minimumInterval: RemoteVideoFrameTap.defaultMinimumInterval)

        // One second of 30 FPS video. Waiting for idle after each frame
        // keeps the count deterministic: otherwise a frame that the throttle
        // would admit can still be dropped because the previous inference
        // hasn't unwound yet.
        for _ in 0..<30 {
            harness.tap.renderFrame(makeFrame())
            await waitUntilIdle(harness)
            harness.clock.advance(by: 1.0 / 30.0)
        }

        XCTAssertEqual(harness.detector.callCount, 3, "≈3 FPS")
        XCTAssertEqual(RemoteVideoFrameTap.defaultMinimumInterval, 1.0 / 3.0, accuracy: 0.0001)
    }

    // MARK: - One in flight

    /// No queue: a frame arriving while inference is running is discarded,
    /// not buffered. Otherwise a slow device accumulates stale frames
    /// unboundedly.
    func test_framesArrivingDuringInferenceAreDroppedNotQueued() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.detector.isGated = true

        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)
        XCTAssertEqual(harness.detector.callCount, 1)

        // These all arrive while the first inference is still blocked.
        for _ in 0..<5 {
            harness.tap.renderFrame(makeFrame())
        }
        await letQueuedWorkSettle()
        XCTAssertEqual(harness.detector.callCount, 1, "nothing should have been queued behind it")

        harness.detector.gate.signal()
        await letQueuedWorkSettle()

        // Still one: the dropped frames were discarded, not deferred.
        XCTAssertEqual(harness.detector.callCount, 1)
        XCTAssertEqual(harness.tap.statistics.dropped, 5)
    }

    func test_samplingResumesAfterInferenceFinishes() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.detector.isGated = true
        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)

        harness.detector.gate.signal()
        harness.detector.isGated = false
        await waitUntilIdle(harness)

        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 2)

        XCTAssertEqual(harness.detector.callCount, 2)
    }

    // MARK: - Enable / disable

    func test_aDisabledTapDropsEverythingWithoutInferring() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.tap.setEnabled(false)

        for _ in 0..<5 { harness.tap.renderFrame(makeFrame()) }
        await letQueuedWorkSettle()

        XCTAssertEqual(harness.detector.callCount, 0)
        XCTAssertFalse(harness.tap.isActive)
    }

    func test_reEnablingResumesSampling() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.tap.setEnabled(false)
        harness.tap.renderFrame(makeFrame())
        await letQueuedWorkSettle()
        XCTAssertEqual(harness.detector.callCount, 0)

        harness.tap.setEnabled(true)
        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)

        XCTAssertEqual(harness.detector.callCount, 1)
        XCTAssertTrue(harness.tap.isActive)
    }

    // MARK: - Cancellation

    func test_aCancelledTapStopsSampling() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.tap.cancel()

        for _ in 0..<5 { harness.tap.renderFrame(makeFrame()) }
        await letQueuedWorkSettle()

        XCTAssertEqual(harness.detector.callCount, 0)
        XCTAssertFalse(harness.tap.isActive)
    }

    /// The reconnect case: an inference started under the old session must
    /// not paint boxes over the new one.
    func test_aResultIsDiscardedIfTheTapIsCancelledMidInference() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.detector.isGated = true
        harness.detector.objectsToReturn = [
            DetectedObject(label: "banana", confidence: 0.9,
                           boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)),
        ]

        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)

        // Session ends while Vision is still running.
        harness.tap.cancel()
        harness.detector.gate.signal()
        await letQueuedWorkSettle()

        XCTAssertTrue(harness.sink.frames.isEmpty, "a result from a cancelled tap must not be delivered")
    }

    func test_cancellingIsIdempotent() async {
        let harness = makeHarness()
        harness.tap.cancel()
        harness.tap.cancel()

        XCTAssertFalse(harness.tap.isActive)
    }

    // MARK: - Delivery

    func test_aSuccessfulResultIsDelivered() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.detector.objectsToReturn = [
            DetectedObject(label: "apple", confidence: 0.8,
                           boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)),
        ]

        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)
        await poll { !harness.sink.frames.isEmpty }

        XCTAssertEqual(harness.sink.frames.first?.objects.first?.label, "apple")
    }

    func test_aNilFrameIsIgnored() async {
        let harness = makeHarness(minimumInterval: 0)

        harness.tap.renderFrame(nil)
        await letQueuedWorkSettle()

        XCTAssertEqual(harness.detector.callCount, 0)
        XCTAssertEqual(harness.tap.statistics.processed, 0)
    }

    // MARK: - Rotation and geometry passed to the detector

    func test_frameRotationIsTranslatedForVision() async {
        let cases: [(RTCVideoRotation, CGImagePropertyOrientation)] = [
            (._0, .up), (._90, .right), (._180, .down), (._270, .left),
        ]

        for (rtcRotation, expected) in cases {
            let harness = makeHarness(minimumInterval: 0)
            harness.tap.renderFrame(makeFrame(rotation: rtcRotation))
            await waitForInference(harness, toReach: 1)

            XCTAssertEqual(harness.detector.lastOrientation, expected, "\(rtcRotation.rawValue)°")
        }
    }

    /// A 90°-rotated landscape frame is displayed portrait, and that is the
    /// size the overlay must map against.
    func test_aQuarterTurnedFrameReportsItsDisplayedSize() async {
        let harness = makeHarness(minimumInterval: 0)

        harness.tap.renderFrame(makeFrame(width: 1280, height: 720, rotation: ._90))
        await waitForInference(harness, toReach: 1)

        XCTAssertEqual(harness.detector.lastOrientedSize, CGSize(width: 720, height: 1280))
    }

    func test_anUnrotatedFrameKeepsItsSize() async {
        let harness = makeHarness(minimumInterval: 0)

        harness.tap.renderFrame(makeFrame(width: 1280, height: 720, rotation: ._0))
        await waitForInference(harness, toReach: 1)

        XCTAssertEqual(harness.detector.lastOrientedSize, CGSize(width: 1280, height: 720))
    }

    func test_rtcRotationMapsOntoTheDomainRotation() async {
        XCTAssertEqual(RemoteVideoFrameTap.rotation(for: ._0), .none)
        XCTAssertEqual(RemoteVideoFrameTap.rotation(for: ._90), .ninety)
        XCTAssertEqual(RemoteVideoFrameTap.rotation(for: ._180), .oneEighty)
        XCTAssertEqual(RemoteVideoFrameTap.rotation(for: ._270), .twoSeventy)
    }

    // MARK: - Errors

    /// Software-decoded video isn't a `CVPixelBuffer`. Reported rather than
    /// silently producing nothing.
    func test_anI420FrameIsReportedAsAnUnsupportedFormat() async {
        let harness = makeHarness(minimumInterval: 0)

        harness.tap.renderFrame(makeI420Frame())
        await poll { !harness.sink.errors.isEmpty }

        XCTAssertEqual(harness.sink.errors.first, .unsupportedPixelFormat)
        XCTAssertEqual(harness.detector.callCount, 0, "the detector should never be reached")
    }

    /// A terminal failure must be reported once, not three times a second.
    func test_aTerminalFailureIsReportedOnlyOnce() async {
        let harness = makeHarness(minimumInterval: 0)

        for _ in 0..<5 {
            harness.tap.renderFrame(makeI420Frame())
            await letQueuedWorkSettle()
        }

        XCTAssertEqual(harness.sink.errors.count, 1, "got \(harness.sink.errors)")
    }

    func test_aTerminalFailureStopsFurtherSampling() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.tap.renderFrame(makeI420Frame())
        await poll { !harness.sink.errors.isEmpty }

        // A good frame afterwards: still ignored, because the tap has given up.
        harness.tap.renderFrame(makeFrame())
        await letQueuedWorkSettle()

        XCTAssertEqual(harness.detector.callCount, 0)
    }

    /// A recoverable failure keeps the tap alive - the next frame might work.
    func test_aRecoverableFailureDoesNotStopTheTap() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.detector.errorToThrow = YOLODetectionError.inferenceFailed(reason: "transient")

        harness.tap.renderFrame(makeFrame())
        await waitForInference(harness, toReach: 1)

        harness.detector.errorToThrow = nil
        // Keep offering frames: one sent while the previous inference is
        // still unwinding would be dropped by the one-in-flight rule.
        await feed(harness, untilCallCount: 2)

        // At least two: `feed` retries, so it can overshoot. What matters is
        // that sampling resumed at all after the failed frame.
        XCTAssertGreaterThanOrEqual(
            harness.detector.callCount, 2,
            "the tap should keep sampling after a bad frame"
        )
    }

    func test_anErrorIsNotDeliveredAfterCancellation() async {
        let harness = makeHarness(minimumInterval: 0)
        harness.tap.cancel()

        harness.tap.renderFrame(makeI420Frame())
        await letQueuedWorkSettle()

        XCTAssertTrue(harness.sink.errors.isEmpty)
    }
}
