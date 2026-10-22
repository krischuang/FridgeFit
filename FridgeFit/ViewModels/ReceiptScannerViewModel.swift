//
//  ReceiptScannerViewModel.swift
//  FridgeFit
//

import Combine
import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Presentation state and actions for Scan Receipt.
///
/// Decides nothing itself: OCR, parsing, interpretation, canonicalization
/// and deduplication are `ScanReceiptUseCase`, and pantry validation and
/// duplicate rules are `AddDetectedIngredientsUseCase` wrapping the
/// existing `AddPantryItemUseCase`. This owns the corrections the user
/// makes in between, and the state machine the view renders.
@MainActor
final class ReceiptScannerViewModel: ObservableObject {
    /// Where the scan currently is. Drives which of the scanner's states
    /// the view shows.
    enum ScanState: Equatable {
        case idle
        case scanning
        case completed
        case failed(message: String)

        var isScanning: Bool { self == .scanning }
    }

    @Published private(set) var selectedImage: UIImage?
    @Published private(set) var scanState: ScanState = .idle
    /// Editable confirmation rows, in receipt order.
    @Published private(set) var drafts: [ReceiptItemDraft] = []
    @Published var isPresentingReview = false
    /// Set once confirmed items have been through the pantry use case.
    @Published private(set) var addSummary: AddDetectedIngredientsSummary?
    @Published private(set) var isAddingToPantry = false

    /// Items the scan deliberately kept out of the pantry - cleaning
    /// products, drinks, unreadable lines. Never shown in the normal UI;
    /// exposed only so a DEBUG build can inspect why something is missing.
    @Published private(set) var excludedItems: [ReceiptIngredientCandidate] = []

    /// Where the current results came from, or `nil` when there are none.
    ///
    /// Carried through from `ReceiptScanOutcome` rather than guessed from
    /// elapsed time, so the review screen can say plainly that it is showing
    /// a reused result instead of implying the model just ran.
    @Published private(set) var recognitionSource: ReceiptRecognitionSource?

    /// Wall-clock time from `scan()` being called to the review screen being
    /// asked to present, for the most recent scan.
    ///
    /// This is the number a demonstration is actually judged on - it
    /// includes the view model's own state updates, not just the use case's
    /// work - so it is measured here rather than inferred from
    /// `ReceiptScanMetrics.total`.
    @Published private(set) var lastScanLatency: Duration?

    private let scanReceiptUseCase: ScanReceiptUseCase
    private let addDetectedIngredientsUseCase: AddDetectedIngredientsUseCase

    private var scanTask: Task<Void, Never>?
    /// Bumped on every new scan and on cancellation. A finished scan only
    /// writes its results if its token is still the current one, so a slow
    /// first scan can't overwrite a faster second one.
    private var currentScanToken = 0
    /// When the current scan started, for `lastScanLatency`.
    private var scanStartedAt: ContinuousClock.Instant?

    init(
        scanReceiptUseCase: ScanReceiptUseCase,
        addDetectedIngredientsUseCase: AddDetectedIngredientsUseCase
    ) {
        self.scanReceiptUseCase = scanReceiptUseCase
        self.addDetectedIngredientsUseCase = addDetectedIngredientsUseCase
    }

    convenience init(
        textRecognizer: ReceiptTextRecognizer,
        interpreter: ReceiptIngredientInterpreter,
        pantryRepository: PantryRepository,
        recognitionCache: ReceiptRecognitionCacheStoring? = nil,
        metrics: ReceiptScanMetricsRecording? = nil
    ) {
        self.init(
            scanReceiptUseCase: ScanReceiptUseCase(
                textRecognizer: textRecognizer,
                interpreter: interpreter,
                pantryRepository: pantryRepository,
                recognitionCache: recognitionCache,
                metrics: metrics
            ),
            addDetectedIngredientsUseCase: AddDetectedIngredientsUseCase(pantryRepository: pantryRepository)
        )
    }

    #if DEBUG
    /// Supplies an isolated in-memory review state for SwiftUI previews.
    /// It is deliberately unavailable in release builds and never invokes
    /// recognition or persistence.
    convenience init(
        previewDrafts: [ReceiptItemDraft],
        previewSummary: AddDetectedIngredientsSummary? = nil,
        previewSource: ReceiptRecognitionSource = .appleIntelligence
    ) {
        self.init(
            textRecognizer: MockReceiptTextRecognizer(lines: []),
            interpreter: MockReceiptIngredientInterpreter(),
            pantryRepository: InMemoryPantryRepository()
        )
        drafts = previewDrafts
        addSummary = previewSummary
        recognitionSource = previewSource
        scanState = .completed
    }
    #endif

