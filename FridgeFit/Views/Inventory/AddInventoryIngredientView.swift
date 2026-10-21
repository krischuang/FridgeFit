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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTemplate == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.large) {
                searchField

                if !recentTemplates.isEmpty && searchText.isEmpty {
                    templateSection("Add Again", subtitle: "Recently added ingredients", templates: Array(recentTemplates.prefix(3)))
                }

                templateSection(
                    searchText.isEmpty ? "Common Ingredients" : "Results",
                    subtitle: searchText.isEmpty ? "Choose an ingredient to continue" : "Matching ingredients",
                    templates: filteredTemplates
                )

                Button {
                    selectedTemplate = customTemplate
                } label: {
                    Label("Add Custom Item", systemImage: "plus.circle")
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.medium)
            .padding(.bottom, FridgeFitTheme.Spacing.screen)
        }
        .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
    }

    private var searchField: some View {
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)

            TextField("Search common ingredients", text: $searchText)
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, FridgeFitTheme.Spacing.medium)
        .padding(.trailing, searchText.isEmpty ? FridgeFitTheme.Spacing.medium : 0)
        .frame(minHeight: 46)
        .fridgeFitCardSurface()
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

    private func templateSection(_ title: String, subtitle: String, templates: [IngredientTemplate]) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text(subtitle)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: FridgeFitTheme.Spacing.small)],
                spacing: FridgeFitTheme.Spacing.small
            ) {
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
        HStack(spacing: FridgeFitTheme.Spacing.small) {
            IngredientTemplateArtwork(template: template)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .lineLimit(2)

                Text(summary)
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 82, alignment: .leading)
        .padding(.horizontal, FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
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
