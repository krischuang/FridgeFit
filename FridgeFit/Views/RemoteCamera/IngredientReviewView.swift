//
//  IngredientReviewView.swift
//  FridgeFit
//

import SwiftUI

/// The review step: what recognition found, and what the user decides to keep.
///
/// Two lists, kept apart on purpose:
///
/// - **In the photo** - claims anchored to a measured region, shown with
///   their box on the thumbnail.
/// - **Suggested** - whole-image classifications, packaging text and manual
///   additions, which have no location.
///
/// A whole-image classification knows *what* is present, not *where*. Showing
/// it in the same list as a localised box, or drawing it on the thumbnail,
/// would assert a position nothing measured.
struct IngredientReviewView: View {

    @StateObject private var viewModel: IngredientReviewViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pantryRepository) private var pantryRepository

    private let snapshot: UIImage
    /// Called with what was stored, after a clean save.
    private let onConfirm: ([ConfirmedIngredient]) -> Void

    @State private var editingItem: IngredientReviewItem?
    @State private var isAddingManually = false
    @State private var highlightedItemId: UUID?

    init(
        analysis: SnapshotAnalysis,
        snapshot: UIImage,
        addIngredientsUseCase: AddDetectedIngredientsUseCase,
        onConfirm: @escaping ([ConfirmedIngredient]) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: IngredientReviewViewModel(
            analysis: analysis, addIngredientsUseCase: addIngredientsUseCase
        ))
        self.snapshot = snapshot
        self.onConfirm = onConfirm
    }

    /// For previews and tests.
    init(
        viewModel: IngredientReviewViewModel,
        snapshot: UIImage,
        onConfirm: @escaping ([ConfirmedIngredient]) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.snapshot = snapshot
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isEmpty {
                    emptyState
                } else {
                    reviewList
                }
            }
            .navigationTitle("Review Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.saveState.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.saveState.isSaving {
                        ProgressView()
                    } else {
                        Button("Save \(viewModel.acceptedCount)") {
                            Task { await save() }
                        }
                        .disabled(!viewModel.canSaveToPantry)
                        .accessibilityIdentifier("save-to-pantry")
                    }
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
        }
    }

    /// Saves, then closes only on a clean success.
    ///
    /// A partial result or a failure keeps the sheet open with the rows
    /// intact, so the user can read what happened and retry. Dismissing here
    /// would throw away the only record of what they chose.
    private func save() async {
        await viewModel.saveToPantry()
        if viewModel.saveState.allowsAutomaticDismissal {
            onConfirm(viewModel.confirmed ?? [])
            dismiss()
        }
    }

    // MARK: - Save result

    @ViewBuilder
    private var saveResultSection: some View {
        if let summary = viewModel.saveState.summary {
            Section {
                Text(summary.userMessage)
                    .font(.callout)

                if !summary.failures.isEmpty {
                    ForEach(summary.failures, id: \.name) { failure in
                        Label("\(failure.name): \(failure.message)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if viewModel.saveState.isRetryable {
                    Button {
                        Task { await viewModel.retrySave() }
                    } label: {
                        Label("Retry the ones that didn't save", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("retry-save")
                }

                Button("Dismiss") { viewModel.dismissSaveResult() }
                    .font(.caption)
            } header: {
                Text("Saved to pantry")
            }
        } else if let failure = viewModel.saveState.failureMessage {
            Section {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button {
                    Task { await viewModel.retrySave() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("retry-save")
                Button("Dismiss") { viewModel.dismissSaveResult() }
                    .font(.caption)
            } header: {
                Text("Couldn't save")
            }
        }
    }

    /// Explains a disabled Save button rather than leaving it inert.
    @ViewBuilder
    private var readinessSection: some View {
        let missing = viewModel.acceptedItemsMissingQuantity
        if !missing.isEmpty {
            Section {
                Label(
                    missing.count == 1
                        ? "\(missing[0].displayName) needs an amount before it can be saved."
                        : "\(missing.count) selected ingredients still need an amount.",
                    systemImage: "number"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } footer: {
                Text("""
                Recognition can see that something is there, not how much of \
                it. Nothing is stored with a quantity you didn't set.
                """)
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No ingredients recognised", systemImage: "questionmark.circle")
        } description: {
            Text("""
            Nothing in this photo matched an ingredient the models can \
            recognise. Meat, fish, cheese and eggs are known weak spots.
            """)
        } actions: {
            Button("Add One Manually") { isAddingManually = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - List

    /// Says which recognisers actually ran.
    ///
    /// Without this, a YOLO-only run is indistinguishable from a full hybrid
    /// run that happened to find no agreement - the rows look identical. The
    /// user would be told "one method only" on every row with no explanation
    /// of why the second method is missing.
    @ViewBuilder
    private var capabilitySection: some View {
        let outcome = viewModel.classification
        if let message = outcome.userMessage {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message)
                            .font(.callout.weight(.medium))
                        if outcome.isDetectorOnly {
                            Text("""
                            These results come from YOLO object detection only. \
                            Nothing has been cross-checked by a second method, \
                            so please review every row before saving.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: outcome.capability.isExpectedLimitation
                          ? "info.circle" : "exclamationmark.triangle.fill")
                }
                .foregroundStyle(outcome.capability.isExpectedLimitation ? Color.secondary : .orange)
            } header: {
                Text(outcome.isDetectorOnly ? "YOLO-only results" : "Recognition")
            }
            .accessibilityIdentifier("capability-notice")
        }
    }

    private var reviewList: some View {
        List {
            capabilitySection
            thumbnailSection

            if !viewModel.localisedItems.isEmpty {
                Section {
                    ForEach(viewModel.localisedItems) { item in
                        row(item)
                    }
                } header: {
                    Text("In the photo")
                } footer: {
                    Text("Found at a specific place in the image, shown above.")
                }
            }

            if !viewModel.unlocalisedItems.isEmpty {
                Section {
                    ForEach(viewModel.unlocalisedItems) { item in
                        row(item)
                    }
                } header: {
                    Text("Suggested")
                } footer: {
                    Text("""
                    Recognised in the picture as a whole, or added by you. \
                    These have no location, so they are not drawn on the photo.
                    """)
                }
            }

            readinessSection
            saveResultSection
            addSection
            if !viewModel.packagingLines.isEmpty { packagingSection }
            diagnosticsSection
        }
        .listStyle(.insetGrouped)
    }

    private var thumbnailSection: some View {
        Section {
            ZStack {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFit()
                GeometryReader { proxy in
                    ForEach(viewModel.localisedItems) { item in
                        if let box = item.boundingBox,
                           let rect = DetectionGeometry.rect(
                               for: box,
                               sourceSize: viewModel.sourceSize,
                               viewSize: proxy.size,
                               contentMode: .scaleAspectFit
                           ) {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    colour(for: item),
                                    lineWidth: highlightedItemId == item.id ? 4 : 2
                                )
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .opacity(item.isAccepted ? 1 : 0.35)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text("Dimmed boxes are ones you've rejected.")
        }
    }

    private func row(_ item: IngredientReviewItem) -> some View {
        IngredientReviewRow(
            item: item,
            onToggle: { viewModel.toggleAcceptance(item.id) },
            onEdit: { editingItem = item },
            onRemove: item.origin == .manual ? { viewModel.remove(item.id) } : nil,
            onQuantityChange: { viewModel.setQuantityText($0, for: item.id) },
            onUnitChange: { viewModel.setUnit($0, for: item.id) }
        )
        .onTapGesture { highlightedItemId = item.id }
    }

    private var addSection: some View {
        Section {
            Button {
                isAddingManually = true
            } label: {
                Label("Add a missed ingredient", systemImage: "plus.circle")
            }

            HStack {
                Button("Accept all") { viewModel.acceptAll() }
                Spacer()
                Button("Reject all", role: .destructive) { viewModel.rejectAll() }
            }
            .font(.subheadline)
        }
    }

    private var packagingSection: some View {
        Section {
            DisclosureGroup("Packaging text (\(viewModel.packagingLines.count) lines)") {
                ForEach(Array(viewModel.packagingLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("""
            Read from packaging in the photo. It isn't matched to ingredients \
            automatically - that proved unreliable - so it's here for you to \
            read\(viewModel.nonLatinPackagingLines.isEmpty ? "" :
            ", and \(viewModel.nonLatinPackagingLines.count) line(s) aren't in a Latin script").
            """)
        }
    }

    private var diagnosticsSection: some View {
        Section {
            DisclosureGroup("Details") {
                LabeledContent("Agreed", value: "\(viewModel.count(of: .agreed))")
                LabeledContent("One method only", value: "\(viewModel.count(of: .singleSource))")
                LabeledContent("Disagreed", value: "\(viewModel.count(of: .conflicting))")
                LabeledContent("Analysis time",
                               value: String(format: "%.2fs", viewModel.analysisDuration))
                if !viewModel.rejectedFoodClaims.isEmpty {
                    LabeledContent("Discarded guesses",
                                   value: viewModel.rejectedFoodClaims.joined(separator: ", "))
                    .font(.caption)
                }
            }
        } footer: {
            Text("Nothing is saved to your pantry. Confirming keeps these on this screen only.")
        }
    }

    private func colour(for item: IngredientReviewItem) -> Color {
        switch item.tier {
        case .agreed: return .green
        case .conflicting: return .orange
        default: return .yellow
        }
    }
}

// MARK: - Row

struct IngredientReviewRow: View {
    let item: IngredientReviewItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRemove: (() -> Void)?
    let onQuantityChange: (String) -> Void
    let onUnitChange: (MeasurementUnit) -> Void

    /// Local mirror so typing stays responsive; pushed up on every change.
    @State private var quantityText: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isAccepted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isAccepted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isAccepted ? "Accepted" : "Rejected")
            .accessibilityIdentifier("toggle-\(item.id.uuidString)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.body.weight(.medium))
                    if item.wasEdited {
                        Text("edited")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Label(item.category.displayName, systemImage: item.category.symbolName)
                    if let confidence = item.confidence {
                        Text("· \(Int((confidence * 100).rounded()))%")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let tier = item.tier {
                    Label(tier.displayName, systemImage: tier.symbolName)
                        .font(.caption2)
                        .foregroundStyle(tierColour(tier))
                } else if item.origin == .manual {
                    Label("Added by you", systemImage: "hand.raised")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let other = item.conflictingClaim {
                    Text("The other method said “\(other)”")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let reason = item.reviewReason {
                    Text(reason.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !item.sources.displayNames.isEmpty {
                    Text(item.sources.displayNames.joined(separator: " + "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Only asked for once the user has said they want the item.
                // An amount field on a row they are about to reject is noise.
                if item.isAccepted {
                    HStack(spacing: 8) {
                        TextField("Amount", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .accessibilityIdentifier("quantity-\(item.id.uuidString)")
                            .onChange(of: quantityText) { _, new in onQuantityChange(new) }

                        Picker("Unit", selection: Binding(
                            get: { item.unit },
                            set: onUnitChange
                        )) {
                            ForEach(MeasurementUnit.allCases) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        if !item.hasValidQuantity {
                            Text("needed")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .onAppear { quantityText = item.quantityText }

            Spacer(minLength: 0)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(item.displayName)")
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            if let onRemove {
                Button("Delete", systemImage: "trash", role: .destructive, action: onRemove)
            }
        }
    }

    private func tierColour(_ tier: ConfidenceTier) -> Color {
        switch tier {
        case .agreed: return .green
        case .singleSource: return .secondary
        case .conflicting: return .orange
        }
    }
}

// MARK: - Editing

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

/// Category chooser. `.decoy` is an internal vocabulary device and is never
/// offered.
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
