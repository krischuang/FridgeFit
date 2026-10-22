//
//  KitchenActivityView.swift
//  FridgeFit
//

import SwiftUI

/// What the user has actually done with their food.
///
/// Shows committed events only - added, used, finished, discarded, quantity
/// corrected. Typing in the editor and tapping around the drawer never reach
/// here, because a history full of keystrokes is not a history.
///
/// Items that have been finished or discarded are gone from the pantry but
/// their events remain, which is the point: this is the only place the
/// difference between "we ate it" and "we threw it out" survives.
struct KitchenActivityView: View {
    @Environment(\.dismiss) private var dismiss

    let activities: [InventoryEvent]

    var body: some View {
        NavigationStack {
            ScrollView {
                if activities.isEmpty {
                    EmptyKitchenView(
                        title: "No kitchen activity yet",
                        message: "Saved changes will appear here.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(activities) { activity in
                            activityCard(activity)
                        }
                    }
                    .padding(20)
                }
            }
            .background(KitchenTheme.background.ignoresSafeArea())
            .navigationTitle("Kitchen Activity")
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
            }
        }
    }

    private func activityCard(_ activity: InventoryEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activity.kind.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint(for: activity.kind))
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint(for: activity.kind).opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activity.itemName)
                        .font(.headline)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(activity.kind.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint(for: activity.kind))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint(for: activity.kind).opacity(0.12)))
                }

                if let note = activity.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KitchenTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(KitchenTheme.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// Waste reads red, consumption reads as the kitchen accent. Both are
    /// labelled in words beside the icon, so the colour is reinforcement
    /// rather than the only signal.
    private func tint(for kind: InventoryEventKind) -> Color {
        switch kind {
        case .discarded, .deleted:
            return .red
        case .finished, .used:
            return KitchenTheme.warmAccent
        case .added, .quantityAdjusted, .opened, .edited:
            return KitchenTheme.forest
        }
    }
}

#Preview {
    KitchenActivityView(activities: [
        InventoryEvent(pantryItemID: UUID(), itemName: "Milk", kind: .used, note: "Used 200 ml"),
        InventoryEvent(pantryItemID: UUID(), itemName: "Spinach", kind: .discarded, note: "150 g"),
    ])
}
