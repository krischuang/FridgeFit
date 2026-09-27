//
//  IngredientDetectionPromptBuilder.swift
//  FridgeFit
//

import Foundation

/// Builds the instructions and prompt for a fridge scan.
///
/// Separate from `AppleIngredientRecognitionService` for the same reason as
/// `SubstitutionPromptBuilder`: prompt wording is the part most likely to
/// change, and it's the only part that can be unit tested without an
/// Apple Intelligence device.
///
/// The prompt is written to fight the failure mode that matters here -
/// a model happily listing a plausible fridge instead of the one in the
/// photo. Everything it's allowed to mention has to trace back to the
/// supplied evidence.
struct IngredientDetectionPromptBuilder {
    /// Session instructions: the model's standing role, sent once.
    static let instructions = """
        You are a conservative food inventory assistant inside a kitchen app called FridgeFit.

        You are given the results of on-device image analysis of a photo taken inside a \
        refrigerator: a list of visual labels with confidence scores, and any text that was \
        read off packaging and labels.

        Your job is to decide which food ingredients are actually present, and to name them \
        the way a recipe would.

        Rules you must follow:
        - Only report food that the evidence actually supports. The visual labels and the \
        recognised text are your only evidence.
        - Never invent ingredients that a fridge "usually" contains. A typical fridge is not \
        evidence.
        - Do not guess what is inside opaque containers, tubs or bags.
        - Ignore shelves, drawers, containers, plates, bottles, jars, packaging and other \
        kitchen objects. They are not ingredients. Report what is in the container only when \
        the evidence names the food.
        - Use simple normalized ingredient names. Prefer "milk" over "a carton of full cream \
        milk", and "tomato" over "ripe red tomatoes on the vine".
        - Use the singular form, in lowercase, with no brand names.
        - Do not report the same ingredient twice.
        - Only count units when the evidence makes them countable. Otherwise report a count \
        of 0.
        - Never invent expiry dates, weights or volumes.
        - Report low confidence when the evidence is weak or ambiguous, rather than leaving \
        the ingredient out or overstating it.
        - If the evidence does not support any food ingredient, return an empty list. An \
        empty answer is a correct answer.
        """

    /// The per-scan prompt: the evidence extracted from this one photo.
    ///
    /// Returns `nil` when there's nothing to reason about - asking a
    /// generative model to identify ingredients from no evidence is
    /// precisely how hallucinated pantries happen.
    func makePrompt(for evidence: FridgeImageEvidence) -> String? {
        guard !evidence.isEmpty else { return nil }

        var sections: [String] = ["Image analysis results for one refrigerator photo."]

        if evidence.labels.isEmpty {
            sections.append("Visual labels: none detected.")
        } else {
            let labels = evidence.labels
                .map { "- \($0.identifier) (confidence \(Self.formatted($0.confidence)))" }
                .joined(separator: "\n")
            sections.append("Visual labels detected in the photo:\n\(labels)")
        }

        if evidence.recognizedText.isEmpty {
            sections.append("Text read from packaging: none.")
        } else {
            let text = evidence.recognizedText
                .map { "- \"\($0)\"" }
                .joined(separator: "\n")
            sections.append("Text read from packaging and labels:\n\(text)")
        }

        sections.append(
            """
            List the food ingredients this evidence supports. Follow every rule you were given. \
            Return an empty list rather than guessing.
            """
        )

        return sections.joined(separator: "\n\n")
    }

    private static func formatted(_ confidence: Float) -> String {
        String(format: "%.2f", confidence)
    }
}
