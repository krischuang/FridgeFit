//
//  IngredientReviewViewModelTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import XCTest
@testable import FridgeFit

/// The review step: what the user can change, and what they end up with.
@MainActor
final class IngredientReviewViewModelTests: XCTestCase {

    private let box = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)

    private func fused(
        _ ingredient: String,
        tier: ConfidenceTier = .singleSource,
        category: IngredientGroup = .fruit,
        localised: Bool = true,
        asserts: Bool = true,
        sources: EvidenceSources = .detector
    ) -> FusedIngredient {
        FusedIngredient(
            ingredientId: ingredient,
            displayName: ingredient.capitalized,
            category: category,
            tier: tier,
            sources: sources,
            boundingBox: localised ? box : nil,
            detectorConfidence: 0.8,
            assertsIngredient: asserts
        )
    }

    private func model(_ ingredients: [FusedIngredient]) -> IngredientReviewViewModel {
        IngredientReviewViewModel(items: ingredients.map(IngredientReviewItem.init))
    }

    // MARK: - Preselection

    /// Only agreement is pre-ticked, and even that is a default.
    func test_onlyAgreedItemsStartAccepted() {
        let viewModel = model([
            fused("apple", tier: .agreed),
            fused("banana", tier: .singleSource),
            fused("tomato", tier: .conflicting, category: .vegetable),
        ])

        XCTAssertEqual(viewModel.acceptedCount, 1)
        XCTAssertTrue(viewModel.items.first { $0.displayName == "Apple" }!.isAccepted)
        XCTAssertFalse(viewModel.items.first { $0.displayName == "Banana" }!.isAccepted)
        XCTAssertFalse(viewModel.items.first { $0.displayName == "Tomato" }!.isAccepted)
    }

    func test_anUnassertedConflictIsNeverPreselected() {
        let viewModel = model([fused("apple", tier: .agreed, asserts: false)])

        XCTAssertEqual(viewModel.acceptedCount, 0,
                       "if nothing is asserted there is nothing to pre-tick")
    }

    // MARK: - Accept and reject

    func test_acceptingAndRejecting() {
        let viewModel = model([fused("banana")])
        let id = viewModel.items[0].id

        viewModel.accept(id)
        XCTAssertTrue(viewModel.items[0].isAccepted)

        viewModel.reject(id)
        XCTAssertFalse(viewModel.items[0].isAccepted)

        viewModel.toggleAcceptance(id)
        XCTAssertTrue(viewModel.items[0].isAccepted)
    }

    func test_acceptAllAndRejectAll() {
        let viewModel = model([fused("apple"), fused("banana"), fused("pear")])

        viewModel.acceptAll()
        XCTAssertEqual(viewModel.acceptedCount, 3)

        viewModel.rejectAll()
        XCTAssertEqual(viewModel.acceptedCount, 0)
    }

    // MARK: - Corrections

    func test_renamingAnIngredient() {
        let viewModel = model([fused("apple")])
        let id = viewModel.items[0].id

        viewModel.rename(id, to: "Pink Lady Apple")

        XCTAssertEqual(viewModel.items[0].displayName, "Pink Lady Apple")
        XCTAssertTrue(viewModel.items[0].wasEdited)
    }

    func test_renamingTrimsWhitespaceAndRejectsBlank() {
        let viewModel = model([fused("apple")])
        let id = viewModel.items[0].id

        viewModel.rename(id, to: "  Braeburn  ")
        XCTAssertEqual(viewModel.items[0].displayName, "Braeburn")

        viewModel.rename(id, to: "   ")
        XCTAssertEqual(viewModel.items[0].displayName, "Braeburn",
                       "a blank edit must not erase the name")
    }

    func test_correctingTheCategory() {
        let viewModel = model([fused("tomato", category: .fruit)])
        let id = viewModel.items[0].id

        viewModel.recategorise(id, to: .vegetable)

        XCTAssertEqual(viewModel.items[0].category, .vegetable)
        XCTAssertTrue(viewModel.items[0].wasEdited)
    }

    /// Decoy is an internal vocabulary device, not a user-facing category.
    func test_theDecoyCategoryCannotBeChosen() {
        let viewModel = model([fused("apple")])
        let id = viewModel.items[0].id

        viewModel.recategorise(id, to: .decoy)

        XCTAssertEqual(viewModel.items[0].category, .fruit, "decoy must be refused")
    }

    /// An edit must not rewrite what the model said - that is the only way to
    /// tell later whether the model was wrong or the mapping was.
    func test_editingDoesNotAlterTheRecognitionRecord() {
        let viewModel = model([fused("apple")])
        let id = viewModel.items[0].id

        viewModel.rename(id, to: "Quince")
        viewModel.recategorise(id, to: .vegetable)

        XCTAssertEqual(viewModel.items[0].recognised?.displayName, "Apple")
        XCTAssertEqual(viewModel.items[0].recognised?.category, .fruit)
    }

    // MARK: - Manual additions

    func test_addingAMissedIngredient() {
        let viewModel = model([fused("apple")])

        XCTAssertTrue(viewModel.addManualIngredient(name: "Cheddar", category: .dairy))

        let added = try! XCTUnwrap(viewModel.items.last)
        XCTAssertEqual(added.displayName, "Cheddar")
        XCTAssertEqual(added.category, .dairy)
        XCTAssertEqual(added.origin, .manual)
        XCTAssertTrue(added.isAccepted, "the user typed it, so it is accepted")
        XCTAssertNil(added.boundingBox, "a typed ingredient has no location")
        XCTAssertFalse(added.requiresReview)
    }

    func test_aBlankManualNameIsRefused() {
        let viewModel = model([])

        XCTAssertFalse(viewModel.addManualIngredient(name: "   ", category: .dairy))
        XCTAssertTrue(viewModel.isEmpty)
    }

    func test_aDuplicateManualNameIsRefused() {
        let viewModel = model([fused("apple")])

        XCTAssertFalse(viewModel.addManualIngredient(name: "apple", category: .fruit),
                       "case-insensitive duplicate")
        XCTAssertEqual(viewModel.items.count, 1)
    }

    func test_aManualIngredientCanBeRemoved() {
        let viewModel = model([])
        viewModel.addManualIngredient(name: "Cheddar", category: .dairy)
        let id = viewModel.items[0].id

        viewModel.remove(id)

        XCTAssertTrue(viewModel.isEmpty)
    }

    // MARK: - Localised vs unlocalised

    /// The separation that stops a whole-image label being drawn as a box.
    func test_localisedAndUnlocalisedItemsAreKeptApart() {
        let viewModel = model([
            fused("apple", localised: true),
            fused("salmon_fillet", category: .seafood, localised: false, sources: .sceneClassifier),
        ])
        viewModel.addManualIngredient(name: "Cheddar", category: .dairy)

        XCTAssertEqual(viewModel.localisedItems.map(\.displayName), ["Apple"])
        XCTAssertEqual(Set(viewModel.unlocalisedItems.map(\.displayName)),
                       ["Salmon_Fillet", "Cheddar"])
        for item in viewModel.unlocalisedItems {
            XCTAssertNil(item.boundingBox)
        }
    }

    // MARK: - Confirming

    func test_confirmingKeepsOnlyAcceptedItems() {
        let viewModel = model([
            fused("apple", tier: .agreed),
            fused("banana"),
        ])
        viewModel.addManualIngredient(name: "Cheddar", category: .dairy)

        let confirmed = viewModel.confirm()

        XCTAssertEqual(Set(confirmed.map(\.name)), ["Apple", "Cheddar"])
        XCTAssertEqual(viewModel.confirmed?.count, 2)
    }

    func test_aConfirmedIngredientRecordsHowItGotThere() {
        let viewModel = model([fused("apple", tier: .agreed)])
        viewModel.rename(viewModel.items[0].id, to: "Braeburn")
        viewModel.addManualIngredient(name: "Cheddar", category: .dairy)

        let confirmed = viewModel.confirm()

        let edited = try! XCTUnwrap(confirmed.first { $0.name == "Braeburn" })
        XCTAssertTrue(edited.wasCorrected)
        XCTAssertFalse(edited.wasManuallyAdded)
        XCTAssertEqual(edited.recognisedIngredientId, "apple",
                       "traceable back to what recognition proposed")

        let manual = try! XCTUnwrap(confirmed.first { $0.name == "Cheddar" })
        XCTAssertTrue(manual.wasManuallyAdded)
        XCTAssertNil(manual.recognisedIngredientId)
    }

    func test_confirmingNothingProducesAnEmptyResult() {
        let viewModel = model([fused("apple"), fused("banana")])

        XCTAssertTrue(viewModel.confirm().isEmpty)
    }

    // MARK: - Empty

    func test_anAnalysisWithNoResultsProducesAnEmptyReview() {
        let viewModel = IngredientReviewViewModel(analysis: .empty)

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.acceptedCount, 0)
        XCTAssertTrue(viewModel.packagingLines.isEmpty)
    }

    /// Even with nothing recognised, the user can still record what is there.
    func test_anEmptyReviewStillAcceptsManualAdditions() {
        let viewModel = IngredientReviewViewModel(analysis: .empty)

        XCTAssertTrue(viewModel.addManualIngredient(name: "Salmon", category: .seafood))

        XCTAssertEqual(viewModel.confirm().map(\.name), ["Salmon"])
    }

    // MARK: - Analysis plumbing

    func test_packagingTextReachesTheReviewUnmatched() {
        let analysis = SnapshotAnalysis(
            snapshotId: UUID(),
            fused: .empty,
            fullImageBaseline: .empty,
            packaging: PackagedFoodReading(
                lines: ["ГЕРКУЛЕС", "ICE CREAM"],
                matches: [],
                nonLatinLines: ["ГЕРКУЛЕС"]
            ),
            duration: 0.5
        )

        let viewModel = IngredientReviewViewModel(analysis: analysis)

        XCTAssertEqual(viewModel.packagingLines, ["ГЕРКУЛЕС", "ICE CREAM"])
        XCTAssertEqual(viewModel.nonLatinPackagingLines, ["ГЕРКУЛЕС"])
        XCTAssertTrue(viewModel.isEmpty, "unmatched packaging text is not an ingredient")
    }
}
