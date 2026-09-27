//
//  IngredientScannerViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Drives the whole scan flow off `MockIngredientRecognitionService`, so none
/// of this needs Apple Intelligence, Vision, a camera, the network or
/// Firebase.
@MainActor
final class IngredientScannerViewModelTests: XCTestCase {
    private func makeViewModel(
        service: MockIngredientRecognitionService,
        repository: InMemoryPantryRepository = InMemoryPantryRepository()
    ) -> IngredientScannerViewModel {
        IngredientScannerViewModel(recognitionService: service, pantryRepository: repository)
    }

    /// Waits for the view model to settle out of `.analyzing`.
    ///
    /// Polls rather than sleeping a fixed interval so the tests stay fast and
    /// don't depend on timing.
    private func waitUntilAnalysisFinishes(
        _ viewModel: IngredientScannerViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 where viewModel.analysisState.isAnalyzing {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(viewModel.analysisState.isAnalyzing, "Analysis never finished", file: file, line: line)
    }

    // MARK: - Recognition success

    func test_analyze_exposesDetectedIngredients() async {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .success(.sampleFridge))
        )
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        XCTAssertEqual(viewModel.analysisState, .completed)
        XCTAssertEqual(viewModel.drafts.map(\.name), ["Milk", "Eggs", "Tomato", "Chicken"])
        XCTAssertTrue(viewModel.isPresentingReview, "A successful scan should present the review screen")
        // Every detection starts ticked, so confirming is one tap.
        XCTAssertEqual(viewModel.selectedDrafts.count, 4)
    }

    /// Results are ordered most confident first.
    func test_analyze_ordersDraftsByConfidence() async {
        let result = IngredientDetectionResult(ingredients: [
            RawDetectedIngredient(name: "celery", category: "Produce", visibleCount: 0, confidence: "low"),
            RawDetectedIngredient(name: "butter", category: "Dairy", visibleCount: 1, confidence: "high"),
            RawDetectedIngredient(name: "beef", category: "Meat", visibleCount: 0, confidence: "medium")
        ])
        let viewModel = makeViewModel(service: MockIngredientRecognitionService(result: .success(result)))
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        XCTAssertEqual(viewModel.drafts.map(\.name), ["Butter", "Beef", "Celery"])
    }

    /// Quantity defaults to what the model could count, and falls back to one
    /// piece rather than inventing a weight.
    func test_analyze_seedsDraftQuantitiesFromVisibleCount() async {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .success(.sampleFridge))
        )
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        let eggs = viewModel.drafts.first { $0.name == "Eggs" }
        XCTAssertEqual(eggs?.quantityText, "6")
        XCTAssertEqual(eggs?.unit, .pieces)

        // "chicken" came back with a count of 0 - not countable.
        let chicken = viewModel.drafts.first { $0.name == "Chicken" }
        XCTAssertEqual(chicken?.quantityText, "1")
    }

    // MARK: - Empty detection

    func test_analyze_showsEmptyState_whenNothingDetected() async {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .success(.empty))
        )
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertFalse(viewModel.isPresentingReview, "Nothing to review means no review screen")
        XCTAssertEqual(
            viewModel.analysisState,
            .failed(message: IngredientRecognitionError.noIngredientsDetected.localizedDescription)
        )
    }

    // MARK: - Recognition failure

    func test_analyze_setsErrorState_whenServiceThrows() async {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .failure(IngredientRecognitionError.recognitionFailed))
        )
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        XCTAssertEqual(
            viewModel.analysisState,
            .failed(message: IngredientRecognitionError.recognitionFailed.localizedDescription)
        )
        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertFalse(viewModel.isPresentingReview)
    }

    /// An unexpected error type must not leak framework wording into the UI.
    func test_analyze_mapsUnknownErrorToGenericMessage() async {
        struct OpaqueFailure: Error {}
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .failure(OpaqueFailure()))
        )
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        XCTAssertEqual(
            viewModel.analysisState,
            .failed(message: IngredientRecognitionError.recognitionFailed.localizedDescription)
        )
    }

    func test_analyze_setsErrorState_whenNoImageSelected() async {
        let service = MockIngredientRecognitionService(result: .success(.sampleFridge))
        let viewModel = makeViewModel(service: service)

        viewModel.analyze()

        XCTAssertEqual(
            viewModel.analysisState,
            .failed(message: IngredientRecognitionError.noImageSelected.localizedDescription)
        )
        XCTAssertEqual(service.recognizeCallCount, 0)
    }

    // MARK: - Model unavailable

    func test_analyze_isBlocked_whenAppleIntelligenceUnavailable() async {
        let service = MockIngredientRecognitionService(
            result: .success(.sampleFridge),
            availability: .appleIntelligenceNotEnabled
        )
        let viewModel = makeViewModel(service: service)
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()

        XCTAssertFalse(viewModel.canScan)
        XCTAssertEqual(viewModel.availability, .appleIntelligenceNotEnabled)
        XCTAssertEqual(service.recognizeCallCount, 0, "An unavailable model must never be invoked")
        XCTAssertEqual(
            viewModel.analysisState,
            .failed(message: IngredientRecognitionError.recognitionUnavailable(.appleIntelligenceNotEnabled).localizedDescription)
        )
    }

    func test_availability_reportsUnsupportedDevice() async {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(availability: .deviceNotSupported)
        )

        XCTAssertFalse(viewModel.canScan)
        XCTAssertEqual(viewModel.availability, .deviceNotSupported)
        XCTAssertNotNil(viewModel.availability.unavailableTitle)
        XCTAssertNotNil(viewModel.availability.unavailableExplanation)
    }

    func test_availability_reportsModelNotReady() async {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(availability: .modelNotReady)
        )

        XCTAssertFalse(viewModel.canScan)
        XCTAssertEqual(viewModel.availability, .modelNotReady)
    }

    // MARK: - Selection

    func test_toggleSelection_deselectsAndReselectsDetection() async {
        let viewModel = await makeAnalyzedViewModel()
        let milk = try! XCTUnwrap(viewModel.drafts.first { $0.name == "Milk" })

        viewModel.toggleSelection(for: milk.id)
        XCTAssertFalse(try! XCTUnwrap(viewModel.drafts.first { $0.id == milk.id }).isSelected)
        XCTAssertEqual(viewModel.selectedDrafts.count, 3)

        viewModel.toggleSelection(for: milk.id)
        XCTAssertTrue(try! XCTUnwrap(viewModel.drafts.first { $0.id == milk.id }).isSelected)
        XCTAssertEqual(viewModel.selectedDrafts.count, 4)
    }

    func test_canAddToPantry_isFalse_whenNothingSelected() async {
        let viewModel = await makeAnalyzedViewModel()

        for draft in viewModel.drafts {
            viewModel.toggleSelection(for: draft.id)
        }

        XCTAssertTrue(viewModel.selectedDrafts.isEmpty)
        XCTAssertFalse(viewModel.canAddToPantry)
    }

    /// Detections already in the pantry start unticked, since adding them
    /// would only be rejected.
    func test_analyze_leavesExistingPantryItemsUnselected() async {
        let repository = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1, unit: .liters)
        ])
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .success(.sampleFridge)),
            repository: repository
        )
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        let milk = viewModel.drafts.first { $0.name == "Milk" }
        XCTAssertEqual(milk?.isAlreadyInPantry, true)
        XCTAssertEqual(milk?.isSelected, false)
        XCTAssertEqual(viewModel.selectedDrafts.count, 3)
    }

    // MARK: - Editing

    func test_updateName_correctsDetectionBeforePantryInsertion() async throws {
        let repository = InMemoryPantryRepository()
        let viewModel = await makeAnalyzedViewModel(repository: repository)
        let chicken = try XCTUnwrap(viewModel.drafts.first { $0.name == "Chicken" })

        viewModel.updateName("Chicken Thigh", for: chicken.id)
        for draft in viewModel.drafts where draft.id != chicken.id {
            viewModel.toggleSelection(for: draft.id)
        }

        await viewModel.addSelectedToPantry()

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.map(\.name), ["Chicken Thigh"])
    }

    func test_updateCategoryQuantityAndUnit_areAppliedOnInsertion() async throws {
        let repository = InMemoryPantryRepository()
        let viewModel = await makeAnalyzedViewModel(repository: repository)
        let tomato = try XCTUnwrap(viewModel.drafts.first { $0.name == "Tomato" })

        viewModel.updateCategory(.produce, for: tomato.id)
        viewModel.updateQuantityText("450", for: tomato.id)
        viewModel.updateUnit(.grams, for: tomato.id)
        for draft in viewModel.drafts where draft.id != tomato.id {
            viewModel.toggleSelection(for: draft.id)
        }

        await viewModel.addSelectedToPantry()

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, "Tomato")
        XCTAssertEqual(stored.first?.ingredient.category, .produce)
        XCTAssertEqual(stored.first?.quantity, 450)
        XCTAssertEqual(stored.first?.unit, .grams)
    }

    /// The confidence the model reported survives a rename, so the review row
    /// keeps telling the truth about where the suggestion came from.
    func test_updateName_keepsOriginalConfidence() async throws {
        let viewModel = await makeAnalyzedViewModel()
        let tomato = try XCTUnwrap(viewModel.drafts.first { $0.name == "Tomato" })

        viewModel.updateName("Cherry Tomato", for: tomato.id)

        let updated = try XCTUnwrap(viewModel.drafts.first { $0.id == tomato.id })
        XCTAssertEqual(updated.name, "Cherry Tomato")
        XCTAssertEqual(updated.confidence, .medium)
    }

    // MARK: - Removal

    func test_removeDraft_dropsIncorrectDetection() async throws {
        let viewModel = await makeAnalyzedViewModel()
        let chicken = try XCTUnwrap(viewModel.drafts.first { $0.name == "Chicken" })

        viewModel.removeDraft(id: chicken.id)

        XCTAssertEqual(viewModel.drafts.map(\.name), ["Milk", "Eggs", "Tomato"])
    }

    func test_removeDraftsAtOffsets_dropsCorrectRows() async {
        let viewModel = await makeAnalyzedViewModel()

        viewModel.removeDrafts(at: IndexSet([0, 2]))

        XCTAssertEqual(viewModel.drafts.map(\.name), ["Eggs", "Chicken"])
    }

    // MARK: - Pantry mapping and insertion

    func test_addSelectedToPantry_mapsDetectionsOntoPantryItems() async throws {
        let repository = InMemoryPantryRepository()
        let viewModel = await makeAnalyzedViewModel(repository: repository)

        await viewModel.addSelectedToPantry()

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.map(\.name), ["Milk", "Eggs", "Tomato", "Chicken"])
        XCTAssertEqual(stored.map(\.ingredient.category), [.dairy, .other, .produce, .meat])
        XCTAssertEqual(viewModel.addSummary?.addedCount, 4)
        XCTAssertEqual(viewModel.addSummary?.isCompleteSuccess, true)
        XCTAssertFalse(viewModel.isAddingToPantry)
    }

    func test_addSelectedToPantry_onlyAddsSelectedDetections() async throws {
        let repository = InMemoryPantryRepository()
        let viewModel = await makeAnalyzedViewModel(repository: repository)
        let eggs = try XCTUnwrap(viewModel.drafts.first { $0.name == "Eggs" })
        let chicken = try XCTUnwrap(viewModel.drafts.first { $0.name == "Chicken" })

        viewModel.toggleSelection(for: eggs.id)
        viewModel.toggleSelection(for: chicken.id)
        await viewModel.addSelectedToPantry()

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.map(\.name), ["Milk", "Tomato"])
    }

    /// Added rows leave the review list, so a second tap can't re-add them.
    func test_addSelectedToPantry_removesAddedDraftsFromReview() async {
        let viewModel = await makeAnalyzedViewModel()

        await viewModel.addSelectedToPantry()

        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertFalse(viewModel.isPresentingReview)
    }

    // MARK: - Duplicate handling

    func test_addSelectedToPantry_respectsPantryDuplicateRule() async throws {
        let repository = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Tomato", category: .produce), quantity: 2, unit: .pieces)
        ])
        let viewModel = await makeAnalyzedViewModel(repository: repository)

        // The scan flagged Tomato as already present and left it unticked;
        // tick it anyway to prove the pantry rule still holds.
        let tomato = try XCTUnwrap(viewModel.drafts.first { $0.name == "Tomato" })
        XCTAssertTrue(tomato.isAlreadyInPantry)
        XCTAssertFalse(tomato.isSelected)
        viewModel.toggleSelection(for: tomato.id)

        await viewModel.addSelectedToPantry()

        let summary = try XCTUnwrap(viewModel.addSummary)
        XCTAssertEqual(summary.duplicateNames, ["Tomato"])
        XCTAssertFalse(summary.isCompleteSuccess)

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.filter { $0.name == "Tomato" }.count, 1)
        XCTAssertEqual(stored.first { $0.name == "Tomato" }?.quantity, 2, "Existing quantity must be untouched")

        // The rejected row stays so the user can deal with it.
        XCTAssertEqual(viewModel.drafts.map(\.name), ["Tomato"])
        XCTAssertTrue(viewModel.isPresentingReview)
    }

    // MARK: - Cancellation

    func test_cancelAnalysis_leavesNoStaleResults() async {
        let service = MockIngredientRecognitionService(
            result: .success(.sampleFridge),
            delay: .milliseconds(400)
        )
        let viewModel = makeViewModel(service: service)
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        XCTAssertTrue(viewModel.analysisState.isAnalyzing)

        viewModel.cancelAnalysis()

        XCTAssertEqual(viewModel.analysisState, .idle)

        // Well past when the cancelled scan would have finished.
        try? await Task.sleep(for: .milliseconds(600))

        XCTAssertEqual(viewModel.analysisState, .idle, "A cancelled scan must not publish results")
        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertFalse(viewModel.isPresentingReview)
    }

    /// Leaving the screen mid-scan is the same thing as cancelling.
    func test_reset_clearsEverythingAndStopsAnalysis() async {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .success(.sampleFridge), delay: .milliseconds(300))
        )
        viewModel.selectImage(TestImage.makeUIImage())
        viewModel.analyze()

        viewModel.reset()

        XCTAssertNil(viewModel.selectedImage)
        XCTAssertEqual(viewModel.analysisState, .idle)
        XCTAssertFalse(viewModel.isPresentingReview)

        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(viewModel.drafts.isEmpty)
    }

    /// A second analyze of a new photo must win, even if the first scan was
    /// slower and finishes later.
    func test_analyze_discardsResultsFromSupersededScan() async {
        let service = MockIngredientRecognitionService(
            result: .success(.sampleFridge),
            delay: .milliseconds(300)
        )
        let viewModel = makeViewModel(service: service)
        viewModel.selectImage(TestImage.makeUIImage())
        viewModel.analyze()

        // Picking a new photo drops the in-flight scan of the old one.
        viewModel.selectImage(TestImage.makeUIImage())

        service.delay = nil
        service.result = .success(IngredientDetectionResult(ingredients: [
            RawDetectedIngredient(name: "lettuce", category: "Produce", visibleCount: 1, confidence: "high")
        ]))
        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        XCTAssertEqual(viewModel.drafts.map(\.name), ["Lettuce"])

        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(viewModel.drafts.map(\.name), ["Lettuce"], "The older, slower scan must not overwrite the newer one")
    }

    /// Tapping Analyze twice must not run two scans.
    func test_analyze_ignoresRepeatedRequestsWhileAnalyzing() async {
        let service = MockIngredientRecognitionService(
            result: .success(.sampleFridge),
            delay: .milliseconds(150)
        )
        let viewModel = makeViewModel(service: service)
        viewModel.selectImage(TestImage.makeUIImage())

        viewModel.analyze()
        viewModel.analyze()
        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)

        XCTAssertEqual(service.recognizeCallCount, 1)
        XCTAssertEqual(viewModel.drafts.count, 4)
    }

    // MARK: - Image handling

    func test_selectImage_clearsPreviousResults() async {
        let viewModel = await makeAnalyzedViewModel()
        XCTAssertFalse(viewModel.drafts.isEmpty)

        viewModel.selectImage(TestImage.makeUIImage())

        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertEqual(viewModel.analysisState, .idle)
        XCTAssertNotNil(viewModel.selectedImage)
    }

    func test_clearImage_removesSelectedImage() async {
        let viewModel = await makeAnalyzedViewModel()

        viewModel.clearImage()

        XCTAssertNil(viewModel.selectedImage)
        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertEqual(viewModel.analysisState, .idle)
    }

    func test_reportImageLoadFailure_showsUserFacingError() async {
        let viewModel = makeViewModel(service: MockIngredientRecognitionService())

        viewModel.reportImageLoadFailure()

        XCTAssertEqual(
            viewModel.analysisState,
            .failed(message: IngredientRecognitionError.invalidImage.localizedDescription)
        )
    }

    func test_acknowledgeAddSummary_clearsSummary() async {
        let viewModel = await makeAnalyzedViewModel()
        await viewModel.addSelectedToPantry()
        XCTAssertNotNil(viewModel.addSummary)

        viewModel.acknowledgeAddSummary()

        XCTAssertNil(viewModel.addSummary)
    }

    // MARK: - Helpers

    /// A view model that has already completed a successful scan of
    /// `IngredientDetectionResult.sampleFridge`.
    private func makeAnalyzedViewModel(
        repository: InMemoryPantryRepository = InMemoryPantryRepository()
    ) async -> IngredientScannerViewModel {
        let viewModel = makeViewModel(
            service: MockIngredientRecognitionService(result: .success(.sampleFridge)),
            repository: repository
        )
        viewModel.selectImage(TestImage.makeUIImage())
        viewModel.analyze()
        await waitUntilAnalysisFinishes(viewModel)
        return viewModel
    }
}