    /// Deliberately `nonisolated`: `Task.cancel()` is `Sendable` and safe
    /// from any thread, so this deinit touches nothing that needs the main
    /// actor and has no reason to hop onto it.
    ///
    /// The previous scanner marked its deinit `isolated` to avoid a trap
    /// when the last reference is released off the main thread. That isn't
    /// needed when the deinit touches no isolated state, and the hop has a
    /// cost of its own: this target compiles with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every class in it
    /// gets an isolated deinit, and tearing one down through
    /// `swift_task_deinitOnExecutor` while already inside another such
    /// teardown corrupts the runtime's task-local scope stack and aborts
    /// in malloc. Not hopping here removes this view model from that chain.
    ///
    /// Note that the underlying problem is wider than this type: releasing
    /// *any* main-actor-isolated class in this target from a synchronous
    /// context can abort, including pre-existing ones such as
    /// `InMemoryPantryRepository`. That is why every test in
    /// `ReceiptScannerViewModelTests` is `async`.
    nonisolated deinit {
        scanTask?.cancel()
    }

    // MARK: - Availability

    /// Whether Apple Intelligence can interpret a receipt right now.
    /// Re-read on every access so returning from Settings reflects the new
    /// state.
    var availability: AppleIntelligenceAvailability {
        scanReceiptUseCase.availability
    }

    var canScan: Bool { availability.canScan }

    // MARK: - Image selection

    /// Accepts a photo from the camera or the library.
    ///
    /// Any in-flight scan is dropped - its results describe the old photo
    /// and would be misleading against the new one.
    func selectImage(_ image: UIImage) {
        cancelScan()
        selectedImage = image
        drafts = []
        excludedItems = []
        addSummary = nil
        recognitionSource = nil
        lastScanLatency = nil
        scanState = .idle
    }

    /// Clears the photo and everything derived from it.
    func clearImage() {
        cancelScan()
        selectedImage = nil
        drafts = []
        excludedItems = []
        addSummary = nil
        recognitionSource = nil
        lastScanLatency = nil
        scanState = .idle
    }

    /// Reports a failure that happened before scanning - a camera or
    /// picker problem - using the scanner's normal error surface.
    func reportImageLoadFailure() {
        scanState = .failed(message: ReceiptScanError.invalidImage.localizedDescription)
    }

    // MARK: - Scanning

    /// Reads and interprets the selected receipt on-device.
    ///
    /// Ignored while a scan is already running, so tapping the button twice
    /// can't start two scans or produce two sets of results.
    func scan() {
        guard !scanState.isScanning, !isAddingToPantry else { return }

        guard let selectedImage else {
            scanState = .failed(message: ReceiptScanError.noImageSelected.localizedDescription)
            return
        }

        guard let cgImage = selectedImage.cgImage else {
            scanState = .failed(message: ReceiptScanError.invalidImage.localizedDescription)
            return
        }

        let availability = self.availability
        guard availability.canScan else {
            scanState = .failed(
                message: ReceiptScanError.scanUnavailable(availability).localizedDescription
            )
            return
        }

        currentScanToken += 1
        let token = currentScanToken
        let orientation = CGImagePropertyOrientation(selectedImage.imageOrientation)

        scanState = .scanning
        addSummary = nil
        scanStartedAt = ContinuousClock.now
        lastScanLatency = nil

        // The use case is captured by value rather than reached through
        // `self`, so an abandoned scan doesn't keep the view model alive
        // until it finishes.
        let useCase = scanReceiptUseCase

        scanTask = Task { [weak self] in
            do {
                let outcome = try await useCase.execute(image: cgImage, orientation: orientation)
                self?.finishScan(with: .success(outcome), token: token)
            } catch is CancellationError {
                // Cancellation is handled by cancelScan(); a cancelled scan
                // must leave no trace in the UI.
            } catch {
                self?.finishScan(with: .failure(error), token: token)
            }
        }
    }

    /// Cancels an in-flight scan and returns to the image-selected state.
    ///
    /// Bumping the token as well as cancelling the task means a scan that
    /// had already finished its work, and was only waiting to hand results
    /// back, still can't publish them.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        currentScanToken += 1

