//
//  YOLODetectionOverlay.swift
//  FridgeFit
//

import SwiftUI

/// Ingredient bounding boxes drawn over the live WebRTC video.
///
/// Positions come from `DetectionGeometry`, which maps Vision's normalised,
/// bottom-left-origin boxes through the `.scaleAspectFill` crop the video is
/// rendered with. Boxes are *not* scaled onto the view's bounds directly -
/// that only lines up when the video and the view share an aspect ratio,
/// which they generally don't.
///
/// What it draws is `DetectedIngredient`, not raw model output: decoy terms
/// are already gone, ambiguous classes already genericised, and anything the
/// model is unsure about is marked with a `?` rather than presented as fact.
///
/// Draws nothing when there is nothing to draw, and never intercepts touches.
struct YOLODetectionOverlay: View {
    let detections: IngredientDetectionFrame
    var contentMode: DetectionGeometry.VideoContentMode = .scaleAspectFill

    var body: some View {
        GeometryReader { proxy in
            let viewSize = proxy.size
            ZStack(alignment: .topLeading) {
                ForEach(detections.ingredients) { ingredient in
                    if let rect = DetectionGeometry.rect(
                        for: ingredient.boundingBox,
                        sourceSize: detections.sourceSize,
                        viewSize: viewSize,
                        contentMode: contentMode
                    ) {
                        IngredientBox(
                            ingredient: ingredient,
                            rect: DetectionGeometry.clamped(rect, to: viewSize)
                        )
                    }
                }
            }
            .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        }
        // Detections update a few times a second; without this they would
        // snap between positions. Short enough not to lag the object.
        .animation(.easeOut(duration: 0.15), value: detections)
        // The overlay sits on top of the video and must not swallow taps
        // meant for the controls.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One box plus its label.
private struct IngredientBox: View {
    let ingredient: DetectedIngredient
    let rect: CGRect

    /// Colour carries the category, so a glance says "fruit" vs "meat"
    /// without reading every label. Amber overrides it for anything the user
    /// needs to confirm - uncertainty outranks category.
    private var tint: Color {
        if ingredient.requiresReview { return .orange }
        switch ingredient.category {
        case .fruit: return .green
        case .vegetable: return .mint
        case .meat: return .pink
        case .seafood: return .cyan
        case .dairy: return .yellow
        case .pantry: return .purple
        case .decoy: return .gray
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(tint, style: StrokeStyle(
                    lineWidth: 2,
                    // Dashed for anything unconfirmed, so uncertainty is
                    // visible even in a screenshot.
                    dash: ingredient.requiresReview ? [5, 3] : []
                ))
                .frame(width: rect.width, height: rect.height)

            HStack(spacing: 3) {
                Image(systemName: ingredient.category.symbolName)
                    .font(.system(size: 8, weight: .bold))
                Text(ingredient.overlayLabel)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint, in: RoundedRectangle(cornerRadius: 3))
            // Above the box, or inside it when the box is at the very top of
            // the view and there is no room.
            .offset(y: rect.minY >= 16 ? -16 : 2)
            .fixedSize()
        }
        .offset(x: rect.minX, y: rect.minY)
    }
}

#Preview {
    // Portrait 720x1280 video in a landscape-ish view, to show the
    // aspect-fill crop being accounted for rather than boxes being stretched.
    let frame = IngredientDetectionFrame(
        ingredients: [
            DetectedIngredient(
                ingredientId: "banana", displayName: "Banana", category: .fruit,
                confidence: 0.91, boundingBox: CGRect(x: 0.15, y: 0.55, width: 0.35, height: 0.2),
                source: .ingredientDetector, reviewReason: nil, rawTerm: "banana"
            ),
            DetectedIngredient(
                ingredientId: "red_meat", displayName: "Red Meat", category: .meat,
                confidence: 0.48, boundingBox: CGRect(x: 0.55, y: 0.2, width: 0.25, height: 0.25),
                source: .ingredientDetector, reviewReason: .ambiguousClass, rawTerm: "raw beef steak"
            ),
        ],
        sourceSize: CGSize(width: 720, height: 1280),
        source: .ingredientDetector
    )
    return ZStack {
        Color.black
        YOLODetectionOverlay(detections: frame)
    }
    .frame(width: 360, height: 480)
}
