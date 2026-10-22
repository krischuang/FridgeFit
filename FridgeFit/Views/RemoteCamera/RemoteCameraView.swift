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
    /// Reports a completed save so the presenting flow can take the user
    /// somewhere useful. The pantry has already been written to by the time
    /// this runs - it carries the summary, it does not perform the save.
    ///
    /// `nil` leaves the screen exactly as it was: the camera stays open and
    /// the saved-ingredients note below is the whole feedback. Both real
    /// entry points pass one; previews and tests are what take the default.
    private let onIngredientsSaved: ((AddDetectedIngredientsSummary) -> Void)?

    init(
        identity: DeviceIdentity,
        initialCamera: RegisteredDevice? = nil,
        onPresentationChange: ((Bool) -> Void)? = nil,
        onIngredientsSaved: ((AddDetectedIngredientsSummary) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: RemoteCameraViewModel(identity: identity))
        self.initialCamera = initialCamera
        self.onPresentationChange = onPresentationChange
        self.onIngredientsSaved = onIngredientsSaved
    }

    init(
        viewModel: RemoteCameraViewModel,
        initialCamera: RegisteredDevice? = nil,
        onPresentationChange: ((Bool) -> Void)? = nil,
        onIngredientsSaved: ((AddDetectedIngredientsSummary) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.initialCamera = initialCamera
        self.onPresentationChange = onPresentationChange
        self.onIngredientsSaved = onIngredientsSaved
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

                savedIngredientsFeedback

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
        // Connecting first, and deliberately not after `start()`. `start()`
        // registers this device and attaches the discovery listener, neither
        // of which a session depends on - the camera learns who is calling
        // from the session document itself. Awaiting its Firestore write
        // before dialling put a full round trip between arriving here and the
        // offer, for a registration the previous screen had already made.
        .task {
            connectInitialCameraIfNeeded()
            await viewModel.start()
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
        // Both the analysis and the photo are read here, and `currentAnalysis`
        // guarantees they are the same capture - the sheet cannot open
        // against a mismatched pair.
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
                } onSaveCompleted: { summary in
                    onIngredientsSaved?(summary)
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
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(FridgeFitTheme.ColorToken.brandFill, in: Circle())
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
                presentReviewIfCurrentAnalysis()
            } catch {
                viewModel.reportLocalImageFailure()
            }
        }
    }

    // MARK: - Live session

    private var liveControlContent: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
            // Connection details sit directly under the device header they
            // describe, so the preview is the first thing below them rather
            // than the top of the screen.
            connectionCard
            livePreview

            if viewModel.isConnected {
                // The headline action is kept against the bottom edge of the
                // preview - what you analyse is what you can see.
                analyseSection
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
        // Capped rather than full-width: at the surface's 3:4 ratio an iPhone
        // screen's width makes the preview tall enough to push the capture
        // button off screen. The height bound shrinks the width with it, so
        // the aspect ratio - and the detection overlay's alignment with the
        // frame - is unchanged, and the box is centred instead of hugging
        // the stack's leading edge.
        .frame(maxHeight: Self.livePreviewMaxHeight)
        .frame(maxWidth: .infinity)
    }

    /// Chosen so the preview, the connection card above it and the capture
    /// button below it all fit on the shortest supported screen.
    private static let livePreviewMaxHeight: CGFloat = 420

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

    /// The capture action and anything it has to report, kept together so the
    /// failure and unavailable notices stay attached to the button.
    private var analyseSection: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            analyseButton
        }
    }

    private var liveActions: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
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
            Task {
                await viewModel.captureAndAnalyse()
                presentReviewIfCurrentAnalysis()
            }
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

    /// Opens review only after the awaited analysis still belongs to the
    /// snapshot on screen. A failed or superseded capture therefore leaves
    /// the sheet closed.
    private func presentReviewIfCurrentAnalysis() {
        guard viewModel.currentAnalysis != nil, viewModel.snapshot != nil else { return }
        isReviewingIngredients = true
    }

    /// Food-detection toggle, status, and what it found.
    ///
    /// Sits below the preview and the capture button, so the live view it
    /// draws boxes over is still on screen while the toggle is read.
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
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                if viewModel.detectionStatus.isRunning {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(
                        viewModel.detectionCount == 1
                            ? "1 item"
                            : "\(viewModel.detectionCount) items"
                    )
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    if viewModel.reviewCount > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(viewModel.reviewCount) to confirm")
                            .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
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
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                }
            }

            if let reason = viewModel.detectorFallbackReason {
                // The ingredient model failed to load. Say so plainly - the
                // fallback covers ten COCO classes, not the full taxonomy.
                Text("Using the COCO fallback model (10 food classes). \(reason)")
                    .font(.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            }

            if let reason = viewModel.detectionStatus.unavailableReason {
                // Shown instead of boxes - never mock detections.
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
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

    @ViewBuilder
    private var savedIngredientsFeedback: some View {
        if !confirmedIngredients.isEmpty {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Label(
                    "Saved \(confirmedIngredients.count) to your pantry: "
                    + confirmedIngredients.map(\.name).joined(separator: ", "),
                    systemImage: "checkmark.circle.fill"
                )
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                Text("Open the Pantry tab to see them.")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            .padding(FridgeFitTheme.Spacing.medium)
            .fridgeFitCardSurface()
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

}
