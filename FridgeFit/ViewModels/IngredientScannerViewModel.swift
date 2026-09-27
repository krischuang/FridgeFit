//
//  IngredientScannerViewModel.swift
//  FridgeFit
//

import Combine
import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Presentation state and actions for Scan Fridge.
///
/// Decides nothing itself: detection and normalization are
/// `DetectIngredientsUseCase`, and pantry validation and duplicate rules are
/// `AddDetectedIngredientsUseCase` wrapping the existing
/// `AddPantryItemUseCase`. This owns the review edits the user makes in
/// between, and the state machine the view renders.
@MainActor
final class IngredientScannerViewModel: ObservableObject {
    /// Where the scan currently is. Drives which of the scanner's states
    /// the view shows.
    enum AnalysisState: Equatable {
        case idle
        case analyzing
        case completed
        case failed(message: String)

        var isAnalyzing: Bool { self == .analyzing }
    }

    @Published private(set) var selectedImage: UIImage?
    @Published private(set) var analysisState: AnalysisState = .idle
    /// Editable review rows, ordered most confident first.
    @Published private(set) var drafts: [DetectedIngredientDraft] = []
    @Published var isPresentingReview = false
    /// Set once confirmed detections have been through the pantry use case.
    @Published private(set) var addSummary: AddDetectedIngredientsSummary?
    @Published private(set) var isAddingToPantry = false

    private let detectIngredientsUseCase: DetectIngredientsUseCase
    private let addDetectedIngredientsUseCase: AddDetectedIngredientsUseCase

    private var analysisTask: Task<Void, Never>?
    /// Bumped on every new scan and on cancellation. A finished scan only
    /// writes its results if its token is still the current one, so a slow
    /// first scan can't overwrite a faster second one.
    private var currentAnalysisToken = 0

    init(
        detectIngredientsUseCase: DetectIngredientsUseCase,
        addDetectedIngredientsUseCase: AddDetectedIngredientsUseCase
    ) {
        self.detectIngredientsUseCase = detectIngredientsUseCase
        self.addDetectedIngredientsUseCase = addDetectedIngredientsUseCase
    }

    convenience init(
        recognitionService: IngredientRecognitionService,
        pantryRepository: PantryRepository
    ) {
        self.init(
            detectIngredientsUseCase: DetectIngredientsUseCase(
                recognitionService: recognitionService,
                pantryRepository: pantryRepository
            ),
            addDetectedIngredientsUseCase: AddDetectedIngredientsUseCase(pantryRepository: pantryRepository)
        )
    }

    /// `isolated` so teardown cancellation is guaranteed to run on the main
    /// actor. A plain `deinit` on a `@MainActor` class traps if the last
    /// reference happens to be released from a background thread.
    isolated deinit {
        analysisTask?.cancel()
    }

    // MARK: - Availability

    /// Whether Apple Intelligence can run a scan right now. Re-read on
    /// every access so returning from Settings reflects the new state.
    var availability: IngredientRecognitionAvailability {
        detectIngredientsUseCase.availability
    }

    var canScan: Bool { availability.canScan }

    // MARK: - Image selection

    /// Accepts a photo from the camera or the library.
    ///
    /// Any in-flight analysis is dropped - its results describe the old
    /// photo and would be misleading against the new one.
    func selectImage(_ image: UIImage) {
        cancelAnalysis()
        selectedImage = image
        drafts = []
        addSummary = nil
        analysisState = .idle
    }

    /// Clears the photo and everything derived from it.
    func clearImage() {
        cancelAnalysis()
        selectedImage = nil
        drafts = []
        addSummary = nil
        analysisState = .idle
    }

    /// Reports a failure that happened before analysis - a camera or
    /// picker problem - using the scanner's normal error surface.
    func reportImageLoadFailure() {
        analysisState = .failed(message: IngredientRecognitionError.invalidImage.localizedDescription)
    }

    // MARK: - Analysis

