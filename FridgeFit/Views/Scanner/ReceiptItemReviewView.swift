//
//  ReceiptItemReviewView.swift
//  FridgeFit
//

import SwiftUI

/// The confirmation step between reading a receipt and saving the selected
/// grocery drafts. This is presentation only: every edit and save continues
/// through `ReceiptScannerViewModel` and its existing use cases.
struct ReceiptItemReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ReceiptScannerViewModel
    var onCompleted: (AddDetectedIngredientsSummary) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.drafts.isEmpty {
                    emptyReviewState
                } else {
                    reviewContent
                }
            }
            .background(FridgeFitTheme.ColorToken.canvas)
            .navigationTitle("Smart Scan Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FridgeFitTheme.ColorToken.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Return to receipt capture")
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
            .safeAreaInset(edge: .bottom) {
                if !viewModel.drafts.isEmpty {
                    addToPantryBar
                }
            }
        }
    }

    private var reviewContent: some View {
        ScrollView {
            LazyVStack(spacing: FridgeFitTheme.Spacing.medium) {
                receiptSourceCard
                reviewGuidanceCard

                ForEach(viewModel.drafts) { draft in
                    ReceiptReviewCard(draft: draft, viewModel: viewModel)
                }

                #if DEBUG
                excludedDiagnosticsCard
                #endif
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas)
    }

    private var receiptSourceCard: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: "receipt")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                    .frame(width: 48, height: 48)
                    .background(FridgeFitTheme.ColorToken.errorBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text("Receipt scanned")
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    Text("\(viewModel.drafts.count) \(viewModel.drafts.count == 1 ? "item" : "items") detected — review before saving")
                        .font(FridgeFitTheme.Typography.supporting)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack {
                FridgeFitStatusBadge(title: "Receipt OCR complete", systemImage: "document.viewfinder", tone: .success)
                Spacer()
                Text("On-device scan")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            }

            // A replayed result must say so. Presenting a cached outcome
            // with the same wording as a fresh one would tell the user the
            // model just ran when it did not.
            if viewModel.recognitionSource == .verifiedCache {
                Label(
                    "Reused the saved result from the last time this exact photo was analysed. You can still edit everything below.",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var reviewGuidanceCard: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
            Image(systemName: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 32, height: 32)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Review your groceries")
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                Text("Check each name, category, quantity, and unit before adding it to My Fridge.")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .background(FridgeFitTheme.ColorToken.successBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var emptyReviewState: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 80, height: 80)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
            Text("Nothing Left to Review")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("Every item from this receipt has been added or removed.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
            Button("Return to Smart Scan") { dismiss() }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FridgeFitTheme.Spacing.section)
        .background(FridgeFitTheme.ColorToken.canvas)
    }

    #if DEBUG
    @ViewBuilder
    private var excludedDiagnosticsCard: some View {
        if !viewModel.excludedItems.isEmpty {
            DisclosureGroup("Excluded items (\(viewModel.excludedItems.count))") {
                ForEach(viewModel.excludedItems) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(FridgeFitTheme.Typography.supporting)
                        Text("\(item.classification.diagnosticLabel) · \(item.sourceText)")
                            .font(FridgeFitTheme.Typography.caption)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                }
            }
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            .padding(FridgeFitTheme.Spacing.medium)
            .fridgeFitCardSurface()
        }
    }
    #endif

    private var addToPantryBar: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            if let summary = viewModel.addSummary, !summary.isCompleteSuccess {
                Label {
                    Text(summary.userMessage)
                        .font(FridgeFitTheme.Typography.metadata)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                .padding(FridgeFitTheme.Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FridgeFitTheme.ColorToken.errorBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
            }

            HStack {
                Text(selectionSummary)
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                Spacer()
            }

            Button {
                addSelected()
            } label: {
                if viewModel.isAddingToPantry {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Label(addButtonTitle, systemImage: "cabinet")
                }
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())
            .disabled(!viewModel.canAddToPantry)
        }
        .padding(.horizontal, FridgeFitTheme.Spacing.large)
        .padding(.top, FridgeFitTheme.Spacing.small)
        .padding(.bottom, FridgeFitTheme.Spacing.small)
        .background(FridgeFitTheme.ColorToken.canvas.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FridgeFitTheme.ColorToken.border.opacity(0.65))
                .frame(height: 1)
        }
    }

    private var selectionSummary: String {
        let count = viewModel.selectedDrafts.count
        return count == 0 ? "No items selected" : "\(count) \(count == 1 ? "item" : "items") selected"
    }

    private var addButtonTitle: String {
        let count = viewModel.selectedDrafts.count
        return count == 0 ? "Add to My Fridge" : "Add \(count) \(count == 1 ? "Item" : "Items") to My Fridge"
    }

    private func addSelected() {
        Task {
            await viewModel.addSelectedToPantry()
            if let summary = viewModel.addSummary, summary.isCompleteSuccess {
                onCompleted(summary)
            }
        }
    }
}

