//
//  RemoveSavedRecipeUseCase.swift
//  FridgeFit
//

import Foundation

/// Removes a recipe the user saved from Discover. Bundled recipes can't be
/// removed - the caller only offers this for saved ones.
struct RemoveSavedRecipeUseCase {
    let repository: SavedRecipeRepository

    func execute(id: UUID) async throws {
        do {
            try await repository.remove(id: id)
        } catch let error as SaveOnlineRecipeError {
            throw error
        } catch {
            throw SaveOnlineRecipeError.removeFailed
        }
    }
}