    /// Analyses the selected photo on-device.
    ///
    /// Ignored while a scan is already running, so tapping the button twice
    /// can't start two scans or produce two sets of results.
    func analyze() {
        guard !analysisState.isAnalyzing, !isAddingToPantry else { return }

        guard let selectedImage else {
            analysisState = .failed(message: IngredientRecognitionError.noImageSelected.localizedDescription)
            return
        }

        guard let cgImage = selectedImage.cgImage else {
            analysisState = .failed(message: IngredientRecognitionError.invalidImage.localizedDescription)
            return
        }

        let availability = self.availability
        guard availability.canScan else {
            analysisState = .failed(
                message: IngredientRecognitionError.recognitionUnavailable(availability).localizedDescription
            )
            return
        }

        currentAnalysisToken += 1
        let token = currentAnalysisToken
        let orientation = CGImagePropertyOrientation(selectedImage.imageOrientation)

        analysisState = .analyzing
        addSummary = nil

        // The use case is captured by value rather than reached through
        // `self`, so an abandoned scan doesn't keep the view model alive
        // until it finishes.
        let useCase = detectIngredientsUseCase

        analysisTask = Task { [weak self] in
            do {
                let detections = try await useCase.execute(image: cgImage, orientation: orientation)
                self?.finishAnalysis(with: .success(detections), token: token)
            } catch is CancellationError {
                // Cancellation is handled by cancelAnalysis(); a cancelled
                // scan must leave no trace in the UI.
            } catch {
                self?.finishAnalysis(with: .failure(error), token: token)
            }
        }
    }

    /// Cancels an in-flight scan and returns to the image-selected state.
    ///
    /// Bumping the token as well as cancelling the task means a scan that
    /// had already finished its work, and was only waiting to hand results
    /// back, still can't publish them.
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        currentAnalysisToken += 1

        if analysisState.isAnalyzing {
            analysisState = .idle
        }
    }

    /// Applies a finished scan, unless it's been superseded or cancelled.
    private func finishAnalysis(with result: Result<[DetectedIngredient], Error>, token: Int) {
        guard token == currentAnalysisToken else { return }
        analysisTask = nil

        switch result {
        case .success(let detections):
            guard !detections.isEmpty else {
                drafts = []
                analysisState = .failed(message: IngredientRecognitionError.noIngredientsDetected.localizedDescription)
                return
            }
            drafts = detections
                .sorted { $0.confidence.sortPriority < $1.confidence.sortPriority }
                .map(DetectedIngredientDraft.init(detection:))
            analysisState = .completed
            isPresentingReview = true

        case .failure(let error):
            drafts = []
            analysisState = .failed(message: Self.userMessage(for: error))
        }
    }

    /// Anything that isn't already a FridgeFit error becomes the generic
    /// scan failure message - underlying framework text never reaches the
    /// user.
    private static func userMessage(for error: Error) -> String {
        if let recognitionError = error as? IngredientRecognitionError {
            return recognitionError.localizedDescription
        }
        return IngredientRecognitionError.recognitionFailed.localizedDescription
    }

    // MARK: - Review editing

    var selectedDrafts: [DetectedIngredientDraft] {
        drafts.filter(\.isSelected)
    }

    var canAddToPantry: Bool {
        !selectedDrafts.isEmpty && !isAddingToPantry
    }

    func toggleSelection(for draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].isSelected.toggle()
    }

    /// Corrects a misread ingredient name before it reaches the pantry.
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

    /// Drops an incorrect detection entirely.
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

    /// Sends the ticked detections to the pantry through the existing
    /// pantry use case, then reports what actually went in.
    ///
    /// Drafts the pantry accepted are removed from the review list so a
    /// second tap can't try to add them again; anything rejected stays put
    /// so the user can fix it.
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
                .filter { summary.addedNames.contains($0.trimmedName.isEmpty ? $0.detection.name : $0.trimmedName) }
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
        cancelAnalysis()
        selectedImage = nil
        drafts = []
        addSummary = nil
        analysisState = .idle
        isPresentingReview = false
    }
}

extension CGImagePropertyOrientation {
    /// Bridges a `UIImage`'s orientation to what Vision expects - camera
    /// captures are rarely upright, and analysing them unrotated costs
    /// detections.
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