private struct ReceiptReviewCard: View {
    let draft: ReceiptItemDraft
    @ObservedObject var viewModel: ReceiptScannerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Button {
                    viewModel.toggleSelection(for: draft.id)
                } label: {
                    Image(systemName: draft.isSelected ? "checkmark" : "circle")
                        .font(.body.weight(.bold))
                        .foregroundStyle(draft.isSelected ? .white : FridgeFitTheme.ColorToken.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(
                            draft.isSelected ? FridgeFitTheme.ColorToken.brandFill : FridgeFitTheme.ColorToken.disabledSurface,
                            in: Circle()
                        )
                }
                .accessibilityLabel(draft.isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Double tap to \(draft.isSelected ? "exclude" : "include") \(draft.name)")

                IconBadge(systemImage: draft.category.symbolName, tint: draft.category.tint, size: 44)

                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    TextField(
                        "Item name",
                        text: Binding(
                            get: { draft.name },
                            set: { viewModel.updateName($0, for: draft.id) }
                        )
                    )
                    .font(FridgeFitTheme.Typography.cardTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Item name")

                    Text(draft.sourceText)
                        .font(FridgeFitTheme.Typography.caption)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .lineLimit(2)
                        .accessibilityLabel("From receipt line \(draft.sourceText)")
                }

                Button {
                    viewModel.removeDraft(id: draft.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove \(draft.name)")
            }

            if draft.isAlreadyInPantry {
                Label("Already in your pantry — this item starts unselected to prevent a duplicate.", systemImage: "shippingbox")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, FridgeFitTheme.Spacing.xSmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FridgeFitTheme.ColorToken.warningBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    quantityField
                        .frame(minWidth: 76, maxWidth: .infinity, alignment: .leading)
                    unitPicker
                        .frame(width: 60, alignment: .leading)
                    categoryPicker
                        .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                }

                VStack(spacing: FridgeFitTheme.Spacing.small) {
                    HStack(spacing: FridgeFitTheme.Spacing.small) {
                        quantityField
                        unitPicker
                    }
                    categoryPicker
                }
            }

            if !draft.hasDetectedQuantity && draft.quantity == nil {
                Label("Quantity wasn’t detected. Enter a quantity before saving this selected item.", systemImage: "exclamationmark.circle")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .opacity(draft.isSelected ? 1 : 0.68)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .contain)
    }

    private var quantityField: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("QUANTITY")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            TextField(
                draft.hasDetectedQuantity ? "Quantity" : "Required",
                text: Binding(
                    get: { draft.quantityText },
                    set: { viewModel.updateQuantityText($0, for: draft.id) }
                )
            )
            .keyboardType(.decimalPad)
            .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            .padding(.horizontal, FridgeFitTheme.Spacing.small)
            .frame(minHeight: 44)
            .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
            .accessibilityLabel(draft.hasDetectedQuantity ? "Quantity for \(draft.name)" : "Quantity for \(draft.name), not detected on the receipt")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unitPicker: some View {
        compactPicker(
            title: "UNIT",
            selection: Binding(
                get: { draft.unit },
                set: { viewModel.updateUnit($0, for: draft.id) }
            ),
            values: MeasurementUnit.allCases,
            label: { $0.symbol }
        )
    }

    private var categoryPicker: some View {
        compactPicker(
            title: "CATEGORY",
            selection: Binding(
                get: { draft.category },
                set: { viewModel.updateCategory($0, for: draft.id) }
            ),
            values: IngredientCategory.allCases,
            label: { $0.rawValue }
        )
    }

    private func compactPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        values: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(FridgeFitTheme.ColorToken.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
            .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
private enum ReceiptReviewPreviewData {
    static func draft(
        _ name: String,
        category: IngredientCategory,
        quantity: ReceiptQuantity?,
        isAlreadyInPantry: Bool = false
    ) -> ReceiptItemDraft {
        ReceiptItemDraft(
            candidate: ReceiptIngredientCandidate(
                displayName: name,
                canonicalName: name.lowercased(),
                classification: .ingredient,
                category: category,
                quantity: quantity,
                sourceText: name.uppercased(),
                order: 0,
                isAlreadyInPantry: isAlreadyInPantry
            )
        )
    }

    static let normal = [
        draft("Milk", category: .dairy, quantity: ReceiptQuantity(value: 2, unit: .liters)),
        draft("Baby Spinach", category: .produce, quantity: ReceiptQuantity(value: 120, unit: .grams)),
        draft("Free Range Eggs", category: .other, quantity: ReceiptQuantity(value: 12, unit: .pieces))
    ]

    static let duplicateAndMissingQuantity = [
        draft("Milk", category: .dairy, quantity: ReceiptQuantity(value: 2, unit: .liters), isAlreadyInPantry: true),
        draft("Truss Tomatoes", category: .produce, quantity: nil)
    ]
}

#Preview("Receipt Review — Normal Results") {
    ReceiptItemReviewView(
        viewModel: ReceiptScannerViewModel(previewDrafts: ReceiptReviewPreviewData.normal),
        onCompleted: { _ in }
    )
}

#Preview("Receipt Review — Duplicate and Missing Quantity") {
    ReceiptItemReviewView(
        viewModel: ReceiptScannerViewModel(previewDrafts: ReceiptReviewPreviewData.duplicateAndMissingQuantity),
        onCompleted: { _ in }
    )
}
#endif
