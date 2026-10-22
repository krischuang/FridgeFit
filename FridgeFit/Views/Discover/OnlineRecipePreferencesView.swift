//
//  OnlineRecipePreferencesView.swift
//  FridgeFit
//

import SwiftUI

/// Filters for the Discover tab: diet, intolerances, and a time limit.
///
/// Only `FoodIntolerance.assessableCases` are selectable. The rest are
/// listed in a separate, non-selectable section that says why - the same
/// treatment `CookingContextFormView` gives `glutenFree` and `nutFree`, and
/// for the same reason: a filter the app cannot honour returns an empty list
/// and blames the user's preferences for a limitation that is the app's.
struct OnlineRecipePreferencesView: View {
    let onSave: (OnlineRecipePreferences) -> Void
    @State private var draft: OnlineRecipePreferences
    @Environment(\.dismiss) private var dismiss

    private static let timeOptions: [Int?] = [nil, 15, 30, 45, 60, 90]

    init(initial: OnlineRecipePreferences, onSave: @escaping (OnlineRecipePreferences) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: initial.sanitized())
    }

    var body: some View {
        Form {
            Section {
                Picker("Diet", selection: $draft.diet) {
                    ForEach(DietPreference.allCases) { diet in
                        Text(diet.displayName).tag(diet)
                    }
                }
            } header: {
                Text("Diet")
            } footer: {
                Text("Narrows the search at the recipe service. FridgeFit doesn't label saved recipes as meeting a diet, so a saved recipe is still withheld from recommendations when you've set a dietary restriction.")
            }

            Section {
                ForEach(FoodIntolerance.assessableCases) { intolerance in
                    Toggle(intolerance.displayName, isOn: binding(for: intolerance))
                }
            } header: {
                Text("Avoid")
            } footer: {
                Text("Recipes that contain these - or whose ingredients couldn't be screened at all - are hidden. The screen reads ingredient names only.")
            }

            unassessableSection

            Section("Time") {
                Picker("Ready within", selection: $draft.maxReadyTimeMinutes) {
                    ForEach(Self.timeOptions, id: \.self) { option in
                        Text(option.map { "\($0) min" } ?? "Any time").tag(option)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FridgeFitTheme.ColorToken.canvas)
        .tint(FridgeFitTheme.ColorToken.primary)
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draft.sanitized())
                    dismiss()
                }
            }
        }
    }

    /// The intolerances FridgeFit deliberately does not offer, each with its
    /// reason. Shown rather than omitted so the absence is an explained
    /// decision instead of a gap the user has to guess at.
    @ViewBuilder
    private var unassessableSection: some View {
        let unassessable = FoodIntolerance.unassessableCases
        if !unassessable.isEmpty {
            Section {
                ForEach(unassessable) { intolerance in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                            Text(intolerance.displayName)
                            Spacer()
                            Text("Not matched")
                                .font(.caption)
                                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        }
                        if let explanation = intolerance.unassessableExplanation {
                            Text(explanation)
                                .font(.caption2)
                                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Not matched by FridgeFit")
            } footer: {
                Text("FridgeFit knows each recipe's ingredient names, not the brands or processing behind them. For coeliac disease or a nut allergy a trace matters, so it doesn't offer these as filters rather than implying a check it hasn't done.")
            }
        }
    }

    private func binding(for intolerance: FoodIntolerance) -> Binding<Bool> {
        Binding(
            get: { draft.intolerances.contains(intolerance) },
            set: { isOn in
                if isOn { draft.intolerances.insert(intolerance) } else { draft.intolerances.remove(intolerance) }
            }
        )
    }
}

#Preview {
    NavigationStack {
        OnlineRecipePreferencesView(initial: .default) { _ in }
    }
}
