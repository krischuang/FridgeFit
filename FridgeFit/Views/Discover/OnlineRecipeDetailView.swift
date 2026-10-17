//
//  OnlineRecipeDetailView.swift
//  FridgeFit
//

import SwiftUI

/// Full view of an online recipe in the FridgeFit "Recipe Detail" design:
/// hero photo, readiness against the pantry, FridgeFix substitution help,
/// an ingredient breakdown (have / still need), allergen screening and the
/// method. Read-only - it never edits the pantry or the bundled recipes.
///
/// Every element is backed by real data; anything the provider doesn't
/// supply is left out rather than invented (no calorie pill without
/// nutrition data, no difficulty label, no shopping-list action until the
/// app has a shopping list).
///
/// ## Allergen wording
///
/// An empty finding is reported as what was done - a keyword screen of the
/// ingredient list - never as "no allergens". See `RecipeIntoleranceAnalysis`.
struct OnlineRecipeDetailView: View {
    let match: OnlineRecipeMatch
    let intolerances: Set<FoodIntolerance>
    @ObservedObject var recipeViewModel: RecipeViewModel
    /// Near-expiry / expired pantry items this recipe would use.
    var expiryUse: OnlineRecipeExpiryUse = .none
    /// Hides this recipe from future searches. `nil` hides the action.
    var onHide: (() -> Void)? = nil
    /// Pantry the search ran against, for location and freshness per row.
    var pantrySnapshot: [PantryItem] = []
    /// Powers the FridgeFix card. `nil` hides the card.
    var substitutionViewModel: SubstitutionViewModel? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var fridgeFixTarget: OnlineRecipeFridgeFixTarget?
    @State private var hasPreparedFridgeFix = false
    @State private var isCooking = false

    private typealias Token = FridgeFitTheme.ColorToken
    private typealias Space = FridgeFitTheme.Spacing

    private var recipe: OnlineRecipe { match.recipe }
    private var content: OnlineRecipeDetailContent {
        OnlineRecipeDetailContent.build(match: match, pantry: pantrySnapshot)
    }

