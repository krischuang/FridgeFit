//
//  PantryView.swift
//  FridgeFit
//

import SwiftUI

/// Lets the signed-in user see what's in their pantry, add new items,
/// update quantities, and remove ones they've used up.
struct PantryView: View {
    @ObservedObject var viewModel: PantryViewModel
    @State private var isPresentingAddItem = false
    @State private var editingItem: PantryItem?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Loading Pantry…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView {
                    Label("Your Pantry Is Empty", systemImage: "cabinet")
                } description: {
                    Text("Add ingredients you have on hand to start tracking your pantry.")
                } actions: {
                    Button {
                        isPresentingAddItem = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
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
        }
        .task { await viewModel.loadItems() }
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
                get: { viewModel.errorMessage != nil && !isPresentingAddItem && editingItem == nil },
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
    NavigationStack {
        PantryView(viewModel: PantryViewModel())
    }
}
