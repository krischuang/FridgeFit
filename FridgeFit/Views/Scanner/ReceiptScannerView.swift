//
//  ReceiptScannerView.swift
//  FridgeFit
//

import PhotosUI
import SwiftUI

/// Scan Receipt: take or choose a photo of a grocery receipt, read it on
/// device, then confirm what was found before anything reaches the pantry.
/// All capture and scanning actions continue to go through
/// `ReceiptScannerViewModel`.
struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ReceiptScannerViewModel
    var onFinished: (AddDetectedIngredientsSummary) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var isPresentingCamera = false
    @State private var isLoadingPickedPhoto = false
    @State private var isPresentingTips = false
    @State private var cameraAccessMessage: String?
    #if DEBUG
    @State private var isPresentingDemoCachePreparation = false
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.canScan {
                    scannerContent
                } else {
                    unavailableContent
                }
            }
            .background(FridgeFitTheme.ColorToken.canvas)
            .navigationTitle("Smart Scan Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        viewModel.cancelScan()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close receipt scanner")
                }

                #if DEBUG
                // Developer entry point for preparing the demonstration
                // receipt's cache entry. Compiled out of Release builds.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingDemoCachePreparation = true
                    } label: {
                        Image(systemName: "hammer")
                    }
                    .accessibilityLabel("Prepare demo receipt cache")
                }
                #endif

                ToolbarItem(placement: .confirmationAction) {
                    Image(systemName: "person")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.card)
                        .frame(width: 36, height: 36)
                        .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                        .accessibilityHidden(true)
                }
            }
            #if DEBUG
            .sheet(isPresented: $isPresentingDemoCachePreparation) {
                ReceiptDemoCachePreparationView()
            }
            #endif
            .sheet(isPresented: $viewModel.isPresentingReview) {
                ReceiptItemReviewView(viewModel: viewModel) { summary in
                    onFinished(summary)
                    dismiss()
                }
            }
            .sheet(isPresented: $isPresentingTips) {
                ReceiptCaptureTipsView()
                    .presentationDetents([.medium])
            }
            .fullScreenCover(isPresented: $isPresentingCamera) {
                CameraPicker(
                    onCapture: { viewModel.selectImage($0) },
                    onFailure: { viewModel.reportImageLoadFailure() }
                )
                .ignoresSafeArea()
            }
            .alert(
                "Camera Unavailable",
                isPresented: Binding(
                    get: { cameraAccessMessage != nil },
                    set: { if !$0 { cameraAccessMessage = nil } }
                )
            ) {
                Button("OK") { cameraAccessMessage = nil }
            } message: {
                Text(cameraAccessMessage ?? "")
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                loadPickedPhoto(newItem)
            }
        }
    }

    // MARK: - States

    private var scannerContent: some View {
        ScrollView {
            VStack(spacing: FridgeFitTheme.Spacing.medium) {
                if viewModel.selectedImage == nil {
                    captureLaunchSurface
                } else {
                    selectedReceiptSurface
                }

                if isLoadingPickedPhoto {
                    photoLoadingIndicator
                } else if viewModel.scanState.isScanning {
                    scanningIndicator
                } else if viewModel.selectedImage != nil {
                    selectedReceiptActions
                } else {
                    captureControls
                    parsingInfoCard
                    captureGuidance
                }

                if case .failed(let message) = viewModel.scanState {
                    scanFailureCard(message: message)
                }
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.section)
        }
        .background(FridgeFitTheme.ColorToken.canvas)
    }

    /// This is intentionally a launch surface, not a simulated live preview.
    /// Actual live capture remains in the system UIImagePickerController.
    private var captureLaunchSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
                .fill(FridgeFitTheme.ColorToken.textPrimary)

            LinearGradient(
                colors: [
                    FridgeFitTheme.ColorToken.primary.opacity(0.82),
                    FridgeFitTheme.ColorToken.textPrimary.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(FridgeFitTheme.ColorToken.card.opacity(0.3))

            ReceiptFrameGuide()
                .padding(.horizontal, 48)
                .padding(.vertical, 76)

            VStack {
                HStack {
                    captureStatusPill("Ready to scan", systemImage: "circle.fill", tint: FridgeFitTheme.ColorToken.primary)
                    Spacer()
                    captureStatusPill("Frame receipt", systemImage: "viewfinder", tint: FridgeFitTheme.ColorToken.primary)
                }

                Spacer()

                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    Label("Fit whole receipt in frame", systemImage: "document.viewfinder")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        .padding(.horizontal, FridgeFitTheme.Spacing.medium)
                        .padding(.vertical, FridgeFitTheme.Spacing.small)
                        .background(FridgeFitTheme.ColorToken.card.opacity(0.96), in: Capsule())

                    Label("Avoid glare · Hold steady", systemImage: "sun.max.fill")
                        .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.card)
                }
            }
            .padding(FridgeFitTheme.Spacing.medium)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 390)
        .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Receipt framing guide. Open the camera to photograph a receipt.")
    }

    private var selectedReceiptSurface: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Image(uiImage: viewModel.selectedImage ?? UIImage())
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 360)
                .background(FridgeFitTheme.ColorToken.textPrimary, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
                .accessibilityLabel("Selected receipt photo")

            Label("Receipt ready to read", systemImage: "checkmark.circle.fill")
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
        }
    }

    private var captureControls: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.large) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                captureControlLabel("Import", systemImage: "photo.on.rectangle")
            }
            .accessibilityLabel("Import receipt from photo library")

            Button {
                presentCamera()
            } label: {
                Image(systemName: "receipt")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.card)
                    .frame(width: 72, height: 72)
                    .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                    .overlay {
                        Circle().stroke(FridgeFitTheme.ColorToken.card, lineWidth: 4)
                    }
                    .shadow(color: FridgeFitTheme.ColorToken.primary.opacity(0.3), radius: 0, x: 0, y: 0)
                    .padding(4)
                    .background(FridgeFitTheme.ColorToken.primary.opacity(0.16), in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Open camera to capture receipt")

            Button {
                isPresentingTips = true
            } label: {
                captureControlLabel("Tips", systemImage: "lightbulb")
            }
            .accessibilityLabel("Receipt photo tips")
        }
        .frame(maxWidth: .infinity)
    }

    private func captureControlLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .frame(width: 52, height: 52)
                .background(FridgeFitTheme.ColorToken.card, in: Circle())
                .overlay {
                    Circle().stroke(FridgeFitTheme.ColorToken.border, lineWidth: 1)
                }

            Text(title)
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .frame(minWidth: 72, minHeight: 76)
    }

    private var parsingInfoCard: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 36, height: 36)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Instant Smart Parsing")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Read grocery lines on your device, then review names, quantities, and categories before saving.")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var captureGuidance: some View {
        Label("For best results, keep the entire receipt flat, bright, and in focus.", systemImage: "lock.fill")
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, FridgeFitTheme.Spacing.medium)
            .accessibilityElement(children: .combine)
    }

    private var selectedReceiptActions: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            Button {
                viewModel.scan()
            } label: {
                Label("Read Receipt", systemImage: "sparkles")
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())

            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Button {
                    photoItem = nil
                    viewModel.clearImage()
                } label: {
                    Label("Retake", systemImage: "camera")
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Import Another", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
            }
        }
    }

    private var photoLoadingIndicator: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            ProgressView()
                .tint(FridgeFitTheme.ColorToken.primary)
            Text("Loading receipt photo…")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading receipt photo")
    }

    private var scanningIndicator: some View {
        VStack(spacing: FridgeFitTheme.Spacing.medium) {
            ProgressView()
                .tint(FridgeFitTheme.ColorToken.primary)
            Text("Reading your receipt…")
                .font(FridgeFitTheme.Typography.cardTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("This stays on your device while we prepare the review.")
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
            Button("Cancel Scan") { viewModel.cancelScan() }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading your receipt")
    }

    private func scanFailureCard(message: String) -> some View {
        Label {
            Text(message)
                .font(FridgeFitTheme.Typography.supporting)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(FridgeFitTheme.ColorToken.danger)
        .padding(FridgeFitTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FridgeFitTheme.ColorToken.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func captureStatusPill(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(FridgeFitTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, FridgeFitTheme.Spacing.small)
            .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
            .background(FridgeFitTheme.ColorToken.card.opacity(0.94), in: Capsule())
            .symbolRenderingMode(.hierarchical)
            .tint(tint)
    }

    /// Shown when Apple Intelligence cannot interpret a receipt. Capture is
    /// deliberately not offered because the image cannot be processed.
    private var unavailableContent: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: "sparkles.slash")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 76, height: 76)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())

            Text(viewModel.availability.unavailableTitle ?? "Receipt Scanning Is Unavailable")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .multilineTextAlignment(.center)
            Text(viewModel.availability.unavailableExplanation ?? "")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)

            Button("Return to Smart Scan") { dismiss() }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FridgeFitTheme.Spacing.section)
        .background(FridgeFitTheme.ColorToken.canvas)
    }

    // MARK: - Actions

    private func presentCamera() {
        Task {
            let access = await CameraAccess.request()
            switch access {
            case .granted:
                isPresentingCamera = true
            case .denied, .unavailable:
                cameraAccessMessage = access.explanation
            }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        isLoadingPickedPhoto = true
        Task {
            defer { isLoadingPickedPhoto = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    viewModel.reportImageLoadFailure()
                    return
                }
                viewModel.selectImage(image)
            } catch {
                viewModel.reportImageLoadFailure()
            }
        }
    }
}