    var body: some View {
        let content = self.content
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xLarge) {
                actionRow
                hero
                titleBlock
                readinessCard(content)
                saveStatus
                if let substitutionViewModel, let fridgeFixTarget {
                    FridgeFixCard(target: fridgeFixTarget, substitutionViewModel: substitutionViewModel)
                }
                breakdown(content)
                allergenCard
                methodCard
                sourceFooter
            }
            .padding(.horizontal, Space.large)
            .padding(.bottom, Space.screen)
        }
        .background(Token.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar {
            if let onHide {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            onHide()
                            dismiss()
                        } label: {
                            Label("Don't Show This Recipe Again", systemImage: "eye.slash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationTitle("Recipe Detail")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isCooking) {
            OnlineRecipeCookingView(title: recipe.title, steps: recipe.steps)
        }
        .task {
            guard !hasPreparedFridgeFix else { return }
            hasPreparedFridgeFix = true
            fridgeFixTarget = OnlineRecipeFridgeFixTarget.make(
                for: match,
                readyCount: content.readyCount,
                totalCount: content.totalCount
            )
        }
        .onDisappear { recipeViewModel.savedRecipeErrorMessage = nil }
    }

    // MARK: - Header

    private var actionRow: some View {
        HStack(spacing: Space.small) {
            Spacer()
            if recipeViewModel.canSaveRecipes {
                let isSaved = recipeViewModel.isSaved(onlineRecipeID: recipe.id)
                Button {
                    Task { await recipeViewModel.saveOnlineRecipe(recipe) }
                } label: {
                    if recipeViewModel.isSaving(onlineRecipeID: recipe.id) {
                        ProgressView()
                    } else {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    }
                }
                .buttonStyle(FridgeFitIconButtonStyle())
                .disabled(isSaved || recipeViewModel.isSaving(onlineRecipeID: recipe.id))
                .accessibilityLabel(isSaved ? "Saved to Recipes" : "Save to Recipes")
            }
            if let source = recipe.sourceURL {
                ShareLink(item: source, subject: Text(recipe.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(FridgeFitIconButtonStyle())
                .accessibilityLabel("Share recipe")
            }
        }
        .padding(.top, Space.small)
    }

    private var hero: some View {
        OnlineRecipeImage(url: recipe.imageURL)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous))
            .overlay(alignment: .topLeading) {
                if expiryUse.usesUrgentIngredient && !expiryUse.usesExpiredIngredient {
                    Label("Zero Waste Pick", systemImage: "leaf.fill")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(Token.primary)
                        .padding(.horizontal, Space.medium)
                        .padding(.vertical, 6)
                        .background(Token.card, in: Capsule())
                        .padding(Space.medium)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let score = recipe.healthScore {
                    Text("Health \(Int(score))")
                        .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(Token.textPrimary)
                        .padding(.horizontal, Space.medium)
                        .padding(.vertical, 6)
                        .background(Token.card, in: Capsule())
                        .padding(Space.medium)
                }
            }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Space.medium) {
            Text(recipe.title)
                .font(FridgeFitTheme.Typography.hero)
                .foregroundStyle(Token.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.small) {
                    if let minutes = recipe.readyInMinutes {
                        MetaChip(text: "\(minutes) min", systemImage: "clock")
                    }
                    if let servings = recipe.servings {
                        MetaChip(text: "\(servings) servings", systemImage: "person.2")
                    }
                    if !recipe.steps.isEmpty {
                        MetaChip(text: "\(recipe.steps.count) steps", systemImage: "list.number")
                    }
                    if match.isFromCache {
                        MetaChip(text: "Saved earlier", systemImage: "icloud.slash")
                    }
                }
            }
        }
    }

    // MARK: - Readiness

    private func readinessCard(_ content: OnlineRecipeDetailContent) -> some View {
        VStack(alignment: .leading, spacing: Space.medium) {
            HStack(spacing: Space.medium) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Token.card)
                    .frame(width: 28, height: 28)
                    .background(Token.primary, in: Circle())
                Text("\(content.readyCount) of \(content.totalCount) ingredients ready")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(Token.primary)
                Spacer(minLength: Space.small)
                Text("\(content.matchPercent)% Match")
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Token.textPrimary)
                    .padding(.horizontal, Space.small)
                    .padding(.vertical, Space.xSmall)
                    .background(Token.card, in: Capsule())
            }

            if expiryUse.usesExpiredIngredient {
                calloutRow(
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Token.danger,
                    text: Text("**Check first:** uses your \(expiryUse.expired.joined(separator: ", ")), which has expired.")
                )
            } else if expiryUse.usesUrgentIngredient {
                calloutRow(
                    systemImage: "bolt.fill",
                    tint: Token.warningText,
                    text: Text("**Smart choice:** Uses your \(OnlineRecipeExpiryPresentation.list(expiryUse.urgent)).")
                )
            }
        }
        .padding(Space.large)
        .background(Token.successBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func calloutRow(systemImage: String, tint: Color, text: Text) -> some View {
        HStack(alignment: .top, spacing: Space.small) {
            Image(systemName: systemImage).foregroundStyle(tint)
            text
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(Token.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.medium)
        .background(Token.card, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
    }

    /// Save errors, or why saving is switched off. Never a button that
    /// cannot work.
    @ViewBuilder
    private var saveStatus: some View {
        if let message = recipeViewModel.savedRecipeErrorMessage {
            Label(message, systemImage: "exclamationmark.circle")
                .font(FridgeFitTheme.Typography.metadata)
                .foregroundStyle(Token.danger)
        } else if !recipeViewModel.canSaveRecipes, let explanation = recipeViewModel.savedRecipeUnavailableExplanation {
            VStack(alignment: .leading, spacing: Space.xSmall) {
                Label("Saving isn't available yet", systemImage: "bookmark.slash")
                    .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                    .foregroundStyle(Token.textPrimary)
                Text(explanation)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(Token.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.medium)
            .fridgeFitCardSurface()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Ingredients

    private func breakdown(_ content: OnlineRecipeDetailContent) -> some View {
        VStack(alignment: .leading, spacing: Space.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredients Breakdown")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(Token.textPrimary)
                Spacer()
                Text("\(content.totalCount) items total")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(Token.textSecondary)
            }

            if !content.have.isEmpty {
                groupHeader(title: "Already have in stock", dot: Token.primary) {
                    FridgeFitStatusBadge(title: "\(content.readyCount) ready", tone: .success)
                }
                ForEach(content.have) { line in IngredientRow(line: line) }
            }

            if !content.missing.isEmpty {
                groupHeader(title: "Still need to source", dot: Token.accent) {
                    FridgeFitStatusBadge(title: "\(content.missing.count) missing", tone: .danger)
                }
                ForEach(content.missing) { line in IngredientRow(line: line) }
            }

            Text("Matched against your pantry by name, not quantity. Save the recipe to have FridgeFit check quantities.")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(Token.textSecondary)
        }
    }

    private func groupHeader(title: String, dot: Color, @ViewBuilder badge: () -> some View) -> some View {
        HStack(spacing: Space.small) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(title)
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(Token.textPrimary)
            Spacer()
            badge()
        }
        .padding(.top, Space.xSmall)
    }

    // MARK: - Allergens, method, source

    private var allergenCard: some View {
        VStack(alignment: .leading, spacing: Space.small) {
            Text("Allergen screening")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(Token.textPrimary)
            Group {
                if let contained = recipe.containsIntolerances {
                    if contained.isEmpty {
                        Label(
                            "None of the allergens FridgeFit screens for appear in this recipe's ingredient list.",
                            systemImage: "magnifyingglass"
                        )
                        .foregroundStyle(Token.textSecondary)
                    } else {
                        Label(
                            "May contain: " + contained.map(\.displayName).sorted().joined(separator: ", "),
                            systemImage: "exclamationmark.shield"
                        )
                        .foregroundStyle(contained.isDisjoint(with: intolerances) ? Token.textSecondary : Token.danger)
                    }
                } else {
                    Label("FridgeFit couldn't screen this recipe's ingredients.", systemImage: "questionmark.diamond")
                        .foregroundStyle(Token.warningText)
                }
            }
            .font(FridgeFitTheme.Typography.supporting)
            Text("A keyword screen of the ingredient names the recipe service supplied, not a safety check. If you have an allergy, read the packaging of everything you cook with.")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(Token.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.large)
        .fridgeFitCardSurface()
    }

    private var methodCard: some View {
        VStack(alignment: .leading, spacing: Space.medium) {
            Text("Method")
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(Token.textPrimary)
            if recipe.steps.isEmpty {
                Text("No step-by-step method was provided for this recipe.")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(Token.textSecondary)
                if let source = recipe.sourceURL {
                    Link("Open the original recipe", destination: source)
                        .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                }
            } else {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: Space.medium) {
                        Text("\(index + 1)")
                            .font(FridgeFitTheme.Typography.caption.weight(.bold))
                            .foregroundStyle(Token.primary)
                            .frame(width: 24, height: 24)
                            .background(Token.successBackground, in: Circle())
                        Text(step)
                            .font(FridgeFitTheme.Typography.supporting)
                            .foregroundStyle(Token.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.large)
        .fridgeFitCardSurface()
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: Space.xSmall) {
            if let source = recipe.sourceURL {
                Link(destination: source) {
                    Label("Source: \(recipe.sourceName ?? source.host() ?? "original recipe")", systemImage: "safari")
                }
                .font(FridgeFitTheme.Typography.metadata)
            }
            Link(destination: URL(string: "https://spoonacular.com/food-api")!) {
                Text("Recipe data powered by Spoonacular")
            }
            .font(FridgeFitTheme.Typography.metadata)
            Text("Spoonacular recipe ID \(String(recipe.id))")
                .font(.caption2)
                .foregroundStyle(Token.textSecondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if let firstStep = recipe.steps.first {
            Button {
                isCooking = true
            } label: {
                Label("Step 1: \(OnlineRecipeCookingView.shortLabel(for: firstStep))", systemImage: "play.circle")
                    .lineLimit(1)
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())
            .padding(.horizontal, Space.large)
            .padding(.vertical, Space.small)
            .background(Token.canvas.opacity(0.96))
        }
    }
}

// MARK: - Pieces

private struct MetaChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .padding(.horizontal, FridgeFitTheme.Spacing.medium)
            .padding(.vertical, 6)
            .background(FridgeFitTheme.ColorToken.disabledSurface, in: Capsule())
    }
}

private struct IngredientRow: View {
    let line: OnlineRecipeDetailContent.Line

    private typealias Token = FridgeFitTheme.ColorToken

    private var isMissing: Bool { line.status == .missing }

    var body: some View {
        HStack(spacing: FridgeFitTheme.Spacing.medium) {
            Image(systemName: isMissing ? "exclamationmark" : "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(isMissing ? Token.danger : Token.primary)
                .frame(width: 26, height: 26)
                .background(isMissing ? Token.accent.opacity(0.16) : Token.successBackground, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(line.quantity.isEmpty ? line.name : "\(line.quantity) \(line.name)")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(Token.textPrimary)
                if let location = line.location {
                    Label("From \(location.title)", systemImage: "refrigerator")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(Token.textSecondary)
                } else if line.quantityIsUncertain {
                    Text("Amount unclear - check the original recipe")
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(Token.warningText)
                }
            }

            Spacer(minLength: FridgeFitTheme.Spacing.small)

            FridgeFitStatusBadge(
                title: LocalizedStringKey(line.status.title),
                systemImage: badgeIcon,
                tone: tone
            )
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var tone: FridgeFitStatusTone {
        switch line.status {
        case .missing, .expired: return .danger
        case .expiresToday, .expiresTomorrow: return .warning
        case .daysLeft(let days): return days <= 3 ? .warning : .neutral
        case .fresh: return .success
        case .inStock: return .neutral
        }
    }

    private var badgeIcon: String? {
        switch line.status {
        case .expiresToday, .expiresTomorrow, .expired: return "clock"
        default: return nil
        }
    }
}

/// The FridgeFix substitution card for the first missing essential
/// ingredient. Only asks the assistant when the user taps - suggestions go
/// through the existing pipeline, which validates them against the pantry.
private struct FridgeFixCard: View {
    let target: OnlineRecipeFridgeFixTarget
    @ObservedObject var substitutionViewModel: SubstitutionViewModel

    private typealias Token = FridgeFitTheme.ColorToken
    private var ingredientName: String { target.ingredient.ingredient.name }

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack {
                Label("FridgeFix Suggestion", systemImage: "wand.and.sparkles")
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(Token.textPrimary)
                Spacer()
                FridgeFitStatusBadge(title: "AI ASSISTANT", tone: .success)
            }

            content

            Label("Always check ingredients against personal dietary & allergy needs.", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(Token.textSecondary)
        }
        .padding(FridgeFitTheme.Spacing.large)
        .fridgeFitCardSurface()
    }

    @ViewBuilder
    private var content: some View {
        if let suggestion = substitutionViewModel.suggestions(for: target.ingredient)?.first {
            suggestionBox {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text("Missing **\(ingredientName)**? Try **\(suggestionTitle(suggestion))** instead.")
                    Text(suggestion.explanation)
                    if let limitations = suggestion.limitations {
                        Text(limitations).foregroundStyle(Token.textSecondary)
                    }
                }
            }
            FridgeFitStatusBadge(
                title: LocalizedStringKey(suggestion.validationStatus.displayName),
                systemImage: suggestion.validationStatus.symbolName,
                tone: suggestion.validationStatus == .availableInPantry ? .success : .neutral
            )
        } else if substitutionViewModel.isLoading(for: target.ingredient) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                ProgressView()
                Text("Asking FridgeFix…")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(Token.textSecondary)
            }
        } else {
            suggestionBox {
                Text("Missing **\(ingredientName)**? FridgeFix can suggest a swap from what you have.")
            }
            if let error = substitutionViewModel.errorMessage(for: target.ingredient) {
                Text(error)
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(Token.danger)
            }
            Button {
                Task {
                    await substitutionViewModel.findSubstitutes(
                        for: target.ingredient,
                        recipe: target.recipe,
                        feasibility: target.feasibility
                    )
                }
            } label: {
                Label("Ask FridgeFix for a swap", systemImage: "sparkles")
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())
        }
    }

    private func suggestionTitle(_ suggestion: SubstitutionSuggestion) -> String {
        if let amount = suggestion.formattedSuggestedQuantity {
            return "\(amount) \(suggestion.ingredientName)"
        }
        return suggestion.ingredientName
    }

    private func suggestionBox(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "lightbulb")
                .foregroundStyle(Token.accent)
            content()
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(Token.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .background(Token.canvas, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
    }
}
