//
//  OnlineRecipePreferencesView.swift
//  FridgeFit
//

import SwiftUI

/// Filters for the Discover tab: diet, intolerances, and a time limit.
struct OnlineRecipePreferencesView: View {
    let onSave: (OnlineRecipePreferences) -> Void
    @State private var draft: OnlineRecipePreferences
    @Environment(\.dismiss) private var dismiss

    private static let timeOptions: [Int?] = [nil, 15, 30, 45, 60, 90]

    init(initial: OnlineRecipePreferences, onSave: @escaping (OnlineRecipePreferences) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section("Diet") {
                Picker("Diet", selection: $draft.diet) {
                    ForEach(DietPreference.allCases) { diet in
                        Text(diet.displayName).tag(diet)
                    }
                }
            }

            Section {
                ForEach(FoodIntolerance.allCases) { intolerance in
                    Toggle(intolerance.displayName, isOn: binding(for: intolerance))
                }
            } header: {
                Text("Avoid")
            } footer: {
                Text("Recipes that contain these - or whose ingredients can't be verified - are hidden.")
            }

            Section("Time") {
                Picker("Ready within", selection: $draft.maxReadyTimeMinutes) {
                    ForEach(Self.timeOptions, id: \.self) { option in
                        Text(option.map { "\($0) min" } ?? "Any time").tag(option)
                    }
                }
            }
        }
        .navigationTitle("Filters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
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
