//
//  CookingContextFormView.swift
//  FridgeFit
//

import SwiftUI

/// Lets the user say what they're in the mood for and what they can't eat.
///
/// Presented as a sheet from the recommendation screen. Edits a local copy
/// and only hands it back on "Apply", so backing out leaves the current
/// results alone.
///
/// Its own `NavigationStack` is correct here: a sheet is a separate
/// presentation context, so this does not nest inside the Recipes tab's
/// stack - the same pattern `PantryRecipeIdeasView` already uses.
struct CookingContextFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var context: CookingContext
    private let onApply: (CookingContext) -> Void

    init(context: CookingContext, onApply: @escaping (CookingContext) -> Void) {
        _context = State(initialValue: context)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    Picker("Maximum time", selection: $context.maximumCookingTime) {
                        ForEach(CookingTimeLimit.allCases) { limit in
                            Text(limit.displayName).tag(limit)
                        }
                    }
                }

                Section {
                    Picker("Maximum effort", selection: $context.maximumDifficulty) {
                        ForEach(CookingDifficulty.allCases) { difficulty in
                            Text(difficulty.displayName).tag(difficulty)
                        }
                    }
                } header: {
                    Text("Effort")
                } footer: {
                    Text("Recipes that don't state a time or difficulty are still shown, but aren't ranked up for fitting your limits.")
                }

                Section {
                    Toggle(isOn: $context.prioritisesExpiringIngredients) {
                        Text("Use food expiring soon first")
                    }
                } footer: {
                    Text("Ranks meals that use food approaching its date ahead of others. Food already past its date is never ranked up.")
                }

                multiSelectSection(
                    title: "Cuisines",
                    footer: "Preferences only - these never hide a meal.",
                    options: Cuisine.allCases,
                    selection: $context.preferredCuisines,
                    label: \.displayName
                )

                multiSelectSection(
                    title: "Tastes",
                    footer: "Preferences only - these never hide a meal.",
                    options: TastePreference.allCases,
                    selection: $context.preferredTastes,
                    label: \.displayName
                )

                multiSelectSection(
                    title: "Dietary requirements",
                    footer: "FridgeFit only matches a requirement a recipe has been explicitly assessed for. Recipes with no dietary information are withheld rather than assumed safe, and none of the bundled recipes are assessed for nut content.",
                    options: DietaryRestriction.allCases,
                    selection: $context.dietaryRestrictions,
                    label: \.displayName
                )

                Section {
                    Button("Reset to no preferences") {
                        context = .unrestricted
                    }
                }
            }
            .navigationTitle("Cooking Preferences")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(context)
                        dismiss()
                    }
                }
            }
        }
    }

    /// A tappable multi-select list section.
    ///
    /// Generic over the option type so cuisines, tastes, and restrictions
    /// share one implementation instead of three near-identical copies.
    @ViewBuilder
    private func multiSelectSection<Option: Hashable & Identifiable & CaseIterable>(
        title: String,
        footer: String,
        options: [Option],
        selection: Binding<Set<Option>>,
        label: KeyPath<Option, String>
    ) -> some View {
        Section {
            ForEach(options) { option in
                Button {
                    if selection.wrappedValue.contains(option) {
                        selection.wrappedValue.remove(option)
                    } else {
                        selection.wrappedValue.insert(option)
                    }
                } label: {
                    HStack {
                        Text(option[keyPath: label])
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.wrappedValue.contains(option) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityAddTraits(
                    selection.wrappedValue.contains(option) ? .isSelected : []
                )
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }
}

#Preview {
    CookingContextFormView(context: .unrestricted) { _ in }
}
