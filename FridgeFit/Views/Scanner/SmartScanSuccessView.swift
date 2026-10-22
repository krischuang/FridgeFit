//
//  SmartScanSuccessView.swift
//  FridgeFit
//

import SwiftUI

/// A persisted, complete Smart Scan result. It is deliberately built from
/// `AddDetectedIngredientsSummary`, rather than recognition candidates, so it
/// can never celebrate items that did not reach the pantry.
struct SmartScanSuccessResult: Identifiable {
    let id = UUID()
    let summary: AddDetectedIngredientsSummary
}

/// Shared completion surface for receipt and local-ingredient Smart Scan
/// flows. Callers present it only for a complete non-empty save.
struct SmartScanSuccessView: View {
    let summary: AddDetectedIngredientsSummary
    let onScanMore: () -> Void
    let onViewMyFridge: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FridgeFitTheme.Spacing.large) {
                    successHero
                    inventoryUpdateCard

                    VStack(spacing: FridgeFitTheme.Spacing.small) {
                        Button(action: onScanMore) {
                            Label("Scan More Items", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(FridgeFitPrimaryButtonStyle())

                        Button(action: onViewMyFridge) {
                            Label("View My Fridge", systemImage: "refrigerator")
                        }
                        .buttonStyle(FridgeFitSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, FridgeFitTheme.Spacing.large)
                .padding(.top, FridgeFitTheme.Spacing.medium)
                .padding(.bottom, FridgeFitTheme.Spacing.section)
            }
            .background(FridgeFitTheme.ColorToken.canvas)
            .navigationTitle("Smart Scan Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onViewMyFridge) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close Smart Scan")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Image(systemName: "person")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(FridgeFitTheme.ColorToken.brandFill, in: Circle())
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var successHero: some View {
        VStack(spacing: FridgeFitTheme.Spacing.medium) {
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(FridgeFitTheme.ColorToken.successBackground.opacity(0.72))
                    .frame(width: 230, height: 230)

                RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.largeCard, style: .continuous)
                    .fill(FridgeFitTheme.ColorToken.card)
                    .frame(width: 190, height: 190)
                    .overlay {
                        VStack(spacing: FridgeFitTheme.Spacing.small) {
                            Image(systemName: "refrigerator")
                                .font(.system(size: 70, weight: .light))
                                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                            HStack(spacing: FridgeFitTheme.Spacing.small) {
                                Image(systemName: "leaf.fill")
                                Image(systemName: "carrot.fill")
                                Image(systemName: "fish.fill")
                            }
                            .font(.title3)
                            .foregroundStyle(FridgeFitTheme.ColorToken.primaryMuted)
                        }
                    }
                    .shadow(color: .black.opacity(0.055), radius: 8, y: 3)

                Label("Sync Complete", systemImage: "checkmark.circle.fill")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.medium)
                    .padding(.vertical, FridgeFitTheme.Spacing.small)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                    .offset(y: 18)
            }
            .padding(.bottom, FridgeFitTheme.Spacing.small)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Smart Scan sync complete")

            VStack(spacing: FridgeFitTheme.Spacing.small) {
                Text("Your fridge is up to date!")
                    .font(FridgeFitTheme.Typography.hero)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .multilineTextAlignment(.center)

                Text(successMessage)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var inventoryUpdateCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Circle()
                    .fill(FridgeFitTheme.ColorToken.primary)
                    .frame(width: 10, height: 10)
                Text("INVENTORY UPDATE")
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Spacer()
            }

            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                    Label(
                        "\(summary.addedCount) \(summary.addedCount == 1 ? "New Item" : "New Items")",
                        systemImage: "plus.circle"
                    )
                    .font(FridgeFitTheme.Typography.sectionTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                    ForEach(summary.addedNames, id: \.self) { name in
                        Label(name, systemImage: "circle.fill")
                            .font(FridgeFitTheme.Typography.supporting)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                            .symbolRenderingMode(.hierarchical)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var successMessage: String {
        let count = summary.addedCount
        return count == 1
            ? "Successfully added 1 new ingredient to your inventory."
            : "Successfully added \(count) new ingredients to your inventory."
    }
}

#Preview {
    SmartScanSuccessView(
        summary: AddDetectedIngredientsSummary(
            addedNames: ["Baby Spinach", "Eggs", "Truss Tomatoes"],
            duplicateNames: [],
            failures: []
        ),
        onScanMore: {},
        onViewMyFridge: {}
    )
}
