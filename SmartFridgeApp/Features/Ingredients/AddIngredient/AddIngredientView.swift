import SwiftUI

struct AddIngredientView: View {
    @Environment(\.dismiss) private var dismiss

    let inventory: InventoryService

    @State private var searchText = ""
    @State private var selectedTemplate: IngredientTemplate?

    private var filteredTemplates: [IngredientTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SmartFridgeSeedData.templates }
        return SmartFridgeSeedData.templates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.category.displayName.localizedCaseInsensitiveContains(query)
        }
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
            .smartInlineNavigationTitle()
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
                            self.selectedTemplate = nil
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
                        Text("Can’t find it? Add Custom Item")
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SmartFridgeTheme.forest)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SmartFridgeTheme.surface)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(SmartFridgeTheme.background.ignoresSafeArea())
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("What did you get?", text: $searchText)
                .smartIngredientTextInput()
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SmartFridgeTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var recentTemplates: [IngredientTemplate] {
        let recentNames = inventory.events
            .filter { $0.kind == .added }
            .sorted { $0.date > $1.date }
            .map(\.ingredientName)

        let templatesByName = Dictionary(uniqueKeysWithValues: SmartFridgeSeedData.templates.map { ($0.name, $0) })
        return recentNames.compactMap { templatesByName[$0] }.removingDuplicates()
    }

    private func templateButton(_ template: IngredientTemplate) -> some View {
        Button {
            selectedTemplate = template
        } label: {
            TemplateTile(template: template, summary: defaultSummary(for: template))
        }
        .buttonStyle(.plain)
    }

    private func templateSection(_ title: String, templates: [IngredientTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                ForEach(templates) { template in
                    templateButton(template)
                }
            }
        }
    }

    private func defaultSummary(for template: IngredientTemplate) -> String {
        "\(template.defaultQuantity.displayText) · \(template.storageLocation.title)"
    }

    private var customTemplate: IngredientTemplate {
        IngredientTemplate(
            name: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Item" : searchText,
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
                .fill(SmartFridgeTheme.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("\(template.name), \(summary)")
    }
}

private extension Array where Element == IngredientTemplate {
    func removingDuplicates() -> [IngredientTemplate] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
