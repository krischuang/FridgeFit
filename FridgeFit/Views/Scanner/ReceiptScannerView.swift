//
//  ReceiptScannerView.swift
//  FridgeFit
//

import PhotosUI
import SwiftUI

/// Scan Receipt: take or choose a photo of a grocery receipt, read it
/// on-device, then confirm what was found before anything reaches the
/// pantry.
///
/// Presented as a sheet from `PantryView`. Holds no business logic - every
/// action goes through `ReceiptScannerViewModel`.
struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ReceiptScannerViewModel
    /// Called after the pantry has been updated, so Pantry can reload and
    /// report what happened.
    var onFinished: (AddDetectedIngredientsSummary) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var isPresentingCamera = false
    @State private var isLoadingPickedPhoto = false
    @State private var cameraAccessMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.canScan {
                    scannerContent
                } else {
                    unavailableContent
                }
            }
            .navigationTitle("Scan Receipt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelScan()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.isPresentingReview) {
                ReceiptItemReviewView(viewModel: viewModel) { summary in
                    onFinished(summary)
                    dismiss()
                }
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

    @ViewBuilder
    private var scannerContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                imageArea

                if viewModel.scanState.isScanning {
                    scanningIndicator
                } else {
                    actionButtons
                }

                if case .failed(let message) = viewModel.scanState {
                    InlineErrorBanner(message: message)
                }

                InlineInfoBanner(
                    message: "Receipts are read by Apple Intelligence on this device. Your receipt photo is never uploaded - only the ingredients you confirm are saved to your pantry.",
                    systemImage: "lock.fill"
                )
            }
            .padding()
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        if let image = viewModel.selectedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Selected receipt photo")
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Scan a grocery receipt to add what you bought.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Lay the receipt flat and fill the frame.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var scanningIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading your receipt…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Cancel Scan") { viewModel.cancelScan() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading your receipt")
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if viewModel.selectedImage == nil {
                Button {
                    presentCamera()
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    viewModel.scan()
                } label: {
                    Label("Read Receipt", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    photoItem = nil
                    viewModel.clearImage()
                } label: {
                    Label("Choose Another Photo", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if isLoadingPickedPhoto {
                ProgressView()
                    .accessibilityLabel("Loading photo")
            }
        }
    }

    /// Shown in place of the scanner when Apple Intelligence can't run.
    /// Pantry, recipes and everything else keep working - only this screen
    /// is affected.
    @ViewBuilder
    private var unavailableContent: some View {
        let availability = viewModel.availability
        ContentUnavailableView {
            Label(availability.unavailableTitle ?? "Receipt Scanning Is Unavailable", systemImage: "sparkles.slash")
        } description: {
            Text(availability.unavailableExplanation ?? "")
        } actions: {
            Button("Add Ingredients by Hand") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
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

    /// Loads the picked photo's bytes off the main actor, tolerating a
    /// library item that can't be read.
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
