//
//  PantryPresentation.swift
//  FridgeFit
//

import SwiftUI

extension IngredientCategory {
    /// Just for giving pantry rows a recognisable colour.
    var tint: Color {
        switch self {
        case .produce: return .green
        case .dairy: return .blue
        case .meat: return .red
        case .grain: return .brown
        case .spice: return .orange
        case .other: return .gray
        }
    }
}

/// A small icon in a tinted circle, used for category icons on pantry rows.
struct IconBadge: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

/// An inline error message with an icon and tinted background, used
/// instead of plain red text in the Pantry forms.
struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
