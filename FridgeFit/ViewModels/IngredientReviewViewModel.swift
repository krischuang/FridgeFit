//
//  IngredientReviewViewModel.swift
//  FridgeFit
//

import Combine
import Foundation
import SwiftUI

/// Drives the ingredient review sheet.
///
/// Takes one `SnapshotAnalysis` and lets the user accept, reject, rename,
/// recategorise, set an amount, and add what recognition missed.
///
/// ## What reaches the pantry
///
/// Only rows the user explicitly accepted, and only through
/// `AddDetectedIngredientsUseCase` - the same path the receipt scanner uses,
/// with the same validation and the same duplicate rule. Nothing recognition
/// produced is stored on its own:
///
/// - a conflicting prediction is never preselected (`isPreselected` requires
///   `.agreed` *and* `assertsIngredient`)
/// - an unaccepted row is never included
/// - a row with no amount is refused before the save button is offered
///
/// Measured precision of the hybrid pipeline is 56.4%, so human confirmation
/// is not a formality - it is the only thing standing between a guess and the
/// user's pantry.
@MainActor
final class IngredientReviewViewModel: ObservableObject {

    @Published private(set) var items: [IngredientReviewItem]
    /// Set once the user confirms, so the view can show what was kept.
    @Published private(set) var confirmed: [ConfirmedIngredient]?
    /// Where the pantry save has got to.
    @Published private(set) var saveState: PantrySaveState = .idle
    /// Packaging text, for the user to read. Shown verbatim because mapping
    /// it to ingredients is not reliable - see `PackagedFoodTextReader`.
    let packagingLines: [String]
    let nonLatinPackagingLines: [String]
    /// Food claims recognition made that are not FridgeFit ingredients. Shown
    /// in the diagnostics disclosure rather than hidden, because they are the
    /// clearest signal of what the models get wrong.
    let rejectedFoodClaims: [String]
    let analysisDuration: TimeInterval
    /// Which recognisers ran. Drives the "YOLO-only" notice, so the sheet
    /// never implies two methods agreed when only one of them ran.
    let classification: ClassificationOutcome
    /// Geometry the boxes were measured against, for the thumbnail overlay.
    let sourceSize: CGSize

    private let addIngredientsUseCase: AddDetectedIngredientsUseCase?

    init(
        analysis: SnapshotAnalysis,
        addIngredientsUseCase: AddDetectedIngredientsUseCase? = nil
    ) {
        self.addIngredientsUseCase = addIngredientsUseCase
        self.items = analysis.fused.all.map(IngredientReviewItem.init)
        self.packagingLines = analysis.packaging.lines
        self.nonLatinPackagingLines = analysis.packaging.nonLatinLines
        self.rejectedFoodClaims = analysis.fused.rejectedFoodClaims
        self.analysisDuration = analysis.duration
        self.classification = analysis.classification
        self.sourceSize = analysis.fused.sourceSize
        self.confirmed = nil
    }

    /// For previews and tests.
    init(
        items: [IngredientReviewItem],
        sourceSize: CGSize = CGSize(width: 640, height: 480),
        addIngredientsUseCase: AddDetectedIngredientsUseCase? = nil,
        classification: ClassificationOutcome = .available
    ) {
        self.addIngredientsUseCase = addIngredientsUseCase
        self.items = items
        self.packagingLines = []
        self.nonLatinPackagingLines = []
        self.rejectedFoodClaims = []
        self.analysisDuration = 0
        self.classification = classification
        self.sourceSize = sourceSize
        self.confirmed = nil
    }

    /// Nothing to tear down - but the isolation matters.
    ///
    /// SwiftUI releases a `@StateObject` from the hosting view's Objective-C
    /// ivar destructor, which is not running inside a Swift task. An isolated
    /// `deinit` - which every `@MainActor` class gets by default - has to hop
    /// to the main actor from there, and that hop corrupts the concurrency
    /// runtime's task-local stack and aborts the process with
    /// `pointer being freed was not allocated`. Every view model in this app
    /// carries this for the same reason; omitting it here crash-looped the
    /// review tests until it was added.
    nonisolated deinit {}

    // MARK: - Derived state

    var isEmpty: Bool { items.isEmpty }
    var acceptedCount: Int { items.filter(\.isAccepted).count }

    /// Rows that came from recognition and are anchored to a measured region.
    var localisedItems: [IngredientReviewItem] { items.filter { $0.boundingBox != nil } }

    /// Rows with no location: whole-image classification, packaging text, and
    /// anything the user typed. Listed apart from the localised rows so the
    /// distinction survives into the UI, and never drawn as boxes.
    var unlocalisedItems: [IngredientReviewItem] { items.filter { $0.boundingBox == nil } }

    func count(of tier: ConfidenceTier) -> Int {
        items.filter { $0.tier == tier }.count
    }

    // MARK: - User actions

    func accept(_ id: UUID) { setAccepted(true, for: id) }
    func reject(_ id: UUID) { setAccepted(false, for: id) }

    func toggleAcceptance(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isAccepted.toggle()
    }

    private func setAccepted(_ accepted: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isAccepted = accepted
    }

