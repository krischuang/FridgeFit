//
//  RecommendationViewModel.swift
//  FridgeFit
//

import Combine
import Foundation

/// Presentation state for the context-aware recommendation screen.
///
/// Never ranks or filters anything itself - that is all
/// `GenerateContextAwareRecommendationsUseCase`. This holds the context
/// the user picked, the session feedback they gave, and whatever the last
/// run produced.
///
/// The use case is `nonisolated`, so `await`ing it from here hops off the
/// main actor for the pantry read and the ranking, and back on to publish.
@MainActor
final class RecommendationViewModel: ObservableObject {

    @Published private(set) var recommendations: [RecipeRecommendation] = []
    @Published private(set) var isLoading = false
    /// The failure from the last run, if it failed. A
    /// `RecommendationGenerationError` rather than a string so the view can
    /// offer the right recovery action.
    @Published private(set) var failure: RecommendationGenerationError?
    /// A message for anything that wasn't a domain failure.
    @Published private(set) var unexpectedErrorMessage: String?
    /// The context the last run used. `nil` until the first run.
    @Published private(set) var appliedContext: CookingContext?
    /// The context the preference form edits. Applied on generate.
    @Published var draftContext: CookingContext = .unrestricted
    @Published private(set) var session = RecommendationSession()
    @Published private(set) var hasRun = false

    private let generateUseCase: GenerateContextAwareRecommendationsUseCase
    /// The in-flight run, so a second request supersedes the first rather
    /// than racing it to publish.
    private var runTask: Task<Void, Never>?

    init(generateUseCase: GenerateContextAwareRecommendationsUseCase) {
        self.generateUseCase = generateUseCase
    }

    var hasRecommendations: Bool { !recommendations.isEmpty }

    /// Recipes the user saved in this session, newest state only.
    var savedRecipeCount: Int { session.savedRecipeIDs.count }

    // MARK: - Running

    /// Generates recommendations for `draftContext`.
    ///
    /// Reads the pantry fresh every time, so returning from Pantry or
    /// Kitchen and regenerating always reflects what is actually there.
    func generate() async {
        runTask?.cancel()
        let context = draftContext
        let task = Task { await self.run(context: context) }
        runTask = task
        await task.value
    }

    /// Re-runs the last applied context, or the draft if nothing has run.
    func regenerate() async {
        draftContext = appliedContext ?? draftContext
        await generate()
    }

    private func run(context: CookingContext) async {
        isLoading = true
        failure = nil
        unexpectedErrorMessage = nil

        defer {
            isLoading = false
            hasRun = true
        }

        do {
            let results = try await generateUseCase.execute(context: context, session: session)
            guard !Task.isCancelled else { return }
            recommendations = results
            appliedContext = context
        } catch is CancellationError {
            // Superseded by a newer run; its result is the one that counts.
            return
        } catch let error as RecommendationGenerationError {
            guard !Task.isCancelled else { return }
            recommendations = []
            appliedContext = context
            failure = error
        } catch {
            guard !Task.isCancelled else { return }
            recommendations = []
            appliedContext = context
            unexpectedErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Session feedback

    /// Records feedback and immediately re-ranks.
    ///
    /// Re-running rather than locally reordering keeps one ranking
    /// implementation: the list the user sees after giving feedback is
    /// produced by exactly the code the tests assert against. A skip also
    /// removes the recipe, which only the use case knows how to do.
    func record(_ action: SessionRecipeFeedbackAction, for recipe: Recipe) async {
        session.record(SessionRecipeFeedback(recipeID: recipe.id, action: action))
        await regenerate()
    }

    /// Clears feedback for one recipe and re-ranks.
    func clearFeedback(for recipe: Recipe) async {
        session.clearFeedback(for: recipe.id)
        await regenerate()
    }

    func feedback(for recipe: Recipe) -> SessionRecipeFeedbackAction? {
        session.feedback(for: recipe.id)
    }

    /// Ends the current session and starts a fresh one, bringing skipped
    /// recipes back.
    func startNewSession() async {
        session.end()
        session = RecommendationSession()
        await regenerate()
    }

    /// Cancels any in-flight run. Called when the screen goes away.
    func cancel() {
        runTask?.cancel()
        runTask = nil
    }
}
