//
//  OnlineDietaryPolicyTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Pins the allergen and diet policy so a later edit cannot quietly widen
/// what FridgeFit claims about online recipes.
@MainActor
final class OnlineDietaryPolicyTests: XCTestCase {

    // MARK: - The assessable / unassessable split

    func test_provenanceGradeIntolerancesAreNotSelectable() {
        let unassessable = Set(FoodIntolerance.unassessableCases)

        // These four are the ones `main` withdrew, plus sulfites, which are
        // an added preservative no ingredient name discloses.
        XCTAssertTrue(unassessable.contains(.gluten))
        XCTAssertTrue(unassessable.contains(.wheat))
        XCTAssertTrue(unassessable.contains(.peanut))
        XCTAssertTrue(unassessable.contains(.treeNut))
        XCTAssertTrue(unassessable.contains(.sulfite))
    }

    func test_assessableAndUnassessableArePartitionsOfAllCases() {
        let assessable = Set(FoodIntolerance.assessableCases)
        let unassessable = Set(FoodIntolerance.unassessableCases)

        XCTAssertTrue(assessable.isDisjoint(with: unassessable))
        XCTAssertEqual(assessable.union(unassessable), Set(FoodIntolerance.allCases))
        XCTAssertFalse(assessable.isEmpty, "The filter would be pointless with nothing selectable")
    }

    func test_everyUnassessableIntoleranceExplainsItself() {
        for intolerance in FoodIntolerance.unassessableCases {
            XCTAssertNotNil(
                intolerance.unassessableExplanation,
                "\(intolerance.displayName) is withheld with no reason given to the user"
            )
        }
    }

    func test_assessableIntolerancesHaveNoExplanationToShow() {
        for intolerance in FoodIntolerance.assessableCases {
            XCTAssertNil(intolerance.unassessableExplanation)
        }
    }

    func test_intoleranceBasisAgreesWithMainsDietaryRestrictionPolicy() {
        // The two vocabularies must not drift. Gluten is provenance-grade in
        // both; dairy is composition-grade in both.
        XCTAssertEqual(DietaryRestriction.glutenFree.assessmentBasis, .productProvenance)
        XCTAssertEqual(FoodIntolerance.gluten.assessmentBasis, .productProvenance)

        XCTAssertEqual(DietaryRestriction.dairyFree.assessmentBasis, .composition)
        XCTAssertEqual(FoodIntolerance.dairy.assessmentBasis, .composition)

        XCTAssertEqual(DietaryRestriction.nutFree.assessmentBasis, .productProvenance)
        XCTAssertEqual(FoodIntolerance.peanut.assessmentBasis, .productProvenance)
        XCTAssertEqual(FoodIntolerance.treeNut.assessmentBasis, .productProvenance)
    }

    // MARK: - Diet preferences

    func test_dietPreferencesOfferNoGlutenFreeOption() {
        // `main` withdrew the gluten-free claim; offering it against
        // third-party data would be strictly worse.
        let rawValues = DietPreference.allCases.map(\.rawValue)
        XCTAssertFalse(rawValues.contains("Gluten Free"))

        for diet in DietPreference.allCases {
            XCTAssertFalse(
                diet.displayName.lowercased().contains("gluten"),
                "\(diet.displayName) reintroduces a gluten-free claim"
            )
        }
    }

    func test_noPreferenceSendsNoDietParameter() {
        XCTAssertNil(DietPreference.none.apiValue)
        XCTAssertEqual(DietPreference.vegan.apiValue, "Vegan")
    }

    // MARK: - Sanitising

    func test_sanitizedDropsUnassessableIntolerances() {
        let preferences = OnlineRecipePreferences(
            diet: .vegan,
            intolerances: [.gluten, .peanut, .dairy, .egg],
            maxReadyTimeMinutes: 30
        )

        let sanitized = preferences.sanitized()

        XCTAssertEqual(sanitized.intolerances, [.dairy, .egg])
        XCTAssertEqual(sanitized.diet, .vegan, "Sanitising must not disturb anything else")
        XCTAssertEqual(sanitized.maxReadyTimeMinutes, 30)
    }

    func test_sanitizedIsIdempotent() {
        let once = OnlineRecipePreferences(intolerances: [.gluten, .dairy]).sanitized()
        XCTAssertEqual(once.sanitized(), once)
    }

    func test_storeSanitisesOnLoad() {
        // A value persisted by an earlier build could name gluten. Loading
        // it must not reinstate a filter the app does not perform.
        let store = InMemoryOnlineRecipePreferencesStore(
            preferences: OnlineRecipePreferences(intolerances: [.gluten, .dairy])
        )

        XCTAssertEqual(store.load().intolerances, [.dairy])
    }

    func test_userDefaultsStoreSanitisesOnLoad() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OnlineDietaryPolicyTests"))
        defaults.removePersistentDomain(forName: "OnlineDietaryPolicyTests")
        let store = UserDefaultsOnlineRecipePreferencesStore(defaults: defaults, key: "prefs")

        // Write a value that names an unassessable intolerance, the way an
        // older build would have.
        store.save(OnlineRecipePreferences(intolerances: [.gluten, .treeNut, .soy]))

        XCTAssertEqual(store.load().intolerances, [.soy])
        defaults.removePersistentDomain(forName: "OnlineDietaryPolicyTests")
    }

    // MARK: - Never claim allergen safety without evidence

    func test_unverifiedRecipeIsNeverSafeForSomeoneWithAnIntolerance() {
        let unverified = OnlineRecipeFixtures.recipe(intolerances: nil)

        XCTAssertFalse(FindOnlineRecipesFromPantryUseCase.isSafe(unverified, for: [.dairy]))
        XCTAssertTrue(
            FindOnlineRecipesFromPantryUseCase.isSafe(unverified, for: []),
            "With no intolerance selected there is nothing to fail"
        )
    }

    func test_screenedClearRecipeIsSafeOnlyForIntolerancesItWasScreenedFor() {
        let screened = OnlineRecipeFixtures.recipe(intolerances: [.soy])

        XCTAssertTrue(FindOnlineRecipesFromPantryUseCase.isSafe(screened, for: [.dairy]))
        XCTAssertFalse(FindOnlineRecipesFromPantryUseCase.isSafe(screened, for: [.soy]))
    }
}
