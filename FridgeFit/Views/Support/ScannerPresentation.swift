//
//  ScannerPresentation.swift
//  FridgeFit
//

import SwiftUI

// A confidence badge used to live here, showing the model's self-reported
// "Low / Medium / High confidence" for each detection. It was removed with
// the fridge-photo scanner: it was the model's own coarse self-assessment
// rather than a measurement of anything, it had no defensible meaning, and
// it gave the user nothing to act on. The receipt confirmation screen shows
// the receipt line an item came from instead, which is evidence the user
// can actually check.

/// A short explanatory note in a tinted card, used for the privacy note and
/// the "already in your pantry" warning - the same shape as
/// `InlineErrorBanner` but for information rather than failure.
struct InlineInfoBanner: View {
    let message: String
    var systemImage: String = "info.circle.fill"
    var tint: Color = .accentColor

    var body: some View {
        Label {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
