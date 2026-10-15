//
//  AddDetectedIngredientsUseCase.swift
//  FridgeFit
//

import Foundation

/// What happened when confirmed scan results were sent to the pantry.
///
/// A receipt can add ten ingredients at once, so "did it work" isn't a yes
/// or no - some can succeed while others are rejected as duplicates. Each
/// outcome is reported by name so the confirmation screen can say exactly
/// what went in and what didn't.
struct AddDetectedIngredientsSummary: Equatable {
    /// Names added to the pantry.
    let addedNames: [String]
    /// Names rejected by `AddPantryItemUseCase`'s duplicate rule.
    let duplicateNames: [String]
    /// Names that failed for any other reason, with the reason.
    let failures: [Failure]

    struct Failure: Equatable {
        let name: String
        let message: String
    }

    var addedCount: Int { addedNames.count }
    var isCompleteSuccess: Bool { duplicateNames.isEmpty && failures.isEmpty }

    /// One line summarising the result, for the pantry screen to show after
    /// the review sheet closes.
    var userMessage: String {
        var parts: [String] = []

        switch addedNames.count {
        case 0: break
        case 1: parts.append("Added \(addedNames[0]) to your pantry.")
        default: parts.append("Added \(addedNames.count) ingredients to your pantry.")
        }

        if !duplicateNames.isEmpty {
            let names = ListFormatter.localizedString(byJoining: duplicateNames)
            parts.append("\(names) \(duplicateNames.count == 1 ? "was" : "were") already in your pantry, so \(duplicateNames.count == 1 ? "it" : "they") stayed unchanged.")
        }

        if !failures.isEmpty {
            let names = ListFormatter.localizedString(byJoining: failures.map(\.name))
            parts.append("Couldn't add \(names).")
        }

        return parts.isEmpty ? "Nothing was added to your pantry." : parts.joined(separator: " ")
    }
}

/// Adds user-confirmed scan results to the pantry.
///
/// Deliberately thin: it does no validation, no duplicate checking and no
/// storage of its own, because all of that already exists in
/// `AddPantryItemUseCase`. Its only job is to run that use case once per
/// confirmed draft and collect the per-item outcomes, so a receipt of a
/// dozen ingredients can't be stopped dead by one duplicate.
///
/// This is the only path from a scan into the pantry. The scanner UI has no
/// repository and no Firestore access of its own.
struct AddDetectedIngredientsUseCase {
    private let addPantryItemUseCase: AddPantryItemUseCase
    /// Gets told what each added item cost, when the receipt said. Optional so
    /// the scanner still works fine without the Budget tab.
    private let priceRecorder: PurchasePriceRecording?

    init(addPantryItemUseCase: AddPantryItemUseCase, priceRecorder: PurchasePriceRecording? = nil) {
        self.addPantryItemUseCase = addPantryItemUseCase
        self.priceRecorder = priceRecorder
    }

    init(pantryRepository: PantryRepository, priceRecorder: PurchasePriceRecording? = nil) {
        self.init(addPantryItemUseCase: AddPantryItemUseCase(pantryRepository: pantryRepository),
                  priceRecorder: priceRecorder)
    }

    /// Adds each draft through `AddPantryItemUseCase`, in order.
    ///
    /// Drafts with no usable quantity are reported as failures rather than
    /// defaulted to a number the user didn't ask for. That is the normal
    /// outcome for a receipt line that never stated an amount and the user
    /// left blank, and the message tells them exactly what to fix.
    func execute(drafts: [ReceiptItemDraft]) async -> AddDetectedIngredientsSummary {
        var addedNames: [String] = []
        var duplicateNames: [String] = []
        var failures: [AddDetectedIngredientsSummary.Failure] = []

        for draft in drafts {
            let name = draft.trimmedName.isEmpty ? draft.candidate.displayName : draft.trimmedName

            guard let quantity = draft.quantity else {
                failures.append(.init(name: name, message: AddPantryItemError.invalidQuantity.errorDescription ?? "Invalid quantity."))
                continue
            }

            do {
                let added = try await addPantryItemUseCase.execute(
                    name: draft.trimmedName,
                    quantity: quantity,
                    unit: draft.unit,
                    category: draft.category
                )
                addedNames.append(name)
                // only for items that actually went in - a rejected duplicate
                // shouldn't get a price attached to the old entry
                if let price = draft.price {
                    priceRecorder?.recordPurchasePrice(price, for: added)
                }
            } catch AddPantryItemError.duplicateIngredient(let existingName) {
                duplicateNames.append(existingName)
            } catch let error as AddPantryItemError {
                failures.append(.init(name: name, message: error.errorDescription ?? "Couldn't add \(name)."))
            } catch {
                failures.append(.init(name: name, message: error.localizedDescription))
            }
        }

        return AddDetectedIngredientsSummary(
            addedNames: addedNames,
            duplicateNames: duplicateNames,
            failures: failures
        )
    }
}
