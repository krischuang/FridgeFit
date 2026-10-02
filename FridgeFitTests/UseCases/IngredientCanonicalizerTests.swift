//
//  IngredientCanonicalizerTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class IngredientCanonicalizerTests: XCTestCase {
    private let canonicalizer = IngredientCanonicalizer()

    private func canonical(_ name: String, model: String? = nil) -> String {
        canonicalizer.canonicalize(displayName: name, modelCanonicalName: model).canonicalName
    }

    // MARK: - Capsicum, the case with the most spellings

    func test_canonicalize_resolvesEveryCapsicumSpellingToOneIdentity() {
        for spelling in [
            "capsicum", "Capsicum", "CAPSICUM",
            "bell pepper", "Bell Pepper", "BELL PEPPER",
            "bell_pepper", "Bell_pepper",
            "pepper_veggie", "Pepper_veggie",
            "red capsicum", "Red Capsicum",
            "yellow bell pepper", "sweet pepper"
        ] {
            XCTAssertEqual(canonical(spelling), "bell_pepper", "\(spelling) should canonicalize to bell_pepper")
        }
    }

    // MARK: - The names the spec called out

    func test_canonicalize_collapsesChickenCuts() {
        XCTAssertEqual(canonical("Chicken"), "chicken")
        XCTAssertEqual(canonical("Chicken Breast"), "chicken")
        XCTAssertEqual(canonical("Chicken Fillet"), "chicken")
        XCTAssertEqual(canonical("Chicken Thigh"), "chicken")
    }

    func test_canonicalize_collapsesMushroomVarieties() {
        XCTAssertEqual(canonical("Mushroom"), "mushroom")
        XCTAssertEqual(canonical("Mushrooms"), "mushroom")
        XCTAssertEqual(canonical("Cup Mushrooms"), "mushroom")
        XCTAssertEqual(canonical("Button Mushrooms"), "mushroom")
    }

    func test_canonicalize_collapsesTomatoVarieties() {
        XCTAssertEqual(canonical("Tomato"), "tomato")
        XCTAssertEqual(canonical("Tomatoes"), "tomato")
        XCTAssertEqual(canonical("Cherry Tomatoes"), "tomato")
        XCTAssertEqual(canonical("Truss Tomatoes"), "tomato")
    }

    func test_canonicalize_collapsesSalmonCuts() {
        XCTAssertEqual(canonical("Salmon"), "salmon")
        XCTAssertEqual(canonical("Salmon Fillet"), "salmon")
        XCTAssertEqual(canonical("Salmon Portion"), "salmon")
        XCTAssertEqual(canonical("Atlantic Salmon"), "salmon")
    }

    func test_canonicalize_collapsesSaladLeaves() {
        XCTAssertEqual(canonical("Lettuce"), "lettuce")
        XCTAssertEqual(canonical("Leaf Lettuce"), "lettuce")
        XCTAssertEqual(canonical("Salad Greens"), "lettuce")
        XCTAssertEqual(canonical("Iceberg Lettuce"), "lettuce")
    }

    // MARK: - Distinctions worth keeping

    /// Descriptor removal must not reach inside a compound food. If
    /// `sweet` were stripped, sweet potato would silently merge into
    /// potato - a wrong merge the user has no way to notice.
    func test_canonicalize_protectsCompoundFoodsFromDescriptorRemoval() {
        XCTAssertEqual(canonical("Sweet Potato"), "sweet_potato")
        XCTAssertEqual(canonical("Potato"), "potato")
        XCTAssertNotEqual(canonical("Sweet Potato"), canonical("Potato"))

        XCTAssertEqual(canonical("Green Beans"), "green_bean")
        XCTAssertEqual(canonical("Spring Onions"), "spring_onion")
        XCTAssertNotEqual(canonical("Spring Onion"), canonical("Onion"))
    }

    /// A name made only of descriptors is a food in its own right, so the
    /// descriptors are kept rather than leaving nothing behind.
    func test_canonicalize_keepsNamesThatAreEntirelyDescriptorWords() {
        XCTAssertEqual(canonical("Cherry"), "cherry")
        XCTAssertEqual(canonical("Cherries"), "cherry")
    }

    func test_canonicalize_keepsUnrelatedFoodsApart() {
        XCTAssertNotEqual(canonical("Chicken"), canonical("Salmon"))
        XCTAssertNotEqual(canonical("Mushroom"), canonical("Tomato"))
    }

    // MARK: - Dialect

    func test_canonicalize_mapsDialectSynonyms() {
        XCTAssertEqual(canonical("Aubergine"), "eggplant")
        XCTAssertEqual(canonical("Courgette"), "zucchini")
        XCTAssertEqual(canonical("Cilantro"), "coriander")
        XCTAssertEqual(canonical("Kumara"), "sweet_potato")
    }

    // MARK: - Generalising beyond the table

    /// An ingredient the table has never heard of still needs a stable
    /// identity, otherwise the feature only works for foods someone
    /// remembered to list.
    func test_canonicalize_givesUnknownFoodsAStableIdentity() {
        XCTAssertEqual(canonical("Gochujang"), "gochujang")
        XCTAssertEqual(canonical("Za'atar"), "zaatar")
        XCTAssertEqual(canonical("Fresh Gochujang"), "gochujang")
        XCTAssertEqual(canonical("Gochujang"), canonical("gochujang"))
    }

    func test_canonicalize_isStableAcrossPunctuationAndSpacing() {
        XCTAssertEqual(canonical("  Greek   Yogurt  "), canonical("greek yogurt"))
        XCTAssertEqual(canonical("greek-yogurt"), canonical("greek yogurt"))
        XCTAssertEqual(canonical("greek_yogurt"), canonical("greek yogurt"))
    }

    // MARK: - Display names

    /// Canonical identifiers are an internal concern - the user sees the
    /// receipt's own wording.
    func test_canonicalize_keepsTheReadableNameForDisplay() {
        let result = canonicalizer.canonicalize(displayName: "Red Capsicum", modelCanonicalName: "capsicum")

        XCTAssertEqual(result.canonicalName, "bell_pepper")
        XCTAssertEqual(result.displayName, "Red Capsicum")
        XCTAssertFalse(result.displayName.contains("_"))
    }

    func test_canonicalize_titleCasesALowercaseDisplayName() {
        XCTAssertEqual(
            canonicalizer.canonicalize(displayName: "chicken breast").displayName,
            "Chicken Breast"
        )
    }

    /// If the model hands back an internal-looking identifier, it must not
    /// reach the screen.
    func test_canonicalize_replacesInternalLookingDisplayNames() {
        let result = canonicalizer.canonicalize(displayName: "bell_pepper", modelCanonicalName: "bell_pepper")

        XCTAssertEqual(result.canonicalName, "bell_pepper")
        XCTAssertEqual(result.displayName, "Capsicum")
    }

    // MARK: - Using the model's hint

    /// The model's suggestion is a hint, not an instruction: a nonsense
    /// suggestion must not beat a display name that resolves cleanly.
    func test_canonicalize_fallsBackToDisplayName_whenModelHintIsUnrecognised() {
        let result = canonicalizer.canonicalize(displayName: "Red Capsicum", modelCanonicalName: "zzzz")

        XCTAssertEqual(result.canonicalName, "bell_pepper")
    }

    func test_canonicalize_usesModelHint_whenItResolvesAndDisplayNameDoesNot() {
        let result = canonicalizer.canonicalize(displayName: "Woolies Own Capsicum Pack", modelCanonicalName: "capsicum")

        XCTAssertEqual(result.canonicalName, "bell_pepper")
    }

    // MARK: - Degenerate input

    func test_canonicalize_returnsEmpty_forNamesWithNothingInThem() {
        XCTAssertTrue(canonicalizer.canonicalize(displayName: "   ").canonicalName.isEmpty)
        XCTAssertTrue(canonicalizer.canonicalize(displayName: "!!!").canonicalName.isEmpty)
        XCTAssertTrue(canonicalizer.canonicalize(displayName: "").canonicalName.isEmpty)
    }
}
