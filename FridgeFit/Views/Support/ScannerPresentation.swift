//
//  ScannerPresentation.swift
//  FridgeFit
//

import SwiftUI

extension ModelStatedConfidence {
    /// Warm for confident, cooler as the model gets less sure. Paired with
    /// `label` text everywhere it's used, so colour is never the only thing
    /// carrying the meaning.
    var tint: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .high: return "checkmark.seal.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        }
    }
}

/// The model's self-reported confidence in a detection, as a small caption
/// under the ingredient name.
struct ConfidenceBadge: View {
    let confidence: ModelStatedConfidence

    var body: some View {
        Label {
            Text(confidence.label)
        } icon: {
            Image(systemName: confidence.symbolName)
        }
        .font(.caption)
        .foregroundStyle(confidence.tint)
    }
}

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
