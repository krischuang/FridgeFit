//
//  OnlineRecipeCookingView.swift
//  FridgeFit
//

import SwiftUI

/// Step-by-step cooking mode for an online recipe: one step at a time,
/// large text, previous / next.
struct OnlineRecipeCookingView: View {
    let title: String
    let steps: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private typealias Token = FridgeFitTheme.ColorToken

    /// "Step 1: Boil the pasta" - the first few words of a step, for the
    /// detail screen's start button.
    static func shortLabel(for step: String, maxWords: Int = 4) -> String {
        let words = step.split(separator: " ")
        let head = words.prefix(maxWords).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!"))
        return words.count > maxWords ? head + "…" : head
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xLarge) {
                if steps.isEmpty {
                    Text("No step-by-step method was provided for this recipe.")
                        .foregroundStyle(Token.textSecondary)
                } else {
                    ProgressView(value: Double(index + 1), total: Double(steps.count))
                        .tint(Token.primary)
                    Text("Step \(index + 1) of \(steps.count)")
                        .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                        .foregroundStyle(Token.primary)
                    ScrollView {
                        Text(steps[index])
                            .font(.title3)
                            .foregroundStyle(Token.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: FridgeFitTheme.Spacing.medium) {
                        Button("Previous") { index -= 1 }
                            .buttonStyle(FridgeFitSecondaryButtonStyle())
                            .disabled(index == 0)
                        if index < steps.count - 1 {
                            Button("Next Step") { index += 1 }
                                .buttonStyle(FridgeFitPrimaryButtonStyle())
                        } else {
                            Button("Done") { dismiss() }
                                .buttonStyle(FridgeFitPrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(FridgeFitTheme.Spacing.large)
            .background(Token.canvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
