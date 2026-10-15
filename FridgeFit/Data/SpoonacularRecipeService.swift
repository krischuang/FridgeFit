//
//  SpoonacularRecipeService.swift
//  FridgeFit
//

import Foundation

/// Production `OnlineRecipeService` backed by Spoonacular's `complexSearch`
/// endpoint. See https://spoonacular.com/food-api/docs
///
/// ## When this is built
///
/// Only when `OnlineRecipeFeature.provider == .enabled` *and* a valid API
/// key is configured. While the feature is gated off, nothing constructs
/// this type, so no instance capable of issuing a request exists - see
/// `OnlineRecipeFeature`.
///
/// Ported from the `feature/spoonacular-online-recipes` branch, adapted to
/// FridgeFit's domain types, error style and allergen policy.
nonisolated final class SpoonacularRecipeService: OnlineRecipeService {
    static let endpoint = URL(string: "https://api.spoonacular.com/recipes/complexSearch")!
    private static let timeoutInterval: TimeInterval = 20

    private let configuration: SpoonacularConfiguration
    private let urlSession: URLSession

    init(configuration: SpoonacularConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func searchRecipes(matching criteria: OnlineRecipeSearchCriteria) async throws -> [OnlineRecipeMatch] {
        guard let url = Self.requestURL(for: criteria, apiKey: configuration.apiKey) else {
            throw OnlineRecipeSearchError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeoutInterval

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OnlineRecipeSearchError.timeout
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OnlineRecipeSearchError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw OnlineRecipeSearchError.network
        }
        switch http.statusCode {
        case 200 ..< 300: break
        case 401: throw OnlineRecipeSearchError.unauthorized
        case 402, 429: throw OnlineRecipeSearchError.quotaExceeded
        default: throw OnlineRecipeSearchError.providerUnavailable
        }

        return try Self.parseMatches(from: data)
    }

    /// Builds the `complexSearch` URL. Split out so the query can be tested
    /// without the network.
    ///
    /// Note the `intolerances` parameter is still sent: provider-side
    /// filtering is a cheap first pass that reduces how much comes back. It
    /// is never treated as the answer - `FindOnlineRecipesFromPantryUseCase`
    /// re-checks every result locally and fails closed.
    static func requestURL(for criteria: OnlineRecipeSearchCriteria, apiKey: String) -> URL? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(max(1, min(criteria.resultLimit, 100)))),
            URLQueryItem(name: "sort", value: "min-missing-ingredients"),
            URLQueryItem(name: "addRecipeInformation", value: "true"),
            // Without this, complexSearch omits analyzedInstructions even with
            // addRecipeInformation, and the detail screen has no method.
            URLQueryItem(name: "addRecipeInstructions", value: "true"),
            URLQueryItem(name: "fillIngredients", value: "true"),
        ]
        let names = criteria.pantryIngredientNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !names.isEmpty {
            items.append(URLQueryItem(name: "includeIngredients", value: names.joined(separator: ",")))
        }
        let preferences = criteria.preferences
        if !preferences.intolerances.isEmpty {
            let value = preferences.intolerances.map(\.apiValue).sorted().joined(separator: ",")
            items.append(URLQueryItem(name: "intolerances", value: value))
        }
        if let diet = preferences.diet.apiValue {
            items.append(URLQueryItem(name: "diet", value: diet))
        }
        if let maxTime = preferences.maxReadyTimeMinutes {
            items.append(URLQueryItem(name: "maxReadyTime", value: String(maxTime)))
        }
        components?.queryItems = items
        return components?.url
    }

    /// The wire-decoding step, split out so it can be exercised against
    /// fixture JSON without going through the network.
    static func parseMatches(from data: Data) throws -> [OnlineRecipeMatch] {
        guard let decoded = try? JSONDecoder().decode(SpoonacularSearchResponse.self, from: data) else {
            throw OnlineRecipeSearchError.malformedResponse
        }
        return decoded.results.map(\.asMatch)
    }

    /// Spoonacular summaries are HTML; the app shows plain text.
    static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Used when the online feature is gated off, or no Spoonacular key is