    /// Corrects an ingredient's name.
    ///
    /// Blank input is ignored rather than accepted: an empty row would be
    /// confirmed into nothing useful, and silently dropping it would be worse
    /// than refusing the edit.
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].displayName = trimmed
    }

    /// Sets the amount. Stored as text so a half-typed "1." is not discarded
    /// mid-edit; `IngredientReviewItem.quantity` decides what is usable.
    func setQuantityText(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].quantityText = text
    }

    func setUnit(_ unit: MeasurementUnit, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].unit = unit
    }

    /// Overrides where this goes in the pantry, independently of the
    /// recognition category.
    func setPantryCategory(_ category: IngredientCategory, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pantryCategoryOverride = category
    }

    func recategorise(_ id: UUID, to category: IngredientGroup) {
        // `.decoy` is an internal vocabulary device, never a user-facing
        // category, so it is not offered and not accepted.
        guard category.isIngredient, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].category = category
    }

    /// Adds something recognition missed.
    ///
    /// - Returns: `false` when the name is blank or already present, so the
    ///   view can keep the field focused instead of appearing to succeed.
    @discardableResult
    func addManualIngredient(name: String, category: IngredientGroup) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, category.isIngredient else { return false }
        let alreadyListed = items.contains {
            $0.displayName.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        guard !alreadyListed else { return false }

        items.append(IngredientReviewItem(manualName: trimmed, category: category))
        return true
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func acceptAll() {
        for index in items.indices { items[index].isAccepted = true }
    }

    func rejectAll() {
        for index in items.indices { items[index].isAccepted = false }
    }

    // MARK: - Confirming

    /// Freezes the accepted rows into a local result.
    ///
    /// Does not persist. `saveToPantry()` is the only path to storage.
    @discardableResult
    func confirm() -> [ConfirmedIngredient] {
        let result = items.filter(\.isAccepted).map(ConfirmedIngredient.init)
        confirmed = result
        return result
    }

    func resumeEditing() {
        confirmed = nil
        if saveState.isRetryable || saveState.summary != nil { saveState = .idle }
    }

    // MARK: - Pantry persistence

    /// Rows the user accepted that still need an amount before they can be
    /// stored. Shown inline so the Save button's disabled state is explained.
    var acceptedItemsMissingQuantity: [IngredientReviewItem] {
        items.filter { $0.isAccepted && !$0.hasValidQuantity }
    }

    /// Whether Save should be offered.
    ///
    /// Requires at least one accepted row and an amount on every accepted
    /// row. Letting the user press Save and then reporting six "invalid
    /// quantity" failures would be technically correct and useless.
    var canSaveToPantry: Bool {
        guard !saveState.isSaving, acceptedCount > 0 else { return false }
        return acceptedItemsMissingQuantity.isEmpty
    }

    /// Writes the accepted rows to the pantry through the existing use case.
    ///
    /// Only rows the user explicitly accepted are sent. Nothing recognition
    /// produced reaches storage on its own: a conflicting prediction is never
    /// preselected, and an unaccepted row is never included.
    ///
    /// Re-entrancy is guarded at the top rather than only by disabling the
    /// button: a second tap landing between the first tap and the next render
    /// would otherwise write everything twice. `AddPantryItemUseCase`'s
    /// duplicate rule would catch most of that, but relying on it would mean
    /// depending on a *read* of Firestore completing before the second write
    /// starts, which is not something to depend on.
    func saveToPantry() async {
        guard !saveState.isSaving else { return }
        guard let addIngredientsUseCase else {
            saveState = .failed("The pantry isn't available from here.")
            return
        }

        let accepted = items.filter(\.isAccepted)
        guard !accepted.isEmpty else {
            saveState = .failed("Nothing is selected, so there is nothing to save.")
            return
        }

        saveState = .saving
        let summary = await addIngredientsUseCase.execute(
            confirmed: accepted.map(\.pantryDraft)
        )

        // Record what the user confirmed regardless of outcome, so a retry
        // after a partial failure still knows what they chose.
        confirmed = accepted.map(ConfirmedIngredient.init)

        if summary.isCompleteSuccess {
            saveState = .succeeded(summary)
        } else if summary.addedCount > 0 || !summary.duplicateNames.isEmpty {
            saveState = .partial(summary)
        } else {
            saveState = .failed(summary.userMessage)
        }
    }

    /// Retries, sending only what has not already been stored.
    ///
    /// The rows that succeeded are deselected first, so a retry after a
    /// partial failure cannot write them a second time. Duplicates rejected
    /// by the pantry are deselected too - they are already there, and
    /// re-sending them would just collect the same rejection again.
    func retrySave() async {
        guard let summary = saveState.summary else {
            await saveToPantry()
            return
        }

        let settled = Set(summary.addedNames + summary.duplicateNames)
        for index in items.indices where settled.contains(items[index].displayName) {
            items[index].isAccepted = false
        }

        saveState = .idle
        await saveToPantry()
    }

    /// Clears a finished save so the sheet returns to editing.
    func dismissSaveResult() { saveState = .idle }
}
