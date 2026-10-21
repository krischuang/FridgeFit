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
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
                remoteCameraHeader

                if viewModel.isConnected || selectedCamera != nil || initialCamera != nil {
                    liveControlContent
                } else {
                    unselectedCameraContent
                }

                if let snapshot = viewModel.snapshot {
                    snapshotSection(snapshot)
                }

                if let errorMessage = viewModel.errorMessage {
                    connectionErrorCard(errorMessage)
                }

                connectionRecommendation
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.vertical, FridgeFitTheme.Spacing.medium)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
        .navigationTitle("Remote Camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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

    @ViewBuilder
    private var remoteCameraHeader: some View {
        if let cameraName = viewModel.connectedCameraName ?? selectedCamera?.deviceName ?? initialCamera?.deviceName {
            HStack(alignment: .center, spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: "video.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 44, height: 44)
                .background(
                    FridgeFitTheme.ColorToken.successBackground,
                    in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(cameraName)
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .lineLimit(1)
                Text("Live kitchen view")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            Spacer(minLength: FridgeFitTheme.Spacing.small)

            FridgeFitStatusBadge(
                title: LocalizedStringKey(viewModel.status.displayName),
                systemImage: RemoteCameraPresentation.symbol(for: viewModel.status),
                tone: statusTone
            )
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var unselectedCameraContent: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
            unselectedCameraIntroduction
            cameraPickerSection(includeLocalPhoto: false)
            secondaryLocalPhotoSection
        }
    }

    private var unselectedCameraIntroduction: some View {
        HStack(alignment: .center, spacing: FridgeFitTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    .fill(FridgeFitTheme.ColorToken.successBackground)
                    .frame(width: 58, height: 52)
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                Image(systemName: "camera.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.card)
                    .padding(4)
                    .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                    .offset(x: 22, y: 17)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("View your kitchen from another phone")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Choose a kitchen camera to start viewing its live feed.")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
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

    private func cameraPickerSection(includeLocalPhoto: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("Choose a kitchen camera")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            if viewModel.availableCameras.isEmpty {
                Label(RemoteCameraError.noCameraDevicesFound.message, systemImage: "video.slash")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(FridgeFitTheme.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        FridgeFitTheme.ColorToken.disabledSurface,
                        in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    )
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
                                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(FridgeFitTheme.Spacing.medium)
                    .fridgeFitCardSurface()
                }
            }

            if viewModel.status == .connecting {
                Label("Connecting…", systemImage: "ellipsis.circle")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            if includeLocalPhoto {
                localPhotoSection
            }
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
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Analyse a photo from this iPhone")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("""
            Same models, same review step - no second device needed. Useful \
            for checking recognition on real food.
            """)
            .font(FridgeFitTheme.Typography.caption)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            // Read on the main actor, before the label closure. `PhotosPicker`
            // takes its label as a nonisolated closure, so touching the
            // `@MainActor` view model inside it is a concurrency violation -
            // these two reads are the same values, taken where they are legal.
            let isAnalysing = viewModel.isAnalyzingSnapshot
            let analysisMessage = viewModel.analysisPhase.message ?? "Analysing…"

            PhotosPicker(selection: $localPhotoItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 8) {
                    if isAnalysing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    Text(isAnalysing ? analysisMessage : "Choose Photo")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
            .disabled(viewModel.isAnalyzingSnapshot)
            .accessibilityIdentifier("analyse-local-photo")
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var secondaryLocalPhotoSection: some View {
        DisclosureGroup {
            localPhotoSection
                .padding(.top, FridgeFitTheme.Spacing.small)
        } label: {
            Label("Analyse a photo from this iPhone", systemImage: "photo.on.rectangle.angled")
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
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

    private var liveControlContent: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
            livePreview
            connectionCard

            if viewModel.isConnected {
                detectionControls
                liveActions
            } else {
                disconnectedActions
            }

            secondaryLocalPhotoSection

            if selectedCamera != nil {
                DisclosureGroup("Choose a different camera") {
                    cameraPickerSection(includeLocalPhoto: false)
                        .padding(.top, FridgeFitTheme.Spacing.medium)
                }
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .padding(FridgeFitTheme.Spacing.medium)
                .fridgeFitCardSurface()
            }
        }
    }

    private var livePreview: some View {
        VideoSurface(
            track: viewModel.remoteVideoTrack,
            // Gated on confirmed frames, not on ICE being connected - a
            // connected session with no media shows the placeholder and
            // the reason, never a black rectangle passed off as video.
            isLive: viewModel.isReceivingVideo,
            placeholder: placeholderText,
            onStatusChange: { viewModel.recordRenderedVideo($0) }
        )
        .overlay(alignment: .topLeading) {
            if viewModel.isReceivingVideo {
                FridgeFitStatusBadge(title: "Live", systemImage: "dot.radiowaves.left.and.right", tone: .success)
                    .padding(FridgeFitTheme.Spacing.medium)
            }
        }
        // Boxes are drawn over the video, inside the same rounded shape,
        // and never intercept touches.
        .overlay {
            if viewModel.isReceivingVideo && viewModel.isDetectionEnabled {
                YOLODetectionOverlay(detections: viewModel.ingredients)
                    .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card))
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                .stroke(FridgeFitTheme.ColorToken.border.opacity(0.65), lineWidth: 1)
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                ConnectionStatusLabel(status: viewModel.status)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                Spacer()
                if viewModel.isReceivingVideo {
                    FridgeFitStatusBadge(title: "Video live", systemImage: "waveform", tone: .success)
                }
            }

            LabeledContent("Camera") {
                Text(viewModel.connectedCameraName ?? selectedCamera?.deviceName ?? initialCamera?.deviceName ?? "Unknown")
                    .multilineTextAlignment(.trailing)
            }
            .font(FridgeFitTheme.Typography.supporting)
            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            if let progress = viewModel.transferProgress {
                Label(progress, systemImage: "arrow.down.circle")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var liveActions: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            analyseButton

            Button {
                viewModel.requestCapture()
            } label: {
                Label(
                    viewModel.isAwaitingSnapshot ? "Waiting for photo…" : "Capture Photo",
                    systemImage: "camera.shutter.button"
                )
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
            .disabled(!viewModel.canRequestCapture || viewModel.isAnalyzingSnapshot)

            Button {
                viewModel.requestCameraSwitch()
            } label: {
                Label("Switch Remote Camera", systemImage: "arrow.triangle.2.circlepath.camera")
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())

            connectionActions
        }
    }

    private var disconnectedActions: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            if let selectedCamera {
                Button {
                    Task { await viewModel.reconnect(to: selectedCamera) }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .buttonStyle(FridgeFitPrimaryButtonStyle())
            }

            connectionActions
        }
    }

    private var connectionActions: some View {
        Button(role: .destructive) {
            Task { await viewModel.disconnect() }
        } label: {
            Label("Disconnect", systemImage: "xmark.circle")
        }
        .buttonStyle(FridgeFitSecondaryButtonStyle())
        .tint(FridgeFitTheme.ColorToken.danger)
    }

    private var connectionRecommendation: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Label(
                "For the most reliable connection, use the same Wi-Fi network on both phones. Some networks may prevent a connection.",
                systemImage: "wifi"
            )
            .font(FridgeFitTheme.Typography.caption)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            DisclosureGroup("Connection details") {
                Text(viewModel.connectivityCaveat)
                    .font(.caption2)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(.top, FridgeFitTheme.Spacing.xSmall)
            }
            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .buttonStyle(FridgeFitPrimaryButtonStyle())
        .disabled(!viewModel.canRequestCapture || viewModel.isAnalyzingSnapshot)
        .accessibilityIdentifier("analyse-ingredients")

        if let failure = viewModel.analysisPhase.failureReason {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text(failure)
                    Button("Dismiss") { viewModel.dismissAnalysisFailure() }
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                }
            }
            .font(FridgeFitTheme.Typography.caption)
            .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            .padding(FridgeFitTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FridgeFitTheme.ColorToken.warningBackground,
                in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
            )
        }

        if let explanation = viewModel.snapshotAnalysisUnavailable {
            Label(explanation, systemImage: "info.circle")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
    }

    /// Food-detection toggle, status, and what it found.
    ///
    /// Sits between the video and the connection details so the thing it
    /// describes is directly above it.
    private var detectionControls: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Toggle(isOn: $viewModel.isDetectionEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Food Detection", systemImage: "viewfinder")
                    Text("Show recognised ingredients over the live view.")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
            }
            .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
            .tint(FridgeFitTheme.ColorToken.primary)

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
            .font(FridgeFitTheme.Typography.caption)
            .accessibilityElement(children: .combine)

            .accessibilityLabel(
                "Detection \(viewModel.detectionStatus.displayName), "
                + "\(viewModel.detectionCount) items, \(viewModel.reviewCount) to confirm"
            )

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

            detectionDetails
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    @ViewBuilder
    private var detectionDetails: some View {
        if viewModel.detectionStatus.isRunning,
           viewModel.withheldCandidateCount > 0 || viewModel.videoFrameStatistics != nil || viewModel.renderedVideoStatus != nil {
            DisclosureGroup("Detection details") {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    if viewModel.withheldCandidateCount > 0 {
                        Text("\(viewModel.withheldCandidateCount) lower-confidence candidates remain available when you analyse a photo.")
                            .accessibilityIdentifier("withheld-candidates")
                    }

                    if let statistics = viewModel.videoFrameStatistics {
                        Text("Frames received: \(statistics.total) (\(statistics.processed) analysed, \(statistics.dropped) skipped)")
                            .accessibilityIdentifier("frame-statistics")
                    }

                    if let rendered = viewModel.renderedVideoStatus {
                        Text("Preview: \(rendered.framesRendered) frames rendered")
                            .accessibilityIdentifier("render-statistics")
                    }
                }
                .font(.caption2)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .padding(.top, FridgeFitTheme.Spacing.xSmall)
            }
            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
        }
    }

    private var detectionIndicatorColour: Color {
        switch viewModel.detectionStatus {
        case .running: return FridgeFitTheme.ColorToken.primary
        case .waitingForVideo: return FridgeFitTheme.ColorToken.warningText
        case .off: return FridgeFitTheme.ColorToken.textSecondary
        case .unavailable: return FridgeFitTheme.ColorToken.danger
        }
    }

    private var statusTone: FridgeFitStatusTone {
        switch viewModel.status {
        case .connected:
            return .success
        case .connecting, .reconnecting:
            return .warning
        case .failed:
            return .danger
        case .available, .offline, .disconnected:
            return .neutral
        }
    }

    private func connectionErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Connection issue")
                    .font(FridgeFitTheme.Typography.cardTitle)
                Text(message)
                    .font(FridgeFitTheme.Typography.caption)
            }
        }
        .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            FridgeFitTheme.ColorToken.warningBackground,
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
        )
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
