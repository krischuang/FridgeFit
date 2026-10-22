//
//  IngredientReviewView.swift
//  FridgeFit
//

import SwiftUI

/// The human-confirmation step after a local ingredient scan. This view only
/// renders and edits the existing review model; recognition and persistence
/// remain in `RemoteCameraViewModel` and `AddDetectedIngredientsUseCase`.
struct IngredientReviewView: View {
    @StateObject private var viewModel: IngredientReviewViewModel
    @Environment(\.dismiss) private var dismiss

    private let snapshot: UIImage
    private let onConfirm: ([ConfirmedIngredient]) -> Void
    /// Exposes the existing persisted save summary to the local Smart Scan
    /// flow. The Remote Camera caller does not need a completion surface, so
    /// it retains the no-op default.
    private let onSaveCompleted: (AddDetectedIngredientsSummary) -> Void

    @State private var editingItem: IngredientReviewItem?
    @State private var isAddingManually = false
    @State private var highlightedItemId: UUID?

    init(
        analysis: SnapshotAnalysis,
        snapshot: UIImage,
        addIngredientsUseCase: AddDetectedIngredientsUseCase,
        onConfirm: @escaping ([ConfirmedIngredient]) -> Void = { _ in },
        onSaveCompleted: @escaping (AddDetectedIngredientsSummary) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: IngredientReviewViewModel(
            analysis: analysis,
            addIngredientsUseCase: addIngredientsUseCase
        ))
        self.snapshot = snapshot
        self.onConfirm = onConfirm
        self.onSaveCompleted = onSaveCompleted
    }

    init(
        viewModel: IngredientReviewViewModel,
        snapshot: UIImage,
        onConfirm: @escaping ([ConfirmedIngredient]) -> Void = { _ in },
        onSaveCompleted: @escaping (AddDetectedIngredientsSummary) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.snapshot = snapshot
        self.onConfirm = onConfirm
        self.onSaveCompleted = onSaveCompleted
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isEmpty {
                    emptyState
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
                    .disabled(viewModel.saveState.isSaving)
                    .accessibilityLabel("Close ingredient review")
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
            .sheet(item: $editingItem) { item in
                EditIngredientSheet(item: item) { name, category in
                    viewModel.rename(item.id, to: name)
                    viewModel.recategorise(item.id, to: category)
                }
            }
            .sheet(isPresented: $isAddingManually) {
                AddIngredientSheet { name, category in
                    viewModel.addManualIngredient(name: name, category: category)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !viewModel.isEmpty {
                    saveBar
                }
            }
        }
    }

    private var reviewContent: some View {
        ScrollView {
            LazyVStack(spacing: FridgeFitTheme.Spacing.medium) {
                scanSummaryCard
                capabilityNotice

                if !viewModel.localisedItems.isEmpty {
                    reviewSectionHeader("In the photo", detail: "Detected at a measured location in your image")
                    ForEach(viewModel.localisedItems) { item in
                        card(for: item)
                    }
                }

                if !viewModel.unlocalisedItems.isEmpty {
                    reviewSectionHeader("Suggested", detail: "Whole-image, packaging, or manually added items")
                    ForEach(viewModel.unlocalisedItems) { item in
                        card(for: item)
                    }
                }

                readinessNotice
                saveResultCard
                manualAddCard
                packagingCard
                diagnosticsCard
            }
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .padding(.top, FridgeFitTheme.Spacing.small)
            .padding(.bottom, FridgeFitTheme.Spacing.large)
        }
        .background(FridgeFitTheme.ColorToken.canvas)
    }

    private var scanSummaryCard: some View {
        HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.medium) {
            scanSummaryThumbnail

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                Text("Here’s what we found")
                    .font(FridgeFitTheme.Typography.screenTitle)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)

                Text("\(viewModel.items.count) \(viewModel.items.count == 1 ? "item" : "items") to review")
                    .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.small)
                    .padding(.vertical, 2)
                    .background(FridgeFitTheme.ColorToken.successBackground, in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)

                Text("Check the items below. Adjust names, categories, and quantities before saving to My Fridge.")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var scanSummaryThumbnail: some View {
        if snapshot.isSymbolImage {
            Image(systemName: "camera.viewfinder")
                .font(.title2.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 76, height: 76)
                .background(
                    FridgeFitTheme.ColorToken.successBackground,
                    in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                )
                .accessibilityLabel("Ingredient scan placeholder")
        } else {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
                .accessibilityLabel("Scanned ingredient photo")
        }
    }

    @ViewBuilder
    private var capabilityNotice: some View {
        if let message = viewModel.classification.userMessage {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Image(systemName: viewModel.classification.capability.isExpectedLimitation ? "info.circle" : "exclamationmark.triangle.fill")
                    .foregroundStyle(viewModel.classification.capability.isExpectedLimitation ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.warningText)
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text(message)
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    if viewModel.classification.isDetectorOnly {
                        Text("These results use object detection only. Review each item before saving.")
                            .font(FridgeFitTheme.Typography.metadata)
                            .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    }
                }
            }
            .padding(FridgeFitTheme.Spacing.medium)
            .background(FridgeFitTheme.ColorToken.warningBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
            .accessibilityIdentifier("capability-notice")
        }
    }

    private func reviewSectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(FridgeFitTheme.Typography.sectionTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text(detail)
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FridgeFitTheme.Spacing.xSmall)
    }

    private func card(for item: IngredientReviewItem) -> some View {
        IngredientScanReviewCard(
            item: item,
            isHighlighted: highlightedItemId == item.id,
            onToggle: { viewModel.toggleAcceptance(item.id) },
            onEdit: { editingItem = item },
            onRemove: item.origin == .manual ? { viewModel.remove(item.id) } : nil,
            onQuantityChange: { viewModel.setQuantityText($0, for: item.id) },
            onUnitChange: { viewModel.setUnit($0, for: item.id) }
        )
        .onTapGesture { highlightedItemId = item.id }
    }

    @ViewBuilder
    private var readinessNotice: some View {
        let missing = viewModel.acceptedItemsMissingQuantity
        if !missing.isEmpty {
            Label(
                missing.count == 1
                    ? "\(missing[0].displayName) needs an amount before it can be saved."
                    : "\(missing.count) selected ingredients need an amount before they can be saved.",
                systemImage: "number.circle"
            )
            .font(FridgeFitTheme.Typography.metadata)
            .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
            .padding(FridgeFitTheme.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FridgeFitTheme.ColorToken.warningBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous))
        }
    }

    @ViewBuilder
    private var saveResultCard: some View {
        if let summary = viewModel.saveState.summary {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                Label(summary.userMessage, systemImage: summary.isCompleteSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(summary.isCompleteSuccess ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.warningText)

                ForEach(summary.failures, id: \.name) { failure in
                    Text("\(failure.name): \(failure.message)")
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                }

                if viewModel.saveState.isRetryable {
                    Button {
                        Task { await viewModel.retrySave() }
                    } label: {
                        Label("Retry the items that didn’t save", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
                    .accessibilityIdentifier("retry-save")
                }

                Button("Dismiss") { viewModel.dismissSaveResult() }
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(minHeight: 44)
            }
            .padding(FridgeFitTheme.Spacing.medium)
            .background(FridgeFitTheme.ColorToken.warningBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        } else if let message = viewModel.saveState.failureMessage {
            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(FridgeFitTheme.Typography.supporting)
                    .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                Button {
                    Task { await viewModel.retrySave() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
                .accessibilityIdentifier("retry-save")
                Button("Dismiss") { viewModel.dismissSaveResult() }
                    .font(FridgeFitTheme.Typography.metadata.weight(.semibold))
                    .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                    .frame(minHeight: 44)
            }
            .padding(FridgeFitTheme.Spacing.medium)
            .background(FridgeFitTheme.ColorToken.errorBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous))
        }
    }

    private var manualAddCard: some View {
        VStack(spacing: FridgeFitTheme.Spacing.small) {
            Button {
                isAddingManually = true
            } label: {
                Label("Add another item manually", systemImage: "plus.circle")
            }
            .buttonStyle(FridgeFitSecondaryButtonStyle())

            HStack(spacing: FridgeFitTheme.Spacing.small) {
                Button("Accept all") { viewModel.acceptAll() }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
                Button("Reject all", role: .destructive) { viewModel.rejectAll() }
                    .buttonStyle(FridgeFitSecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var packagingCard: some View {
        if !viewModel.packagingLines.isEmpty {
            DisclosureGroup("Packaging text (\(viewModel.packagingLines.count) lines)") {
                ForEach(Array(viewModel.packagingLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(FridgeFitTheme.Typography.caption.monospaced())
                        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
            .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            .padding(FridgeFitTheme.Spacing.medium)
            .fridgeFitCardSurface()
        }
    }

    private var diagnosticsCard: some View {
        DisclosureGroup("Recognition details") {
            LabeledContent("Both methods agree", value: "\(viewModel.count(of: .agreed))")
            LabeledContent("One method only", value: "\(viewModel.count(of: .singleSource))")
            LabeledContent("Methods disagree", value: "\(viewModel.count(of: .conflicting))")
            if !viewModel.rejectedFoodClaims.isEmpty {
                LabeledContent("Discarded guesses", value: viewModel.rejectedFoodClaims.joined(separator: ", "))
                    .font(FridgeFitTheme.Typography.caption)
            }
        }
        .font(FridgeFitTheme.Typography.metadata)
        .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        .padding(FridgeFitTheme.Spacing.medium)
        .fridgeFitCardSurface()
    }

    private var saveBar: some View {
        VStack(spacing: FridgeFitTheme.Spacing.xSmall) {
            Button {
                Task { await save() }
            } label: {
                if viewModel.saveState.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label(saveButtonTitle, systemImage: "checkmark")
                }
            }
            .buttonStyle(FridgeFitPrimaryButtonStyle())
            .disabled(!viewModel.canSaveToPantry)
            .accessibilityIdentifier("save-to-pantry")

            Label("Only confirmed ingredients are added to My Fridge.", systemImage: "leaf")
                .font(FridgeFitTheme.Typography.caption)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
        }
        .padding(.horizontal, FridgeFitTheme.Spacing.large)
        .padding(.top, FridgeFitTheme.Spacing.small)
        .padding(.bottom, FridgeFitTheme.Spacing.small)
        .background(FridgeFitTheme.ColorToken.canvas.opacity(0.97))
        .overlay(alignment: .top) {
            Rectangle().fill(FridgeFitTheme.ColorToken.border.opacity(0.65)).frame(height: 1)
        }
    }

    private var saveButtonTitle: String {
        let count = viewModel.acceptedCount
        return count == 1 ? "Add 1 Item to My Fridge" : "Add \(count) Items to My Fridge"
    }

    private var emptyState: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .frame(width: 80, height: 80)
                .background(FridgeFitTheme.ColorToken.successBackground, in: Circle())
            Text("No ingredients recognised")
                .font(FridgeFitTheme.Typography.screenTitle)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
            Text("Nothing in this photo matched an ingredient we can recognise. You can add one manually instead.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add one manually") { isAddingManually = true }
                .buttonStyle(FridgeFitPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(FridgeFitTheme.Spacing.section)
        .background(FridgeFitTheme.ColorToken.canvas)
    }

    private func save() async {
        await viewModel.saveToPantry()
        if viewModel.saveState.allowsAutomaticDismissal {
            if let summary = viewModel.saveState.summary {
                onSaveCompleted(summary)
            }
            onConfirm(viewModel.confirmed ?? [])
            dismiss()
        }
    }
}

private struct IngredientScanReviewCard: View {
    let item: IngredientReviewItem
    let isHighlighted: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRemove: (() -> Void)?
    let onQuantityChange: (String) -> Void
    let onUnitChange: (MeasurementUnit) -> Void

    @State private var quantityText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            HStack(alignment: .top, spacing: FridgeFitTheme.Spacing.small) {
                Button(action: onToggle) {
                    Image(systemName: item.isAccepted ? "checkmark" : "circle")
                        .font(.body.weight(.bold))
                        .foregroundStyle(item.isAccepted ? .white : FridgeFitTheme.ColorToken.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(item.isAccepted ? FridgeFitTheme.ColorToken.brandFill : FridgeFitTheme.ColorToken.disabledSurface, in: Circle())
                }
                .accessibilityLabel(item.isAccepted ? "Accepted" : "Rejected")
                .accessibilityIdentifier("toggle-\(item.id.uuidString)")

                IngredientArtwork(category: item.resolvedPantryCategory, size: 38)

                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
                    Text(item.displayName)
                        .font(FridgeFitTheme.Typography.cardTitle)
                        .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                        .lineLimit(2)
                    provenanceBadge
                }

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Edit \(item.displayName)")

                    if let onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove \(item.displayName)")
                    }
                }
            }

            if item.wasEdited {
                FridgeFitStatusBadge(title: "Edited", systemImage: "pencil", tone: .neutral)
            }

            if let other = item.conflictingClaim {
                Label("Another recognition method suggested \(other). Please check this item.", systemImage: "exclamationmark.triangle")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                    .padding(FridgeFitTheme.Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FridgeFitTheme.ColorToken.warningBackground, in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
            }

            if let reason = item.reviewReason {
                Label(reason.message, systemImage: "info.circle")
                    .font(FridgeFitTheme.Typography.metadata)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .padding(FridgeFitTheme.Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
            }

            if item.isAccepted {
                HStack(spacing: FridgeFitTheme.Spacing.small) {
                    quantityControl
                    unitControl
                }

                if !item.hasValidQuantity {
                    Label("Enter a quantity before saving this item.", systemImage: "number.circle")
                        .font(FridgeFitTheme.Typography.metadata)
                        .foregroundStyle(FridgeFitTheme.ColorToken.warningText)
                }
            }
        }
        .padding(FridgeFitTheme.Spacing.medium)
        .opacity(item.isAccepted ? 1 : 0.68)
        .background(
            FridgeFitTheme.ColorToken.card,
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card, style: .continuous)
                .stroke(isHighlighted ? FridgeFitTheme.ColorToken.primary : FridgeFitTheme.ColorToken.border, lineWidth: isHighlighted ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
        .onAppear { quantityText = item.quantityText }
        .onChange(of: item.quantityText) { _, newValue in
            if quantityText != newValue { quantityText = newValue }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var provenanceBadge: some View {
        if let tier = item.tier {
            FridgeFitStatusBadge(
                title: LocalizedStringKey(tier.displayName),
                systemImage: tier.symbolName,
                tone: badgeTone(for: tier)
            )
        } else {
            FridgeFitStatusBadge(title: "Added by you", systemImage: "hand.raised", tone: .neutral)
        }
    }

    private var quantityControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("QUANTITY")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            TextField("Required", text: $quantityText)
                .keyboardType(.decimalPad)
                .font(FridgeFitTheme.Typography.supporting.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .padding(.horizontal, FridgeFitTheme.Spacing.small)
                .frame(minHeight: 44)
                .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
                .onChange(of: quantityText) { _, newValue in onQuantityChange(newValue) }
                .accessibilityIdentifier("quantity-\(item.id.uuidString)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unitControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("UNIT")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
            Picker("Unit", selection: Binding(get: { item.unit }, set: onUnitChange)) {
                ForEach(MeasurementUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(FridgeFitTheme.ColorToken.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, FridgeFitTheme.Spacing.xSmall)
            .background(FridgeFitTheme.ColorToken.disabledSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.small, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badgeTone(for tier: ConfidenceTier) -> FridgeFitStatusTone {
        switch tier {
        case .agreed: return .success
        case .singleSource: return .neutral
        case .conflicting: return .warning
        }
    }
}

struct EditIngredientSheet: View {
    let item: IngredientReviewItem
    let onSave: (String, IngredientGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: IngredientGroup

    init(item: IngredientReviewItem, onSave: @escaping (String, IngredientGroup) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.displayName)
        _category = State(initialValue: item.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Ingredient", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("edit-name")
                }
                Section("Category") {
                    CategoryPicker(selection: $category)
                }
                if let recognised = item.recognised {
                    Section("What recognition said") {
                        LabeledContent("Suggested", value: recognised.displayName)
                        if let term = recognised.detectorTerm {
                            LabeledContent("Detector", value: term)
                        }
                        if let identifier = recognised.classifierIdentifier {
                            LabeledContent("Classifier", value: identifier)
                        }
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Edit Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, category)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AddIngredientSheet: View {
    let onAdd: (String, IngredientGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category: IngredientGroup = .vegetable

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Ingredient", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("add-name")
                }
                Section("Category") {
                    CategoryPicker(selection: $category)
                }
            }
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name, category)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct CategoryPicker: View {
    @Binding var selection: IngredientGroup

    var body: some View {
        Picker("Category", selection: $selection) {
            ForEach(IngredientGroup.allCases.filter(\.isIngredient), id: \.self) { group in
                Label(group.displayName, systemImage: group.symbolName).tag(group)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

#if DEBUG
private enum IngredientReviewPreviewData {
    private static func recognisedItem(
        _ name: String,
        category: IngredientGroup,
        quantity: String,
        boundingBox: CGRect?
    ) -> IngredientReviewItem {
        IngredientReviewItem(
            origin: .recognised,
            recognised: FusedIngredient(
                ingredientId: name.lowercased(),
                displayName: name,
                category: category,
                tier: .agreed,
                sources: .detector,
                boundingBox: boundingBox,
                detectorConfidence: 0.91,
                assertsIngredient: true
            ),
            displayName: name,
            category: category,
            isAccepted: true,
            quantityText: quantity,
            unit: .pieces
        )
    }

    static func detectedAndSuggested() -> IngredientReviewViewModel {
        var milk = IngredientReviewItem(manualName: "Milk", category: .dairy)
        milk.quantityText = "1"
        return IngredientReviewViewModel(items: [
            recognisedItem(
                "Tomatoes",
                category: .vegetable,
                quantity: "4",
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.25)
            ),
            recognisedItem("Baby Spinach", category: .vegetable, quantity: "1", boundingBox: nil),
            milk
        ])
    }

    static func validationAndPartialFailure() -> IngredientReviewViewModel {
        let viewModel = IngredientReviewViewModel(items: [
            recognisedItem(
                "Tomatoes",
                category: .vegetable,
                quantity: "",
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.25)
            ),
            recognisedItem("Milk", category: .dairy, quantity: "1", boundingBox: nil)
        ])
        viewModel.presentPreviewSaveState(
            .partial(
                AddDetectedIngredientsSummary(
                    addedNames: ["Milk"],
                    duplicateNames: [],
                    failures: [.init(name: "Tomatoes", message: "Enter an amount before saving.")]
                )
            )
        )
        return viewModel
    }
}

#Preview("Ingredient Review — Detected and Suggested") {
    IngredientReviewView(
        viewModel: IngredientReviewPreviewData.detectedAndSuggested(),
        snapshot: UIImage(systemName: "photo")!
    )
}

#Preview("Ingredient Review — Validation and Partial Failure") {
    IngredientReviewView(
        viewModel: IngredientReviewPreviewData.validationAndPartialFailure(),
        snapshot: UIImage(systemName: "photo")!
    )
}
#endif
