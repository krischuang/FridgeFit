//
//  ReceiptDemoCachePreparationView.swift
//  FridgeFit
//

#if DEBUG

import PhotosUI
import SwiftUI

/// Developer tool for preparing the demonstration receipt's cache entry.
///
/// Pick the receipt, run the real Apple Intelligence pipeline once, read what
/// it found, and persist it. After that the same photo resolves from the
/// cache instead of taking ten seconds.
///
/// The photo is chosen from the library rather than bundled, which is both
/// simpler and the point: the picture that must be prepared is the one that
/// will be picked during the demonstration, going through the same
/// `PhotosPicker` path, so whatever representation Photos hands over is the
/// representation that gets fingerprinted.
///
/// Behind `#if DEBUG` in its entirety - this is not shipped.
struct ReceiptDemoCachePreparationView: View {
    @Environment(\.dismiss) private var dismiss

    /// Default file location, which is the same one `ContentView` wires into
    /// the scanner - so an entry written here is the entry the scan reads.
    private let cache: ReceiptRecognitionCacheStoring
    private let preparer: ReceiptDemoCachePreparer

    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var fingerprint: ReceiptImageFingerprint?
    @State private var report: ReceiptDemoCachePreparer.Report?
    @State private var preparedEntry: ReceiptRecognitionCacheEntry?
    @State private var phase: Phase = .idle
    @State private var message: String?

    private enum Phase: Equatable {
        case idle
        case loadingPhoto
        case analyzing
        case analyzed
        case saved
        case failed(String)
    }

