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

/// One user-confirmed ingredient, ready to be stored.
///
/// A storage-shaped value with no knowledge of where it came from, so the
/// receipt scanner and the remote-camera review sheet can both reach the
/// pantry through the same use case. `ReceiptItemDraft` carries a
/// `ReceiptIngredientCandidate` it cannot exist without; a recognised
/// ingredient has no receipt line, and inventing an empty one to satisfy the
/// type would be a lie about provenance.
///
/// `quantity` is optional on purpose. Both flows deliberately refuse to
/// invent an amount nobody stated - see `ReceiptItemDraft`'s note about the
/// old fridge-scan defaulting every row to `1 pcs`. A `nil` here is reported
/// as a failure with a message telling the user what to fill in.
struct ConfirmedIngredientDraft: Equatable {
    /// The name to store. Passed to `AddPantryItemUseCase` exactly as given,
    /// including when it is blank - validation belongs there, not here.
    let name: String
    /// The name to use when *reporting* this row's outcome.
    ///
    /// Separate from `name` because a row the user blanked must still fail
    /// validation, while the failure message needs something to call it.
    /// Collapsing the two would quietly store the fallback instead.
    let reportingName: String
    /// `nil` when the user has not supplied one. Never defaulted.
    let quantity: Double?
    let unit: MeasurementUnit
    let category: IngredientCategory

    init(
        name: String,
        reportingName: String? = nil,
        quantity: Double?,
        unit: MeasurementUnit,
        category: IngredientCategory
    ) {
        self.name = name
        self.reportingName = reportingName ?? name
        self.quantity = quantity
        self.unit = unit
        self.category = category
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

    init(addPantryItemUseCase: AddPantryItemUseCase) {
        self.addPantryItemUseCase = addPantryItemUseCase
    }

    init(pantryRepository: PantryRepository) {
        self.init(addPantryItemUseCase: AddPantryItemUseCase(pantryRepository: pantryRepository))
    }

    /// Adds each draft through `AddPantryItemUseCase`, in order.
    ///
    /// Drafts with no usable quantity are reported as failures rather than
    /// defaulted to a number the user didn't ask for. That is the normal
    /// outcome for a receipt line that never stated an amount and the user
    /// left blank, and the message tells them exactly what to fix.
    func execute(drafts: [ReceiptItemDraft]) async -> AddDetectedIngredientsSummary {
        await execute(confirmed: drafts.map { draft in
            ConfirmedIngredientDraft(
                // Stored exactly as typed, so a blanked row still fails
                // validation; the display name is only the fallback for
                // saying *which* row failed.
                name: draft.trimmedName,
                reportingName: draft.trimmedName.isEmpty ? draft.candidate.displayName : draft.trimmedName,
                quantity: draft.quantity,
                unit: draft.unit,
                category: draft.category
            )
        })
    }

    /// Adds each confirmed ingredient through `AddPantryItemUseCase`, in order.
    ///
    /// One shared implementation for both callers. Per-item outcomes are
    /// collected rather than aborting on the first problem, so a basket of a
    /// dozen ingredients cannot be stopped dead by one duplicate.
    func execute(confirmed drafts: [ConfirmedIngredientDraft]) async -> AddDetectedIngredientsSummary {
        var addedNames: [String] = []
        var duplicateNames: [String] = []
        var failures: [AddDetectedIngredientsSummary.Failure] = []

        for draft in drafts {
            let name = draft.reportingName

            guard let quantity = draft.quantity else {
                failures.append(.init(name: name, message: AddPantryItemError.invalidQuantity.errorDescription ?? "Invalid quantity."))
                continue
            }

            do {
                try await addPantryItemUseCase.execute(
                    name: draft.name,
                    quantity: quantity,
                    unit: draft.unit,
                    category: draft.category
                )
                addedNames.append(name)
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
