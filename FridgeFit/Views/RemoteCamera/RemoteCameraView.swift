//
//  RemoteCameraView.swift
//  FridgeFit
//

import PhotosUI
import SwiftUI

/// Screen C: watch the other iPhone's camera, take a photo with it, and turn
/// that photo into pantry ingredients.
///
/// Nothing on this screen writes to the pantry directly. The only path to
/// storage runs through the review sheet, which sends explicitly accepted
/// rows to `AddDetectedIngredientsUseCase` - the same use case, repository
/// and validation the receipt scanner uses.
struct RemoteCameraView: View {
    @StateObject private var viewModel: RemoteCameraViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedCamera: RegisteredDevice?
    @State private var hasConnectedInitialCamera = false
    @State private var isReviewingIngredients = false
    @State private var confirmedIngredients: [ConfirmedIngredient] = []
    @Environment(\.pantryRepository) private var pantryRepository
    @State private var localPhotoItem: PhotosPickerItem?

    private let initialCamera: RegisteredDevice?
    private let onPresentationChange: ((Bool) -> Void)?

    init(
        identity: DeviceIdentity,
        initialCamera: RegisteredDevice? = nil,
        onPresentationChange: ((Bool) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: RemoteCameraViewModel(identity: identity))
        self.initialCamera = initialCamera
        self.onPresentationChange = onPresentationChange
    }