/// configured, so Discover shows a clear "not set up" message instead of
/// crashing or sending an empty credential.
///
/// This is the type the app runs with today. It touches no network.
nonisolated final class UnconfiguredOnlineRecipeService: OnlineRecipeService {
    func searchRecipes(matching criteria: OnlineRecipeSearchCriteria) async throws -> [OnlineRecipeMatch] {
        throw OnlineRecipeSearchError.notConfigured
    }
}

// MARK: - Wire types

private struct SpoonacularSearchResponse: Decodable {
    let results: [SpoonacularRecipe]
}

private struct SpoonacularIngredient: Decodable {
    let id: Int?
    let name: String?
    let nameClean: String?
    let amount: Double?
    let unit: String?

    /// `nameClean` is the provider's own canonical name and is preferred;
    /// `name` is the free-text recipe line.
    var resolvedName: String {
        let candidate = nameClean ?? name ?? ""
        let normalized = OnlineIngredientName.normalized(candidate)
        return normalized.isEmpty ? "ingredient" : normalized
    }

    var asIngredient: OnlineRecipeIngredient {
        let rawUnit = unit ?? ""
        let mapped = SpoonacularUnitMapper.map(rawUnit)
        return OnlineRecipeIngredient(
            providerID: id,
            name: resolvedName,
            amount: amount ?? 0,
            unit: mapped.unit,
            originalUnit: rawUnit,
            quantityIsUncertain: mapped.quantityIsUncertain
        )
    }
}

private struct SpoonacularRecipe: Decodable {
    let id: Int
    let title: String
    let image: String?
    let readyInMinutes: Int?
    let servings: Int?
    let sourceUrl: String?
    let sourceName: String?
    let summary: String?
    let healthScore: Double?
    let diets: [String]?
    let extendedIngredients: [SpoonacularIngredient]?
    let analyzedInstructions: [AnalyzedInstruction]?
    let usedIngredients: [SpoonacularIngredient]?
    let missedIngredients: [SpoonacularIngredient]?

    // Spoonacular also returns `glutenFree`, `dairyFree`, `vegan` and
    // `vegetarian` booleans. They are deliberately not decoded: the source
    // branch used them to clear allergens that keyword analysis had found,
    // which let a provider claim override FridgeFit's own uncertainty - and
    // for gluten it asserted a `.productProvenance` claim the app cannot
    // make. Leaving them undecoded means no future edit can quietly
    // reintroduce that path. `diets` is still read, for display only.

    struct AnalyzedInstruction: Decodable {
        let steps: [Step]

        struct Step: Decodable {
            let number: Int
            let step: String
        }
    }

    var asRecipe: OnlineRecipe {
        let ingredientLines = extendedIngredients ?? []
        let steps = (analyzedInstructions ?? [])
            .flatMap(\.steps)
            .map { $0.step.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let intolerances = RecipeIntoleranceAnalysis.intolerances(
            inIngredientNames: ingredientLines.map(\.resolvedName)
        )

        return OnlineRecipe(
            id: id,
            title: title,
            imageURL: image.flatMap(URL.init(string:)),
            readyInMinutes: readyInMinutes,
            servings: servings,
            summary: summary.map(SpoonacularRecipeService.plainText(fromHTML:)),
            sourceName: sourceName,
            sourceURL: sourceUrl.flatMap(URL.init(string:)),
            healthScore: healthScore,
            diets: diets ?? [],
            ingredients: ingredientLines.map(\.asIngredient),
            steps: steps,
            containsIntolerances: intolerances
        )
    }

    var asMatch: OnlineRecipeMatch {
        OnlineRecipeMatch(
            recipe: asRecipe,
            usedIngredientNames: (usedIngredients ?? []).map(\.resolvedName),
            missedIngredients: (missedIngredients ?? []).map(\.asIngredient)
        )
    }
}
