//
//  NumericKeyboardToolbar.swift
//  FridgeFit
//

import SwiftUI
import UIKit

extension View {
    /// Puts a Done button in the bar above the keyboard.
    ///
    /// Every quantity and price field in the app uses `.decimalPad` or
    /// `.numberPad`, and neither has a Return key. `onSubmit` never fires and
    /// `submitLabel` has nothing to label, so without this a numeric field
    /// inside a sheet can leave the keyboard sitting over the Save button
    /// with no affordance for putting it away. Text fields elsewhere already
    /// have the keyboard's own Return key, and the auth screens and search
    /// field pair that with `scrollDismissesKeyboard`.
    ///
    /// Applied once per screen, not once per field: SwiftUI merges the
    /// toolbars it finds in a hierarchy, so two numeric fields each carrying
    /// their own would contribute two Done buttons to the same bar.
    func numericKeyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { KeyboardDismissal.dismissNow() }
                    .accessibilityHint("Dismisses the number pad")
            }
        }
    }
}

enum KeyboardDismissal {
    /// Resigns whatever currently holds first responder.
    ///
    /// Deliberately not routed through `@FocusState`: that would need a focus
    /// binding declared in every screen with a numeric field, and threaded
    /// into each one, to do a job that does not depend on which field is
    /// focused.
    @MainActor
    static func dismissNow() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
