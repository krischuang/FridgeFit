//
//  PantryView.swift
//  FridgeFit
//

import SwiftUI

/// Lets the signed-in user see what's in their pantry, add new items,
/// update quantities, and remove ones they've used up.
struct PantryView: View {
    @ObservedObject var viewModel: PantryViewModel
    @ObservedObject var scannerViewModel: ReceiptScannerViewModel
    @State private var isPresentingAddItem = false
    @State private var isPresentingScanner = false
    @State private var editingItem: PantryItem?
    /// What the last receipt scan added, shown once the scanner closes.
    @State private var scanSummaryMessage: String?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Loading Pantry…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView {
                    Label("Your Pantry Is Empty", systemImage: "cabinet")
                } description: {
                    Text("Scan a grocery receipt, or add ingredients by hand, to start tracking your pantry.")
                } actions: {
                    Button {
                        isPresentingScanner = true
                    } label: {
                        Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isPresentingAddItem = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                List {
                    ForEach(viewModel.items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(systemImage: item.ingredient.category.symbolName, tint: item.ingredient.category.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(item.ingredient.category.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.formattedQuantity)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.name), \(item.ingredient.category.rawValue), \(item.formattedQuantity)")
                        .accessibilityHint("Double tap to update quantity")
                    }
                    .onDelete(perform: removeItems)
                }
                .listStyle(.insetGrouped)
                .refreshable { await viewModel.loadItems() }
            }
        }
        .navigationTitle("Pantry")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddItem = true
                } label: {
                    Label("Add Ingredient", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isPresentingScanner = true
                } label: {
                    Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                }
            }
        }
        .task { await viewModel.loadItems() }
        .sheet(isPresented: $isPresentingScanner, onDismiss: { scannerViewModel.reset() }) {
            ReceiptScannerView(viewModel: scannerViewModel) { summary in
                isPresentingScanner = false
                scanSummaryMessage = summary.userMessage
                Task { await viewModel.loadItems() }
            }
        }
        .alert(
            "Receipt Scan",
            isPresented: Binding(
                get: { scanSummaryMessage != nil },
                set: { isPresented in
                    if !isPresented { scanSummaryMessage = nil }
                }
            )
        ) {
            Button("OK") { scanSummaryMessage = nil }
        } message: {
            Text(scanSummaryMessage ?? "")
        }
        .sheet(isPresented: $isPresentingAddItem) {
            AddPantryItemView(viewModel: viewModel) { duplicateItem in
                isPresentingAddItem = false
                editingItem = duplicateItem
            }
        }
        .sheet(item: $editingItem) { item in
            UpdatePantryItemView(viewModel: viewModel, item: item)
        }
        .alert(
            "Couldn't Remove Item",
            isPresented: Binding(
                get: { viewModel.removalErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.removalErrorMessage = nil }
                }
            )
        ) {
            Button("OK") {
                viewModel.removalErrorMessage = nil
                Task { await viewModel.loadItems() }
            }
        } message: {
            Text(viewModel.removalErrorMessage ?? "")
        }
        .alert(
            "Couldn't Load Pantry",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil && !isPresentingAddItem && !isPresentingScanner && editingItem == nil },
                set: { isPresented in
                    if !isPresented { viewModel.errorMessage = nil }
                }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func removeItems(at offsets: IndexSet) {
        for index in offsets {
            Task { await viewModel.removeItem(viewModel.items[index]) }
        }
    }
}

#Preview {
    let pantryRepository = InMemoryPantryRepository()
    return NavigationStack {
        PantryView(
            viewModel: PantryViewModel(pantryRepository: pantryRepository),
            scannerViewModel: ReceiptScannerViewModel(
                textRecognizer: MockReceiptTextRecognizer(lines: SampleReceiptPreviewData.lines),
                interpreter: MockReceiptIngredientInterpreter(),
                pantryRepository: pantryRepository
            )
        )
    }
}
