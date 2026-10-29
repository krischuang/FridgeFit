//
//  DeleteAccountSheet.swift
//  FridgeFit
//

import SwiftUI

/// Profile → Settings → Delete Account.
///
/// ## Why the destructive tap is behind two deliberate steps
///
/// Opening this sheet deletes nothing. The button inside it opens a
/// confirmation dialog, and only that dialog's destructive action starts the
/// work. Two separate, differently-worded, differently-placed taps, with the
/// list of what will be destroyed on screen between them - which is what
/// makes an accidental deletion essentially impossible without making the
/// intentional one tedious.
///
/// The sheet also cannot be swiped away mid-deletion
/// (`interactiveDismissDisabled`), because a half-finished deletion the user
/// can no longer see is the state with the worst recovery story.
///
/// ## Why the copy is this specific about what is removed
///
/// "Your data will be deleted" is not something a user can check. The list
/// names the actual stores, and it is accurate: each line corresponds to a
/// conformer of `AccountDataDeleting` wired up in `AppDependencies`.
struct DeleteAccountSheet: View {
    @StateObject private var viewModel: DeleteAccountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirming = false
    @FocusState private var isPasswordFocused: Bool

    init(viewModel: @autoclosure @escaping () -> DeleteAccountViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.section) {
                    if viewModel.isFinished {
                        deletedState
                    } else {
                        header
                        whatGetsDeleted
                        if let prompt = viewModel.reauthenticationPrompt {
                            reauthentication(prompt: prompt)
                        }
                        if let error = viewModel.error {
                            errorBanner(error)
                        }
                        actions
                    }
                }
                .padding(FridgeFitTheme.Spacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(FridgeFitTheme.ColorToken.canvas.ignoresSafeArea())
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.isFinished ? "Done" : "Cancel") { dismiss() }
                        // Cancelling mid-deletion would hide a half-finished
                        // irreversible operation.
                        .disabled(viewModel.isDeleting)
                }
            }
            // Same reason: no swipe-to-dismiss while work is in flight.
            .interactiveDismissDisabled(viewModel.isDeleting)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                .font(FridgeFitTheme.Typography.sectionTitleProminent)
                .foregroundStyle(FridgeFitTheme.ColorToken.danger)

            Text(accountDescription)
                .font(FridgeFitTheme.Typography.body)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var accountDescription: String {
        if let email = viewModel.accountEmail {
            return """
                Deleting \(email) permanently removes your FridgeFit account and everything \
                in it. There is no way to restore it, and signing up again with the same \
                email starts an empty kitchen.
                """
        }
        return """
            Deleting your account permanently removes it and everything in it. There is no \
            way to restore it, and signing up again starts an empty kitchen.
            """
    }

    private var whatGetsDeleted: some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.medium) {
            Text("What gets deleted")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
                deletionLine("refrigerator", "Your pantry and every ingredient in it")
                deletionLine("clock.arrow.circlepath", "Your kitchen activity history")
                deletionLine("bookmark", "Recipes you saved from Discover")
                deletionLine("dollarsign.circle", "Your food budget, logged spends, waste records and saved prices")
                deletionLine("iphone.and.arrow.forward", "This account's paired camera devices")
                deletionLine("internaldrive", "FridgeFit's cached data and preferences on this device")
                deletionLine("person.crop.circle.badge.xmark", "Your sign-in itself")
            }
            .padding(FridgeFitTheme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fridgeFitCardSurface()
        }
    }

    private func deletionLine(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(FridgeFitTheme.ColorToken.danger)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reauthentication(prompt: String) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.small) {
            Text("Confirm it's you")
                .font(FridgeFitTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .textCase(.uppercase)

            Text(prompt)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Shown only when the account actually has a password. A
            // Google-only account never sees this field - see
            // `DeleteAccountViewModel.isAskingForPassword`.
            if viewModel.isAskingForPassword {
                // Styled inline rather than with `FridgeFitTextFieldStyle`:
                // that style's `_body` is declared over `TextField`, so a
                // `SecureField` does not reliably pick it up. Same tokens,
                // so it still matches every other field in the app.
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textPrimary)
                    .padding(.horizontal, FridgeFitTheme.Spacing.medium)
                    .frame(minHeight: 44)
                    .background(
                        FridgeFitTheme.ColorToken.card,
                        in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.control, style: .continuous)
                            .stroke(FridgeFitTheme.ColorToken.controlBorder, lineWidth: 1)
                    }
                    .focused($isPasswordFocused)
                    .submitLabel(.done)
                    .accessibilityLabel("Password, to confirm account deletion")
                    .onAppear { isPasswordFocused = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ error: DeleteAccountError) -> some View {
        VStack(alignment: .leading, spacing: FridgeFitTheme.Spacing.xSmall) {
            Text(error.localizedDescription)
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.errorText)
                .fixedSize(horizontal: false, vertical: true)

            // The one state where stopping is worse than continuing, so it
            // says so instead of leaving the user to work it out.
            if error.dataAlreadyDeleted {
                Text("Your kitchen data has already been removed. If you stop now, your sign-in will still work but your account will be empty.")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // "We don't know" is its own state, and the right next step is
            // to look again rather than to assume either outcome. Saying
            // "try again" here would invite a user whose deletion already
            // finished to retry something that is done.
            if case .deletionStatusUnknown = error {
                Text("Checking again is safe — it won't delete anything twice.")
                    .font(FridgeFitTheme.Typography.caption)
                    .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FridgeFitTheme.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            FridgeFitTheme.ColorToken.errorBackground,
            in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.card)
        )
        .accessibilityElement(children: .combine)
    }

    /// What the destructive button says, which depends on what already
    /// happened. Offering "Delete My Account" to someone whose data is
    /// already gone would misdescribe what the tap does.
    private var destructiveButtonTitle: String {
        guard let error = viewModel.error else { return "Delete My Account" }
        if case .deletionStatusUnknown = error { return "Check Again" }
        return error.dataAlreadyDeleted ? "Finish Deleting Account" : "Delete My Account"
    }

    private var actions: some View {
        VStack(spacing: FridgeFitTheme.Spacing.medium) {
            Button {
                isConfirming = true
            } label: {
                if viewModel.isDeleting {
                    HStack(spacing: FridgeFitTheme.Spacing.small) {
                        ProgressView().tint(.white)
                        Text("Deleting…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(destructiveButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            // Deliberately not `FridgeFitPrimaryButtonStyle`: that style
            // hard-codes the brand fill, so a destructive action would be
            // rendered in FridgeFit green. A destructive button has to read
            // as destructive, so the fill is the danger token.
            .buttonStyle(DestructiveFilledButtonStyle())
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("delete-account")
            .accessibilityHint("Opens a final confirmation. Deleting your account cannot be undone.")

            Button("Keep My Account") { dismiss() }
                .buttonStyle(FridgeFitSecondaryButtonStyle())
                .disabled(viewModel.isDeleting)
        }
        // The second deliberate step. The sheet's own button only gets here.
        .confirmationDialog(
            "Delete your FridgeFit account?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                isPasswordFocused = false
                Task { await viewModel.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your pantry, history, saved recipes, budget and sign-in will be permanently deleted. This cannot be undone.")
        }
    }

    private var deletedState: some View {
        VStack(spacing: FridgeFitTheme.Spacing.large) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(FridgeFitTheme.ColorToken.primary)
                .accessibilityHidden(true)

            Text("Your account has been deleted")
                .font(FridgeFitTheme.Typography.screenTitle)
                .multilineTextAlignment(.center)

            Text("Your FridgeFit data has been removed and you've been signed out on this device.")
                .font(FridgeFitTheme.Typography.supporting)
                .foregroundStyle(FridgeFitTheme.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, FridgeFitTheme.Spacing.screen)
        .accessibilityElement(children: .combine)
    }
}

/// Filled button treatment for an irreversible action.
///
/// Mirrors `FridgeFitPrimaryButtonStyle` - same typography, same 52pt
/// minimum height, so it stays above the 44pt touch target at every Dynamic
/// Type size - with the danger fill instead of the brand fill.
private struct DestructiveFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FridgeFitTheme.Typography.button)
            .foregroundStyle(isEnabled ? .white : FridgeFitTheme.ColorToken.disabledText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, FridgeFitTheme.Spacing.large)
            .background(
                isEnabled ? FridgeFitTheme.ColorToken.danger : FridgeFitTheme.ColorToken.disabledSurface,
                in: RoundedRectangle(cornerRadius: FridgeFitTheme.Radius.pill, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