        if scanState.isScanning {
            scanState = .idle
        }
    }

    /// Applies a finished scan, unless it's been superseded or cancelled.
    private func finishScan(with result: Result<ReceiptScanOutcome, Error>, token: Int) {
        guard token == currentScanToken else { return }
        scanTask = nil

        switch result {
        case .success(let outcome):
            excludedItems = outcome.excluded

            guard !outcome.pantryCandidates.isEmpty else {
                drafts = []
                recognitionSource = nil
                scanState = .failed(message: ReceiptScanError.noFoodItemsFound.localizedDescription)
                return
            }
            // Set before the drafts so any observer that reacts to `drafts`
            // already sees the right provenance.
            recognitionSource = outcome.source
            drafts = outcome.pantryCandidates.map(ReceiptItemDraft.init(candidate:))
            scanState = .completed
            isPresentingReview = true
            // Taken after `isPresentingReview`, so the measurement covers
            // every state change the review screen waits on.
            if let scanStartedAt {
                lastScanLatency = ContinuousClock.now - scanStartedAt
                ReceiptScanDiagnostics.reviewPresented(after: ContinuousClock.now - scanStartedAt, source: outcome.source)
            }

        case .failure(let error):
            drafts = []
            excludedItems = []
            recognitionSource = nil
            scanState = .failed(message: Self.userMessage(for: error))
        }
    }

    /// Anything that isn't already a FridgeFit error becomes the generic
    /// scan failure message - underlying framework text never reaches the
    /// user.
    private static func userMessage(for error: Error) -> String {
        if let scanError = error as? ReceiptScanError {
            return scanError.localizedDescription
        }
        return ReceiptScanError.interpretationFailed.localizedDescription
    }

    // MARK: - Review editing

    var selectedDrafts: [ReceiptItemDraft] {
        drafts.filter(\.isSelected)
    }

    var canAddToPantry: Bool {
        !selectedDrafts.isEmpty && !isAddingToPantry
    }

    func toggleSelection(for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].isSelected.toggle()
    }

    /// Corrects a misread product name before it reaches the pantry.
    func updateName(_ name: String, for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].name = name
    }

    func updateCategory(_ category: IngredientCategory, for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].category = category
    }

    func updateQuantityText(_ quantityText: String, for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].quantityText = quantityText
    }

    func updateUnit(_ unit: MeasurementUnit, for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].unit = unit
    }

    /// Drops an incorrect item entirely.
    func removeDraft(id draftID: UUID) {
        drafts.removeAll { $0.id == draftID }
    }

    func removeDrafts(at offsets: IndexSet) {
        // Descending, so earlier removals don't shift later indices.
        for index in offsets.sorted(by: >) where drafts.indices.contains(index) {
            drafts.remove(at: index)
        }
    }

    // MARK: - Pantry insertion

    /// Sends the ticked items to the pantry through the existing pantry use
    /// case, then reports what actually went in.
    ///
    /// Drafts the pantry accepted are removed from the confirmation list so
    /// a second tap can't try to add them again; anything rejected stays
    /// put so the user can fix it.
    func addSelectedToPantry() async {
        guard !isAddingToPantry else { return }

        let confirmed = selectedDrafts
        guard !confirmed.isEmpty else { return }

        isAddingToPantry = true
        defer { isAddingToPantry = false }

        let summary = await addDetectedIngredientsUseCase.execute(drafts: confirmed)
        addSummary = summary

        let addedIDs = Set(
            confirmed
                .filter { summary.addedNames.contains($0.trimmedName.isEmpty ? $0.candidate.displayName : $0.trimmedName) }
                .map(\.id)
        )
        drafts.removeAll { addedIDs.contains($0.id) }

        if drafts.isEmpty {
            isPresentingReview = false
        }
    }

    /// Clears the summary once the pantry screen has shown it.
    func acknowledgeAddSummary() {
        addSummary = nil
    }

    /// Resets everything, for when the scanner is dismissed and reopened.
    func reset() {
        cancelScan()
        selectedImage = nil
        drafts = []
        excludedItems = []
        addSummary = nil
        recognitionSource = nil
        lastScanLatency = nil
        scanState = .idle
        isPresentingReview = false
    }
}

extension CGImagePropertyOrientation {
    /// Bridges a `UIImage`'s orientation to what Vision expects - camera
    /// captures are rarely upright, and reading them unrotated costs almost
    /// every line of a receipt.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