    init() {
        let cache = FileReceiptRecognitionCacheStore()
        self.cache = cache
        self.preparer = ReceiptDemoCachePreparer(
            textRecognizer: VisionReceiptTextRecognizer(),
            interpreter: AppleReceiptIngredientInterpreter(),
            cache: cache
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
                    readinessCard
                    availabilityCard
                    pickerCard
                    if let fingerprint { fingerprintCard(fingerprint) }
                    if phase == .analyzing { analyzingCard }
                    if let report { resultCard(report) }
                    if let message { messageCard(message) }
                    storedEntriesCard
                }
                .padding(FridgeFitTheme.Spacing.large)
            }
            .background(FridgeFitTheme.ColorToken.canvas)
            .navigationTitle("Prepare Demo Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPhoto(item)
            }
        }
    }

    // MARK: - Cards

    /// The headline the operator actually came for.
    private var readinessCard: some View {
        let isReady = preparedEntry != nil
        return VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Label(
                isReady ? "DEMO CACHE READY" : "DEMO CACHE NOT READY",
                systemImage: isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
            )
            .font(FridgeFitTheme.Typography.cardTitle)
            .foregroundStyle(isReady ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.danger)

            if let preparedEntry {
                detailRow("Cache key", preparedEntry.fingerprint.abbreviated)
                detailRow("Prepared", preparedEntry.preparedAt.formatted(date: .abbreviated, time: .standard))
                detailRow("Pipeline", preparedEntry.pipelineVersion)
                detailRow("Items", "\(preparedEntry.outcome.pantryCandidates.count) pantry, \(preparedEntry.outcome.excluded.count) excluded")
            } else {
                Text("Pick the demo receipt below and run the analysis. Readiness is re-read from disk, so reopening this screen after a relaunch proves the entry survived.")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var availabilityCard: some View {
        let availability = preparer.availability
        return Label(
            availability.canScan
                ? "Apple Intelligence is available — preparation will run the real model."
                : (availability.unavailableTitle ?? "Apple Intelligence is unavailable"),
            systemImage: availability.canScan ? "sparkles" : "sparkles.slash"
        )
        .font(FridgeFitTheme.Typography.metadata)
        .foregroundStyle(availability.canScan ? FridgeFitTheme.ColorToken.textSecondary : FridgeFitTheme.ColorToken.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label(pickedImage == nil ? "Choose Demo Receipt" : "Choose a Different Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())

            if let pickedImage {
                Image(uiImage: pickedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

                Button {
                    runAnalysis()
                } label: {
                    Label("Prepare Coles Demo Receipt", systemImage: "wand.and.stars")
                }
                .buttonStyle(FridgeFitPrimaryButtonStyle())
                .disabled(phase == .analyzing || !preparer.availability.canScan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func fingerprintCard(_ fingerprint: ReceiptImageFingerprint) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Text("Canonical fingerprint")
                .font(FridgeFitTheme.Typography.cardTitle)
            Text(fingerprint.value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let pickedImage {
                detailRow("Pixels", "\(Int(pickedImage.size.width * pickedImage.scale))×\(Int(pickedImage.size.height * pickedImage.scale))")
                detailRow("Orientation", "\(pickedImage.imageOrientation.rawValue)")
            }
            if cache.entry(for: fingerprint) != nil {
                Label("This exact photo is already cached.", systemImage: "checkmark.circle")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var analyzingCard: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            ProgressView()
            Text("Running the real pipeline — this takes the normal scan time.")
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func resultCard(_ report: ReceiptDemoCachePreparer.Report) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Recognition result")
                .font(FridgeFitTheme.Typography.cardTitle)

            detailRow("Took", format(report.recognitionDuration))
            detailRow("Source", report.outcome.source.diagnosticLabel)

            ForEach(report.outcome.pantryCandidates) { candidate in
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName)
                        .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                    Text("\(candidate.quantity?.formatted ?? "no quantity stated") · \(candidate.category.rawValue)")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    Text(candidate.sourceText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !report.outcome.excluded.isEmpty {
                Text("Excluded: \(report.outcome.excluded.map(\.displayName).joined(separator: ", "))")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if report.discrepancies.isEmpty {
                Label("Matches the reference receipt.", systemImage: "checkmark.circle")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
            } else {
                Text("Review these before accepting")
                    .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                ForEach(report.discrepancies) { discrepancy in
                    Label(discrepancy.message, systemImage: discrepancy.severity == .blocking ? "xmark.octagon.fill" : "exclamationmark.triangle")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(discrepancy.severity == .blocking ? FridgeFitTheme.ColorToken.danger : FridgeFitTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                save(report)
            } label: {
                Label("Accept and Cache This Result", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())
            .disabled(!report.isPersistable || phase == .saved)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func messageCard(_ message: String) -> some View {
        Text(message)
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FridgeFitTheme.Spacing.medium)
            .fridgeFitCardSurface()
    }

    private var storedEntriesCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Text("Stored entries (\(preparer.allPreparedEntries().count))")
                .font(FridgeFitTheme.Typography.cardTitle)
            ForEach(preparer.allPreparedEntries(), id: \.fingerprint) { entry in
                Text("\(entry.fingerprint.abbreviated) · \(entry.outcome.pantryCandidates.count) items · \(entry.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
            Button(role: .destructive) {
                preparer.clear()
                preparedEntry = nil
                message = "Cache cleared."
            } label: {
                Label("Clear Cache", systemImage: "trash")
            }
            .font(FridgeFitTheme.Typography.metadata)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            Spacer(minLength: FridgeFitTheme.Spacing.small)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func loadPhoto(_ item: PhotosPickerItem) {
        phase = .loadingPhoto
        report = nil
        message = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                phase = .failed("That photo could not be loaded.")
                message = "That photo could not be loaded."
                return
            }

            pickedImage = image
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            // Off the main actor: `fingerprint(of:)` is nonisolated.
            let computed = preparer.fingerprint(of: cgImage, orientation: orientation)
            fingerprint = computed
            preparedEntry = computed.flatMap { cache.entry(for: $0) }
            phase = .idle
        }
    }

    private func runAnalysis() {
        guard let cgImage = pickedImage?.cgImage, let pickedImage else { return }
        phase = .analyzing
        message = nil
        Task {
            do {
                let produced = try await preparer.analyze(
                    image: cgImage,
                    orientation: CGImagePropertyOrientation(pickedImage.imageOrientation)
                )
                report = produced
                phase = .analyzed
            } catch {
                phase = .failed(error.localizedDescription)
                message = error.localizedDescription
            }
        }
    }

    private func save(_ report: ReceiptDemoCachePreparer.Report) {
        do {
            try preparer.persist(report)
            preparedEntry = preparer.preparedEntry(for: report.fingerprint)
            phase = .saved
            message = preparedEntry == nil
                ? "Saved, but the entry could not be read back. The cache is NOT ready."
                : "Saved. Relaunch the app and reopen this screen to confirm it survived."
        } catch {
            message = error.localizedDescription
            phase = .failed(error.localizedDescription)
        }
    }

    private func format(_ duration: Duration) -> String {
        String(format: "%.2fs", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }
}

#endif
