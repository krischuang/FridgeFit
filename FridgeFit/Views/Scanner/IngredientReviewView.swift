//
//  IngredientReviewView.swift
//  FridgeFit
//

import SwiftUI

/// The confirmation step between a scan and the pantry.
///
/// Nothing detected is stored until the user taps Add Selected to Pantry, and
/// every row can be renamed, recategorised, requantified, unticked or
/// deleted first - the model's answer is a starting point, not a fact.
struct IngredientReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: IngredientScannerViewModel
    /// Called once the pantry has been updated, with what actually went in.
    var onCompleted: (AddDetectedIngredientsSummary) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.drafts.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Left to Review", systemImage: "checkmark.circle")
                    } description: {
                        Text("Every detected ingredient has been added or removed.")
                    }
                } else {
                    reviewList
                }
            }
            .navigationTitle("Detected Ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !viewModel.drafts.isEmpty {
                    addToPantryBar
                }
            }
        }
    }

    @ViewBuilder
    private var reviewList: some View {
        List {
            Section {
                ForEach(viewModel.drafts) { draft in
                    DetectedIngredientRow(draft: draft, viewModel: viewModel)
                }
                .onDelete { viewModel.removeDrafts(at: $0) }
            } header: {
                Text("Tap to correct anything Apple Intelligence got wrong")
            } footer: {
                Text("Only ticked ingredients are added. Swipe to remove a detection that isn't in your fridge.")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var addToPantryBar: some View {
        VStack(spacing: 8) {
            if let summary = viewModel.addSummary, !summary.isCompleteSuccess {
                InlineErrorBanner(message: summary.userMessage)
            }

            Button {
                addSelected()
            } label: {
                if viewModel.isAddingToPantry {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(addButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canAddToPantry)
        }
        .padding()
        .background(.bar)
    }

    private var addButtonTitle: String {
        let count = viewModel.selectedDrafts.count
        return count == 0 ? "Add Selected to Pantry" : "Add \(count) to Pantry"
    }

    private func addSelected() {
        Task {
            await viewModel.addSelectedToPantry()
            // Dismiss only once the pantry took everything; if something was
            // rejected the sheet stays open showing why.
            if let summary = viewModel.addSummary, summary.isCompleteSuccess {
                onCompleted(summary)
            }
        }
    }
}

/// One reviewable detection: tick, name, category, quantity and the
/// confidence the model reported.
private struct DetectedIngredientRow: View {
    let draft: DetectedIngredientDraft
    @ObservedObject var viewModel: IngredientScannerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    viewModel.toggleSelection(for: draft.id)
                } label: {
                    Image(systemName: draft.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(draft.isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(draft.isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Double tap to \(draft.isSelected ? "exclude" : "include") \(draft.name)")

                IconBadge(systemImage: draft.category.symbolName, tint: draft.category.tint)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(
                        "Ingredient name",
                        text: Binding(
                            get: { draft.name },
                            set: { viewModel.updateName($0, for: draft.id) }
                        )
                    )
                    .font(.body)
                    .accessibilityLabel("Ingredient name")

                    ConfidenceBadge(confidence: draft.confidence)
                }
            }

            HStack(spacing: 10) {
                TextField(
                    "Quantity",
                    text: Binding(
                        get: { draft.quantityText },
                        set: { viewModel.updateQuantityText($0, for: draft.id) }
                    )
                )
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 90)
                .accessibilityLabel("Quantity for \(draft.name)")

                Picker(
                    "Unit",
                    selection: Binding(
                        get: { draft.unit },
                        set: { viewModel.updateUnit($0, for: draft.id) }
                    )
                ) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .labelsHidden()

                Picker(
                    "Category",
                    selection: Binding(
                        get: { draft.category },
                        set: { viewModel.updateCategory($0, for: draft.id) }
                    )
                ) {
                    ForEach(IngredientCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .labelsHidden()
            }
            .font(.callout)

            if draft.isAlreadyInPantry {
                InlineInfoBanner(
                    message: "Already in your pantry. Adding it again will be rejected - update its quantity in Pantry instead.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let viewModel = IngredientScannerViewModel(
        recognitionService: MockIngredientRecognitionService(result: .success(.sampleFridge)),
        pantryRepository: InMemoryPantryRepository()
    )
    return IngredientReviewView(viewModel: viewModel, onCompleted: { _ in })
}