private struct ReceiptFrameGuide: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(FridgeFitTheme.ColorToken.primary.opacity(0.75), style: StrokeStyle(lineWidth: 3, dash: [8, 8]))
            .overlay(alignment: .topLeading) { frameCorner(rotation: 0) }
            .overlay(alignment: .topTrailing) { frameCorner(rotation: 90) }
            .overlay(alignment: .bottomTrailing) { frameCorner(rotation: 180) }
            .overlay(alignment: .bottomLeading) { frameCorner(rotation: 270) }
            .accessibilityHidden(true)
    }

    private func frameCorner(rotation: Double) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 3, y: 27))
            path.addLine(to: CGPoint(x: 3, y: 8))
            path.addQuadCurve(to: CGPoint(x: 8, y: 3), control: CGPoint(x: 3, y: 3))
            path.addLine(to: CGPoint(x: 27, y: 3))
        }
        .stroke(FridgeFitTheme.ColorToken.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: 30, height: 30)
        .rotationEffect(.degrees(rotation))
    }
}

private struct ReceiptCaptureTipsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                tipRow("Flatten the receipt", detail: "Smooth folds so each printed line stays clear.", systemImage: "doc.text")
                tipRow("Use even light", detail: "Avoid glare, heavy shadows, and reflective surfaces.", systemImage: "sun.max")
                tipRow("Keep it all in frame", detail: "Include the top and bottom of the receipt in one photo.", systemImage: "viewfinder")
                Spacer()
            }
            .padding(FridgeFitTheme.Spacing.large)
            .background(FridgeFitTheme.ColorToken.canvas)
            .navigationTitle("Receipt Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func tipRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 36, height: 36)
                .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text(title)
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(detail)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }
}

#Preview {
    ReceiptScannerView(
        viewModel: ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: SampleReceiptPreviewData.lines),
            interpreter: MockReceiptIngredientInterpreter(),
            pantryRepository: InMemoryPantryRepository()
        ),
        onFinished: { _ in }
    )
}
