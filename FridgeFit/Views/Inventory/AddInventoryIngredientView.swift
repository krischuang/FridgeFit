//
//  AddInventoryIngredientView.swift
//  FridgeFit
//

import SwiftUI

/// Adding food to the kitchen: pick a common item, or describe one.
///
/// Two steps rather than one form, because most additions are the same ten
/// things and a tap beats filling in five fields. Nothing is stored until
/// the editor is confirmed - the templates only pre-fill it.
struct AddInventoryIngredientView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var inventory: InventoryStore

    @State private var searchText = ""
    @State private var selectedTemplate: IngredientTemplate?

    private var filteredTemplates: [IngredientTemplate] {
        InventoryTemplateCatalog.matching(searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedTemplate {
                    IngredientEditorView(
                        mode: .add(selectedTemplate),
                        inventory: inventory,
                        onDone: { dismiss() }
                    )
                } else {
                    templateList
                }
            }
            .navigationTitle("Add Ingredient")
            .kitchenInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                if selectedTemplate != nil {
                    ToolbarItem {
                        Button {
                            selectedTemplate = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }
            }
        }
    }

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchField

                if !recentTemplates.isEmpty && searchText.isEmpty {
                    templateSection("Add Again", templates: Array(recentTemplates.prefix(3)))
                }

                templateSection(searchText.isEmpty ? "Common" : "Results", templates: filteredTemplates)

                Button {
                    selectedTemplate = customTemplate
                } label: {
                    HStack {
                        Text("Can't find it? Add Custom Item")
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(KitchenTheme.forest)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(KitchenTheme.surface)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(KitchenTheme.background.ignoresSafeArea())
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("What did you get?", text: $searchText)
                .kitchenIngredientTextInput()
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KitchenTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    /// Templates for food the user has added before, most recent first.
    ///
    /// Read from the activity log rather than from the pantry, because what
    /// is worth re-offering is what they *buy* - something currently in the
    /// fridge doesn't need adding again.
    private var recentTemplates: [IngredientTemplate] {
        let recentNames = inventory.events
            .filter { $0.kind == .added }
            .sorted { $0.date > $1.date }
            .map(\.itemName)

        let templatesByName = Dictionary(
            InventoryTemplateCatalog.templates.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        return recentNames
            .compactMap { templatesByName[$0.lowercased()] }
            .filter { seen.insert($0.id).inserted }
    }

    private func templateSection(_ title: String, templates: [IngredientTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(templates) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        TemplateTile(template: template, summary: defaultSummary(for: template))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func defaultSummary(for template: IngredientTemplate) -> String {
        "\(template.defaultQuantity.displayText) · \(template.storageLocation.title)"
    }

    /// A blank template seeded with whatever the user typed in the search
    /// box, so "Can't find it?" doesn't throw their typing away.
    private var customTemplate: IngredientTemplate {
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return IngredientTemplate(
            name: typed.isEmpty ? "New Item" : typed,
            category: .other,
            storageLocation: .fridge,
            defaultQuantity: .count(1),
            lowStockThreshold: 1
        )
    }
}

private struct TemplateTile: View {
    let template: IngredientTemplate
    let summary: String

    var body: some View {
        VStack(spacing: 7) {
            IngredientTemplateArtwork(template: template)

            Text(template.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 102)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KitchenTheme.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(template.name), \(summary)")
    }
}

#Preview {
    AddInventoryIngredientView(inventory: InventoryStore(
        pantryRepository: InMemoryPantryRepository(),
        eventRepository: InMemoryInventoryEventRepository()
    ))
}
