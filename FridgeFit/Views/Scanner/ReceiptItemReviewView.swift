//
//  ReceiptItemReviewView.swift
//  FridgeFit
//

import SwiftUI

/// The confirmation step between reading a receipt and the pantry.
///
/// Nothing is stored until the user taps Add to Pantry, and every row can
/// be renamed, recategorised, requantified, unticked or deleted first -
/// an OCR'd abbreviation interpreted by a model is a starting point, not a
/// fact.
///
/// Two things are deliberately absent. There is no confidence badge: the
/// old fridge-scan screen showed the model's self-reported "Low / Medium
/// confidence", which was not a measurement of anything and gave the user
/// no action to take. And there are no canonical identifiers - the row for
/// `CAPS RED` reads "Red Capsicum", never `bell_pepper`.
///
/// What *is* shown is the receipt line each item came from, so a user can
/// check a row against the paper in their hand. That is real grounding,
/// unlike a number.
struct ReceiptItemReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ReceiptScannerViewModel
    /// Called once the pantry has been updated, with what actually went in.
    var onCompleted: (AddDetectedIngredientsSummary) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.drafts.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Left to Review", systemImage: "checkmark.circle")
                    } description: {
                        Text("Every item from this receipt has been added or removed.")
                    }
                } else {
                    reviewList
                }
            }
            .navigationTitle("Detected Grocery Items")
            .navigationBarTitleDisplayMode(.inline)
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
                    ReceiptItemRow(draft: draft, viewModel: viewModel)
                }
                .onDelete { viewModel.removeDrafts(at: $0) }
            } header: {
                Text("Review what we found on your receipt")
            } footer: {
                Text("Only ticked items are added. Swipe to remove anything that isn't a pantry ingredient.")
            }

            #if DEBUG
            excludedDiagnosticsSection
            #endif
        }
        .listStyle(.insetGrouped)
    }

    /// Why items are missing, for development only.
    ///
    /// The production list deliberately shows pantry candidates and
    /// nothing else - a confirmation screen cluttered with dishwashing
    /// tablets and paper towels is worse than useless. But "the scan
    /// dropped my mushrooms" is impossible to diagnose without seeing what
    /// was dropped and why, so the rejected items stay inspectable in
    /// DEBUG builds.
    #if DEBUG
    @ViewBuilder
    private var excludedDiagnosticsSection: some View {
        if !viewModel.excludedItems.isEmpty {
            Section {
                DisclosureGroup("Excluded items (\(viewModel.excludedItems.count))") {
                    ForEach(viewModel.excludedItems) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.callout)
                            Text("\(item.classification.diagnosticLabel) · \(item.sourceText)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.footnote)
            } footer: {
                Text("DEBUG only. Not shown in release builds.")
            }
        }
    }
    #endif

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
        return count == 0 ? "Add to Pantry" : "Add \(count) to Pantry"
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

/// One reviewable grocery item: tick, name, the receipt line it came from,
/// quantity and category.
private struct ReceiptItemRow: View {
    let draft: ReceiptItemDraft
    @ObservedObject var viewModel: ReceiptScannerViewModel

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
                        "Item name",
                        text: Binding(
                            get: { draft.name },
                            set: { viewModel.updateName($0, for: draft.id) }
                        )
                    )
                    .font(.body)
                    .accessibilityLabel("Item name")

                    Text(draft.sourceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel("From receipt line \(draft.sourceText)")
                }
            }

            HStack(spacing: 10) {
                TextField(
                    quantityPlaceholder,
                    text: Binding(
                        get: { draft.quantityText },
                        set: { viewModel.updateQuantityText($0, for: draft.id) }
                    )
                )
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 110)
                .accessibilityLabel(quantityAccessibilityLabel)

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

            // what it cost - goes to the Budget tab, doesn't affect the pantry at all
            HStack(spacing: 6) {
                Text("Paid $")
                    .foregroundStyle(.secondary)
                TextField(
                    "Price",
                    text: Binding(
                        get: { draft.priceText },
                        set: { viewModel.updatePriceText($0, for: draft.id) }
                    )
                )
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 90)
                .accessibilityLabel("Price paid for \(draft.name)")
                .accessibilityIdentifier("review.price.\(draft.name)")

                Text(draft.hasDetectedPrice ? "from receipt" : "optional")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            // The receipt didn't say how much, so the user has to. Said
            // plainly rather than filled in with a made-up "1 pcs".
            if !draft.hasDetectedQuantity && draft.quantity == nil {
                Text("Quantity not detected — enter one to add this item.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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

    private var quantityPlaceholder: String {
        draft.hasDetectedQuantity ? "Quantity" : "Not detected"
    }

    private var quantityAccessibilityLabel: String {
        draft.hasDetectedQuantity
            ? "Quantity for \(draft.name)"
            : "Quantity for \(draft.name), not detected on the receipt"
    }
}

#Preview {
    let viewModel = ReceiptScannerViewModel(
        textRecognizer: MockReceiptTextRecognizer(lines: SampleReceiptPreviewData.lines),
        interpreter: MockReceiptIngredientInterpreter(),
        pantryRepository: InMemoryPantryRepository()
    )
    return ReceiptItemReviewView(viewModel: viewModel, onCompleted: { _ in })
}
