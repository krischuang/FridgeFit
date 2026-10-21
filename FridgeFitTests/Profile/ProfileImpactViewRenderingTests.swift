//
//  ProfileImpactViewRenderingTests.swift
//  FridgeFitTests
//

import SwiftUI
import UIKit
import XCTest
@testable import FridgeFit

/// Renders Profile → Impact & Budget headlessly in each of its data states.
///
/// A hosting controller evaluates and lays out every view body, so a trap, a
/// bad layout calculation or a force-unwrap in one of the empty states fails
/// here rather than on a device. Taps, sheets and navigation are not
/// exercised.
@MainActor
final class ProfileImpactViewRenderingTests: XCTestCase {

    func test_rendersWithNothingRecorded() {
        assertRenders(makeView(funds: .inMemory(pantryRepository: InMemoryPantryRepository())))
    }

    func test_rendersWithoutFridgeFundsWiredIn() {
        assertRenders(makeView(funds: nil))
    }

    func test_rendersWithABudgetAndPricedExpiringStock() async throws {
        let pantry = InMemoryPantryRepository(seedItems: [
            item("Baby Spinach", category: .produce, quantity: 1, expiresInDays: 1),
            item("Brown Mushrooms", category: .produce, quantity: 1, expiresInDays: 2),
            item("Greek Yogurt", category: .dairy, quantity: 1, expiresInDays: 3),
            item("Rice", category: .grain, quantity: 2, expiresInDays: 180),
        ])
        let funds = FundsEnvironment.inMemory(pantryRepository: pantry)
        funds.budgetStore.saveBudget(FoodBudget(limit: Money(320, .aud), cadence: .fortnightly, startDate: .now))
        funds.budgetStore.addSpend(GrocerySpend(amount: Money(Decimal(string: "214.50")!, .aud), spentOn: .now))
        await funds.reload()
        for snapshot in funds.pantry.allItems() where snapshot.name != "Rice" {
            funds.priceStore.save(ItemPriceInfo(pantryItemID: snapshot.id, unitCost: Money(Decimal(string: "3.80")!, .aud)))
        }

        assertRenders(makeView(funds: funds))
    }

    func test_rendersWithAnUnpricedFridge() async {
        let pantry = InMemoryPantryRepository(seedItems: [
            item("Leftover Sauce", category: .other, quantity: 1, expiresInDays: 1)
        ])
        let funds = FundsEnvironment.inMemory(pantryRepository: pantry)
        await funds.reload()

        assertRenders(makeView(funds: funds))
    }

    // MARK: - Helpers

    private func makeView(funds: FundsEnvironment?) -> some View {
        ScrollView {
            ProfileImpactView(
                inventory: InventoryStore(
                    pantryRepository: InMemoryPantryRepository(),
                    eventRepository: InMemoryInventoryEventRepository()
                ),
                funds: funds,
                onFindRecipes: {},
                onOpenPantry: {}
            )
            .padding(FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas)
    }

    private func item(
        _ name: String,
        category: IngredientCategory,
        quantity: Double,
        expiresInDays: Int
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name, category: category),
            quantity: quantity,
            unit: .pieces,
            expiryDate: Calendar.current.date(byAdding: .day, value: expiresInDays, to: .now)
        )
    }

    private func assertRenders(
        _ view: some View,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let size = CGSize(width: 390, height: 844)
        let hostingController = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        hostingController.view.bounds = CGRect(origin: .zero, size: size)
        hostingController.view.backgroundColor = .clear
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            hostingController.view.layer.render(in: context.cgContext)
        }

        XCTAssertGreaterThan(image.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, file: file, line: line)
    }
}
