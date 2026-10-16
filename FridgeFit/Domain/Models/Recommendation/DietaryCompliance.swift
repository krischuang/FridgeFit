//
//  DietaryCompliance.swift
//  FridgeFit
//

import Foundation

/// Whether a recipe is known to satisfy the restrictions the user selected.
///
/// ## Why "unknown" is a case and not a `Bool`
///
/// `Recipe.dietaryLabels` is optional, because recipes that predate the
/// recommendation feature - and anything a future remote source supplies
/// without labels - genuinely have none recorded. The source branch this
/// was ported from compared `restrictions.isSubset(of: labels)` against an
/// empty set, which silently produced the same answer as "this recipe
/// conflicts". Those are different facts and the user deserves to be told
/// which one applies.
///
/// A missing label is never read as compliance. `nutFree` is a safety
/// requirement, not a preference, and "we were never told" is not
/// evidence - so `.unknown` excludes the recipe exactly as `.violated`
/// does, and only the wording shown to the user differs.
nonisolated enum DietaryCompliance: Equatable, Hashable, Sendable {
    /// Every restriction the user selected appears in the recipe's labels.
    case satisfied
    /// The recipe is labelled, and at least one selected restriction is
    /// absent from those labels.
    case violated(missing: Set<DietaryRestriction>)
    /// The recipe carries no dietary labels at all, so compliance cannot
    /// be established either way.
    case unknown

    /// Whether this recipe may be offered to the user.
    ///
    /// `false` for `.unknown` by design - see the type's discussion.
    var isSafeToRecommend: Bool {
        self == .satisfied
    }
}

nonisolated extension Recipe {
    /// Checks this recipe's labels against the restrictions the user
    /// selected.
    ///
    /// An empty `restrictions` set is trivially satisfied: a user who
    /// selected no dietary requirements has nothing for an unlabelled
    /// recipe to fail, which is what keeps unlabelled recipes usable in
    /// the default context.
    func dietaryCompliance(
        with restrictions: Set<DietaryRestriction>
    ) -> DietaryCompliance {
        guard !restrictions.isEmpty else { return .satisfied }
        guard let dietaryLabels else { return .unknown }

        let missing = restrictions.subtracting(dietaryLabels)
        return missing.isEmpty ? .satisfied : .violated(missing: missing)
    }
}
