import SwiftUI

/// Displays committed household inventory activity.
///
/// This surface shows persisted inventory events such as food added, used,
/// finished, discarded, or quantity-adjusted. Draft edits and unsaved drawer
/// changes are intentionally excluded because only committed household actions
/// belong in kitchen history.
struct KitchenActivityView: View {
    @Environment(\.dismiss) private var dismiss

    let activities: [InventoryActivity]

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
            .background(SmartFridgeTheme.background.ignoresSafeArea())
            .navigationTitle("Kitchen Activity")
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
            }
        }
    }

    private func activityCard(_ activity: InventoryActivity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: activity.kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint(for: activity.kind))
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint(for: activity.kind).opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activity.ingredientName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(title(for: activity.kind))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint(for: activity.kind))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint(for: activity.kind).opacity(0.12)))
                }

                if let note = displayNote(for: activity.note) {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SmartFridgeTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(SmartFridgeTheme.separator, lineWidth: 1)
        )
    }

    private func title(for kind: InventoryEventKind) -> String {
        switch kind {
        case .added: "Added"
        case .used: "Used"
        case .quantityAdjusted: "Adjusted"
        case .opened: "Opened"
        case .finished: "Finished"
        case .discarded: "Discarded"
        case .deleted: "Deleted"
        case .edited: "Edited"
        }
    }

    private func tint(for kind: InventoryEventKind) -> Color {
        switch kind {
        case .discarded, .deleted:
            return .red
        case .finished, .used:
            return SmartFridgeTheme.warmAccent
        default:
            return SmartFridgeTheme.forest
        }
    }

    private func icon(for kind: InventoryEventKind) -> String {
        switch kind {
        case .added: "plus"
        case .used: "minus"
        case .quantityAdjusted: "slider.horizontal.3"
        case .opened: "seal"
        case .finished: "checkmark"
        case .discarded: "trash"
        case .deleted: "xmark"
        case .edited: "pencil"
        }
    }

    private func displayNote(for note: String?) -> String? {
        guard let note else { return nil }
        return note == "Seeded" ? "Added from starter list" : note
    }
}
