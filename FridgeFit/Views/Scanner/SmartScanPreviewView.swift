//
//  SmartScanPreviewView.swift
//  FridgeFit
//

import PhotosUI
import SwiftUI

/// The mode-selection surface shown before either existing Smart Scan flow.
///
/// It owns presentation only. Receipt OCR remains in `ReceiptScannerView`,
/// while ingredient recognition continues to use the existing local-photo
/// analysis and review pipeline without opening the Remote Camera/WebRTC UI.
struct SmartScanPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pantryRepository) private var pantryRepository
    @ObservedObject var receiptScannerViewModel: ReceiptScannerViewModel
    var onReceiptFinished: () -> Void
    var onIngredientsFinished: () -> Void
    var onAddManually: () -> Void

    @StateObject private var ingredientScanner = RemoteCameraViewModel(identity: DeviceIdentity.current())
    @State private var isPresentingReceiptScanner = false
    @State private var isPresentingIngredientCamera = false
    @State private var isPresentingIngredientReview = false
    @State private var isRequestingIngredientCamera = false
    @State private var cameraAccessMessage: String?
    @State private var ingredientPhotoItem: PhotosPickerItem?
    /// Completion is staged until its review sheet has dismissed, avoiding a
    /// success cover appearing above an active review sheet.
    @State private var pendingSuccessResult: SmartScanSuccessResult?
    @State private var successResult: SmartScanSuccessResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                    hero

                    VStack(spacing: FridgeFitTheme.Spacing.medium) {
                        scanModeCard(
                            title: "Scan Ingredients",
                            systemImage: "camera.viewfinder",
                            badgeTitle: "Live Object AI",
                            badgeImage: "sparkles",
                            detail: "Point your camera at fresh produce or kitchen groceries to identify them before saving.",
                            actionTitle: ingredientScanner.isAnalyzingSnapshot ? "Analysing…" : "Open Camera",
                            actionImage: "camera"
                        ) {
                            requestIngredientCamera()
                        }
                        .disabled(ingredientScanner.isAnalyzingSnapshot)

                        scanModeCard(
                            title: "Scan Receipt",
                            systemImage: "doc.text.viewfinder",
                            badgeTitle: "Smart OCR",
                            badgeImage: "text.viewfinder",
                            detail: "Snap a grocery receipt to import grocery items, quantities, and categories for review.",
                            actionTitle: "Scan Paper Receipt",
                            actionImage: "doc.viewfinder",
                            usesSecondaryAction: true
                        ) {
                            isPresentingReceiptScanner = true
                        }
                    }

                    controlBanner

                    PhotosPicker(selection: $ingredientPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose Ingredient Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
                    .disabled(ingredientScanner.isAnalyzingSnapshot)

                    Button {
                        dismiss()
                        onAddManually()
                    } label: {
                        Label("Or Add Manually", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())

                    Label("Camera permission is requested only when scanning starts.", systemImage: "lock")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, FridgeFitTheme.Spacing.xLarge)
                .padding(.top, FridgeFitTheme.Spacing.small)
                .padding(.bottom, FridgeFitTheme.Spacing.large)
            }
            .background(FridgeFitTheme.ColorToken.canvas)
            .navigationTitle("Smart Scan Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close Smart Scan")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Image(systemName: "person")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.card)
                        .frame(width: 36, height: 36)
                        .background(FridgeFitTheme.ColorToken.primary, in: Circle())
                        .accessibilityHidden(true)
                }
            }
            .sheet(isPresented: $isPresentingReceiptScanner, onDismiss: {
                receiptScannerViewModel.reset()
                presentPendingSuccessIfNeeded()
            }) {
                ReceiptScannerView(viewModel: receiptScannerViewModel) { summary in
                    recordCompleteSave(summary) {
                        onReceiptFinished()
                    }
                    isPresentingReceiptScanner = false
                }
            }
            .fullScreenCover(isPresented: $isPresentingIngredientCamera) {
                CameraPicker(
                    onCapture: analyseIngredientImage,
                    onFailure: { ingredientScanner.reportLocalImageFailure() }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isPresentingIngredientReview, onDismiss: {
                presentPendingSuccessIfNeeded()
            }) {
                if let analysis = ingredientScanner.currentAnalysis,
                   let snapshot = ingredientScanner.snapshot {
                    IngredientReviewView(
                        analysis: analysis,
                        snapshot: snapshot,
                        addIngredientsUseCase: AddDetectedIngredientsUseCase(
                            pantryRepository: pantryRepository
                        )
                    ) { _ in
                        onIngredientsFinished()
                    } onSaveCompleted: { summary in
                        recordCompleteSave(summary) {}
                    }
                }
            }
            .fullScreenCover(item: $successResult) { result in
                SmartScanSuccessView(
                    summary: result.summary,
                    onScanMore: scanMore,
                    onViewMyFridge: finishSmartScan
                )
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
            .onChange(of: ingredientPhotoItem) { _, item in
                guard let item else { return }
                loadIngredientPhoto(item)
            }
        }
    }

    /// Only a complete, non-empty persistence result may progress to the
    /// success surface. Partial/failed results intentionally remain in their
    /// review sheet with the existing retry UI.
    private func recordCompleteSave(
        _ summary: AddDetectedIngredientsSummary,
        onInventoryChanged: () -> Void
    ) {
        guard summary.isCompleteSuccess, summary.addedCount > 0 else { return }
        pendingSuccessResult = SmartScanSuccessResult(summary: summary)
        onInventoryChanged()
    }

    private func presentPendingSuccessIfNeeded() {
        guard let pendingSuccessResult else { return }
        successResult = pendingSuccessResult
        self.pendingSuccessResult = nil
    }

    private func scanMore() {
        successResult = nil
        receiptScannerViewModel.reset()
        ingredientPhotoItem = nil
    }

    private func finishSmartScan() {
        successResult = nil
        dismiss()
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Label("Kitchen Intelligence", systemImage: "sparkles")
                .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .padding(.horizontal, FridgeFitTheme.Spacing.small)
                .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                .background(FridgeFitTheme.ColorToken.warningBackground.opacity(0.7), in: Capsule())

            Text("Add groceries in a snap")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            Text("Choose how you would like to log your food today. We will help identify items so you can review before saving.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scanModeCard(
        title: String,
        systemImage: String,
        badgeTitle: String,
        badgeImage: String,
        detail: String,
        actionTitle: String,
        actionImage: String,
        usesSecondaryAction: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            scanArtwork(systemImage: systemImage, badgeTitle: badgeTitle, badgeImage: badgeImage)

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Label(title, systemImage: title == "Scan Ingredients" ? "leaf" : "doc.text")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                Text(detail)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if usesSecondaryAction {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionImage)
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
            } else {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionImage)
                }
                .buttonStyle(FridgeFitPrimaryButtonStyle())
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func scanArtwork(systemImage: String, badgeTitle: String, badgeImage: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                .fill(FridgeFitTheme.ColorToken.successBackground)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(FridgeFitTheme.ColorToken.primary.opacity(0.84))
                }

            Label(badgeTitle, systemImage: badgeImage)
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.card)
                .padding(.horizontal, FridgeFitTheme.Spacing.small)
                .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                .background(FridgeFitTheme.ColorToken.primary, in: Capsule())
                .padding(FridgeFitTheme.Spacing.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .accessibilityHidden(true)
    }

    private var controlBanner: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "checkmark.shield")
                .font(.title3)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 36, height: 36)
                .background(FridgeFitTheme.ColorToken.primaryMuted.opacity(0.35), in: Circle())

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("You are always in control")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                Text("Review and edit recognised items before anything is saved to your fridge.")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(FridgeFitTheme.Spacing.small)
        .background(FridgeFitTheme.ColorToken.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
    }

    private func requestIngredientCamera() {
        guard !isRequestingIngredientCamera else { return }
        isRequestingIngredientCamera = true
        Task {
            defer { isRequestingIngredientCamera = false }
            let access = await CameraAccess.request()
            switch access {
            case .granted:
                isPresentingIngredientCamera = true
            case .denied, .unavailable:
                cameraAccessMessage = access.explanation
            }
        }
    }

    private func loadIngredientPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    ingredientScanner.reportLocalImageFailure()
                    return
                }
                analyseIngredientImage(image)
            } catch {
                ingredientScanner.reportLocalImageFailure()
            }
        }
    }

    private func analyseIngredientImage(_ image: UIImage) {
        Task {
            await ingredientScanner.analyseLocalImage(image)
            if ingredientScanner.currentAnalysis != nil, ingredientScanner.snapshot != nil {
                isPresentingIngredientReview = true
            }
        }
    }
}