    init(
        viewModel: RemoteCameraViewModel,
        initialCamera: RegisteredDevice? = nil,
        onPresentationChange: ((Bool) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.initialCamera = initialCamera
        self.onPresentationChange = onPresentationChange
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isConnected {
                    liveSection
                } else {
                    cameraPickerSection
                }

                if let snapshot = viewModel.snapshot {
                    snapshotSection(snapshot)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(viewModel.connectivityCaveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Remote Camera")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.start()
            connectInitialCameraIfNeeded()
        }
        .onAppear { onPresentationChange?(true) }
        .onDisappear {
            onPresentationChange?(false)
            Task { await viewModel.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background || phase == .inactive else { return }
            Task { await viewModel.stop() }
        }
        // Presented from the analysis summary. Both the analysis and the photo
        // are read here, and `currentAnalysis` guarantees they are the same
        // capture - the sheet cannot open against a mismatched pair.
        .sheet(isPresented: $isReviewingIngredients) {
            if let analysis = viewModel.currentAnalysis, let snapshot = viewModel.snapshot {
                IngredientReviewView(
                    analysis: analysis,
                    snapshot: snapshot,
                    // The same use case the receipt scanner uses, over the
                    // app's shared repository. The review sheet has no
                    // Firestore access of its own.
                    addIngredientsUseCase: AddDetectedIngredientsUseCase(
                        pantryRepository: pantryRepository
                    )
                ) { confirmed in
                    confirmedIngredients = confirmed
                }
            }
        }
        .onChange(of: localPhotoItem) { _, item in
            guard let item else { return }
            loadLocalPhoto(item)
        }
        .onChange(of: viewModel.snapshotId) { _, _ in
            // A new photo invalidates the previous confirmation list.
            confirmedIngredients = []
        }
    }

    // MARK: - Choosing a camera

    /// The role-selection flow forwards a real discovery result here. The
    /// existing Remote Camera view model remains the sole owner of the actual
    /// connection and this guard ensures a task restart cannot connect twice.
    private func connectInitialCameraIfNeeded() {
        guard let initialCamera, !hasConnectedInitialCamera else { return }
        hasConnectedInitialCamera = true
        selectedCamera = initialCamera
        Task { await viewModel.connect(to: initialCamera) }
    }

    private var cameraPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Cameras")
                .font(.headline)

            if viewModel.availableCameras.isEmpty {
                Text(RemoteCameraError.noCameraDevicesFound.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.availableCameras) { camera in
                    Button {
                        selectedCamera = camera
                        Task { await viewModel.connect(to: camera) }
                    } label: {
                        HStack {
                            DeviceRow(device: camera, status: .available)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if viewModel.status == .connecting {
                Label("Connecting…", systemImage: "ellipsis.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 4)
            localPhotoSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Run the real pipeline over a photo from this iPhone.
    ///
    /// Deliberately available without a connection. The remote-camera flow
    /// needs two iPhones, which makes the thing most in need of device
    /// testing - whether Apple Vision classification works on hardware - the
    /// hardest to reach. This needs one device and no network.
    @ViewBuilder
    private var localPhotoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analyse a photo from this iPhone")
                .font(.subheadline.weight(.semibold))
            Text("""
            Same models, same review step - no second device needed. Useful \
            for checking recognition on real food.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            PhotosPicker(selection: $localPhotoItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    if viewModel.isAnalyzingSnapshot {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    Text(viewModel.isAnalyzingSnapshot
                         ? (viewModel.analysisPhase.message ?? "Analysing…")
                         : "Choose Photo")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isAnalyzingSnapshot)
            .accessibilityIdentifier("analyse-local-photo")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadLocalPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    viewModel.reportLocalImageFailure()
                    return
                }
                await viewModel.analyseLocalImage(image)
            } catch {
                viewModel.reportLocalImageFailure()
            }
        }
    }

    // MARK: - Live session

    private var liveSection: some View {
        VStack(spacing: 16) {
            VideoSurface(
                track: viewModel.remoteVideoTrack,
                // Gated on confirmed frames, not on ICE being connected - a
                // connected session with no media shows the placeholder and
                // the reason, never a black rectangle passed off as video.
                isLive: viewModel.isReceivingVideo,
                placeholder: placeholderText,
                onStatusChange: { viewModel.recordRenderedVideo($0) }
            )
            // Boxes are drawn over the video, inside the same rounded shape,
            // and never intercept touches.
            .overlay {
                if viewModel.isReceivingVideo && viewModel.isDetectionEnabled {
                    YOLODetectionOverlay(detections: viewModel.ingredients)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

            detectionControls

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ConnectionStatusLabel(status: viewModel.status)
                    Spacer()
                    if viewModel.isReceivingVideo {
                        Label("Video live", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                LabeledContent("Camera") {
                    Text(viewModel.connectedCameraName ?? "Unknown")
                }
                if let progress = viewModel.transferProgress {
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding()
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 12) {
                analyseButton

                Button {
                    viewModel.requestCapture()
                } label: {
                    Label(
                        viewModel.isAwaitingSnapshot ? "Waiting for photo…" : "Capture Photo",
                        systemImage: "camera.shutter.button"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canRequestCapture || viewModel.isAnalyzingSnapshot)

                Button {
                    viewModel.requestCameraSwitch()
                } label: {
                    Label("Switch Remote Camera", systemImage: "arrow.triangle.2.circlepath.camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                PhotosPicker(selection: $localPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Analyse a Photo from This iPhone", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isAnalyzingSnapshot)

                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.disconnect() }
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if let selectedCamera {
                        Button {
                            Task { await viewModel.reconnect(to: selectedCamera) }
                        } label: {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    /// The headline action: capture a photo and run hybrid recognition on it.
    ///
    /// Capture and analysis report separately, because a 20-second transfer
    /// and a sub-second analysis feel completely different, and one label for
    /// both reads as a hang. Live video keeps playing throughout - the
    /// analysis runs on a detached task over a still.
    @ViewBuilder
    private var analyseButton: some View {
        Button {
            Task { await viewModel.captureAndAnalyse() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isAnalyzingSnapshot {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "sparkle.magnifyingglass")
                }
                Text(viewModel.analysisPhase.message ?? "Analyse Ingredients")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canRequestCapture || viewModel.isAnalyzingSnapshot)
        .accessibilityIdentifier("analyse-ingredients")

        if let failure = viewModel.analysisPhase.failureReason {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text(failure)
                Spacer()
                Button("Dismiss") { viewModel.dismissAnalysisFailure() }
                    .font(.caption)
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }

        if let explanation = viewModel.snapshotAnalysisUnavailable {
            Label(explanation, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Food-detection toggle, status, and what it found.
    ///
    /// Sits between the video and the connection details so the thing it
    /// describes is directly above it.
    private var detectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $viewModel.isDetectionEnabled) {
                Label("Food Detection", systemImage: "viewfinder")
            }
            .font(.subheadline)

            HStack(spacing: 6) {
                Circle()
                    .fill(detectionIndicatorColour)
                    .frame(width: 7, height: 7)
                Text(viewModel.detectionStatus.displayName)
                    .foregroundStyle(.secondary)
                if viewModel.detectionStatus.isRunning {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(
                        viewModel.detectionCount == 1
                            ? "1 item"
                            : "\(viewModel.detectionCount) items"
                    )
                    .foregroundStyle(.secondary)
                    if viewModel.reviewCount > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(viewModel.reviewCount) to confirm")
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if let source = viewModel.detectionSource {
                    // Which model produced these boxes. Matters most when the
                    // fallback is running, since its coverage is far smaller.
                    Text(source.shortName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .accessibilityElement(children: .combine)

            .accessibilityLabel(
                "Detection \(viewModel.detectionStatus.displayName), "
                + "\(viewModel.detectionCount) items, \(viewModel.reviewCount) to confirm"
            )

            // Frames the tap has seen. A rising number with a blank preview
            // means the track is delivering and the renderer is not drawing;
            // a stuck zero means no frames are arriving at all. "Video live"
            // cannot tell those apart - it latches on the first frame and is
            // never revisited.
            // What the filter withheld, so a demo can tell "the model found
            // nothing" from "the model found something too weak to draw".
            // Withheld candidates are not discarded - the snapshot analysis
            // works from the same list the overlay filtered down from.
            if viewModel.detectionStatus.isRunning, viewModel.withheldCandidateCount > 0 {
                Text("\(viewModel.withheldCandidateCount) below the "
                     + "\(Int(viewModel.detectionPolicy.displayThreshold * 100))% display "
                     + "threshold - hidden here, still analysed on capture")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("withheld-candidates")
            }

            if let statistics = viewModel.videoFrameStatistics {
                Text("Frames received: \(statistics.total) (\(statistics.processed) analysed, \(statistics.dropped) skipped)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("frame-statistics")
            }

            // The other half of the blank-preview diagnostic: what the view
            // on screen was actually handed, as opposed to what the tap saw.
            if let rendered = viewModel.renderedVideoStatus {
                Text("Drawn: \(rendered.framesRendered) frames · "
                     + "\(Int(rendered.lastFrameSize.width))x\(Int(rendered.lastFrameSize.height))"
                     + " rot \(rendered.lastRotationDegrees)° · "
                     + "view \(Int(rendered.viewSize.width))x\(Int(rendered.viewSize.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("render-statistics")
            }

            // Categories currently on screen, so the user can see the spread
            // at a glance without reading every box.
            if viewModel.detectionStatus.isRunning && !viewModel.ingredients.categories.isEmpty {
                HStack(spacing: 8) {
                    ForEach(viewModel.ingredients.categories, id: \.self) { category in
                        Label(category.displayName, systemImage: category.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let reason = viewModel.detectorFallbackReason {
                // The ingredient model failed to load. Say so plainly - the
                // fallback covers ten COCO classes, not the full taxonomy.
                Text("Using the COCO fallback model (10 food classes). \(reason)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let reason = viewModel.detectionStatus.unavailableReason {
                // Shown instead of boxes - never mock detections.
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var detectionIndicatorColour: Color {
        switch viewModel.detectionStatus {
        case .running: return .green
        case .waitingForVideo: return .orange
        case .off: return .secondary
        case .unavailable: return .red
        }
    }

    private var placeholderText: String {
        switch viewModel.status {
        case .connecting:
            return "Negotiating the connection…"
        case .connected:
            return "Connected. Waiting for the first video frame…"
        case .reconnecting:
            return "Connection dropped. Trying to recover…"
        case .failed:
            return "The connection failed. Try reconnecting."
        case .available, .offline, .disconnected:
            return "Not connected."
        }
    }

    // MARK: - Snapshot

    private func snapshotSection(_ snapshot: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captured Photo")
                .font(.headline)

            Image(uiImage: snapshot)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    viewModel.saveSnapshot()
                } label: {
                    Label("Save Locally", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                ShareLink(
                    item: Image(uiImage: snapshot),
                    preview: SharePreview("Fridge snapshot", image: Image(uiImage: snapshot))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            if let savedName = viewModel.savedSnapshotName {
                Text("Saved to Documents/RemoteSnapshots/\(savedName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            analysisSummarySection
            recognitionSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Summary of the hybrid analysis, with the way into the review sheet.
    ///
    /// Reads `currentAnalysis`, not `snapshotAnalysis`: a result computed from
    /// a different photo is never shown, however recent it is.
    @ViewBuilder
    private var analysisSummarySection: some View {
        if let analysis = viewModel.currentAnalysis {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Hybrid analysis", systemImage: "sparkle.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.1fs", analysis.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Said before the counts, so the chips are read in the right
                // light: "2 single" means something different when only one
                // method ran.
                if let message = analysis.classification.userMessage {
                    Label(message, systemImage: analysis.classification.capability.isExpectedLimitation
                          ? "info.circle" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(analysis.classification.capability.isExpectedLimitation
                                         ? Color.secondary : .orange)
                        .accessibilityIdentifier("analysis-capability")
                }
                if analysis.classification.isDetectorOnly {
                    Text("YOLO-only — every row needs review")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.18), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                if analysis.fused.isEmpty && analysis.packaging.lines.isEmpty {
                    Text(Self.nothingRecognisedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        tierChip("\(analysis.fused.count(of: .agreed)) agreed", .green)
                        tierChip("\(analysis.fused.count(of: .singleSource)) single", .secondary)
                        if analysis.fused.conflictCount > 0 {
                            tierChip("\(analysis.fused.conflictCount) disagree", .orange)
                        }
                    }
                }

                Button {
                    isReviewingIngredients = true
                } label: {
                    Label("Review Ingredients", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("review-ingredients")

                if !confirmedIngredients.isEmpty {
                    Label(
                        "Saved \(confirmedIngredients.count) to your pantry: "
                        + confirmedIngredients.map(\.name).joined(separator: ", "),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                    Text("Open the Pantry tab to see them.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static let nothingRecognisedMessage = """
    Nothing recognised in this photo. Meat, fish, cheese and eggs are known \
    weak spots - you can add them by hand in the review screen.
    """

    private func tierChip(_ text: String, _ colour: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(colour.opacity(0.15), in: Capsule())
            .foregroundStyle(colour)
    }

    private var recognitionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if let explanation = viewModel.recognitionUnavailableExplanation {
                Label(explanation, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let recognition = viewModel.recognition {
                if recognition.isMockData {
                    // Loud on purpose. Mock output must never be mistakable
                    // for real recognition in a screenshot or a demo.
                    Label("Mock data - not real recognition", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                ForEach(recognition.items) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text("\(Int(item.confidence * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Text("""
                Nothing here has been added to your pantry. This prototype \
                only proves the photo arrived.
                """)
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await viewModel.recognizeSnapshot() }
                } label: {
                    Label("Try Food Recognition", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
    }
}

#Preview {
    let identity = DeviceIdentity(deviceId: "preview-controller", deviceName: "Preview iPhone")
    let registry = InMemoryDeviceRegistry(seedDevices: [
        RegisteredDevice(
            deviceId: "kitchen-device",
            deviceName: "Kitchen iPhone",
            deviceRole: .camera,
            connectionStatus: .available,
            lastSeenAt: Date(),
            createdAt: Date()
        ),
    ])
    return NavigationStack {
        RemoteCameraView(
            viewModel: RemoteCameraViewModel(
                identity: identity,
                registry: registry,
                transport: InMemorySignalingTransport()
            )
        )
    }
}
