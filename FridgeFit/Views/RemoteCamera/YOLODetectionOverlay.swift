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
/// ## What it is handed
///
/// Stage 3 output: `DetectionDisplayFilter` has already applied the display
/// threshold, the per-ingredient box budget and the frame budget, so this view
/// draws everything it is given and makes no filtering decisions of its own.
/// Decoy terms never reach it, having been dropped a stage earlier.
///
/// ## What it refuses to imply
///
/// Nothing here is presented as verified. A confident detection gets a solid
/// stroke rather than a dashed one, which says the model is sure - not that it
/// is right. On the evaluation set the most confident detection across all 11
/// images is wrong, so the caption states the live boxes are unconfirmed
/// regardless of how high the numbers are. Confirmation happens in the review
/// sheet, against a photo, with a second method's opinion available.
///
/// Draws nothing when there is nothing to draw, and never intercepts touches.
struct YOLODetectionOverlay: View {
    let detections: IngredientDetectionFrame
    var contentMode: DetectionGeometry.VideoContentMode = .scaleAspectFill
    /// Whether to show the "nothing reliable" caption when the frame is empty.
    ///
    /// Off for the still-photo thumbnail, which has its own empty state and
    /// does not need a second one layered over it.
    var showsEmptyState: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let viewSize = proxy.size
            let placed = Self.placedBoxes(
                for: detections, viewSize: viewSize, contentMode: contentMode
            )
            ZStack(alignment: .topLeading) {
                ForEach(placed) { box in
                    IngredientBox(
                        ingredient: box.ingredient,
                        rect: box.rect,
                        labelBelow: box.labelBelow
                    )
                }
            }
            .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if showsEmptyState && placed.isEmpty {
                    EmptyDetectionCaption()
                } else if !placed.isEmpty {
                    UnconfirmedCaption(count: placed.count)
                }
            }
        }
        // Detections update a few times a second; without this they would
        // snap between positions. Short enough not to lag the object.
        .animation(.easeOut(duration: 0.15), value: detections)
        // The overlay sits on top of the video and must not swallow taps
        // meant for the controls.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Layout

    /// One box, positioned, with its label placement already decided.
    struct PlacedBox: Identifiable {
        let ingredient: DetectedIngredient
        let rect: CGRect
        /// Label sits inside the top of the box rather than above it.
        let labelBelow: Bool
        var id: UUID { ingredient.id }
    }

    /// Maps detections onto the view and resolves label collisions.
    ///
    /// Labels default to sitting just above their box. Two boxes whose tops
    /// are close put their captions on top of each other, which is unreadable
    /// and - worse - ambiguous about which box a name belongs to. When that
    /// would happen the lower-priority label moves inside its own box instead,
    /// which is always unambiguous even if it is tighter.
    ///
    /// Boxes come in confidence order, so the one that keeps the roomier
    /// position is the one the user is most likely to care about.
    static func placedBoxes(
        for frame: IngredientDetectionFrame,
        viewSize: CGSize,
        contentMode: DetectionGeometry.VideoContentMode
    ) -> [PlacedBox] {
        /// Label height plus a little slack, in points.
        let labelHeight: CGFloat = 18
        /// Horizontal distance below which two labels are treated as being in
        /// the same column and therefore able to collide.
        let columnTolerance: CGFloat = 120

        var placed: [PlacedBox] = []
        var takenLabelAnchors: [CGPoint] = []

        for ingredient in frame.ingredients {
            guard let mapped = DetectionGeometry.rect(
                for: ingredient.boundingBox,
                sourceSize: frame.sourceSize,
                viewSize: viewSize,
                contentMode: contentMode
            ) else { continue }
            let rect = DetectionGeometry.clamped(mapped, to: viewSize)

            // No room above the box at all - the label has to go inside.
            var below = rect.minY < labelHeight
            if !below {
                let anchor = CGPoint(x: rect.minX, y: rect.minY - labelHeight)
                let collides = takenLabelAnchors.contains { taken in
                    abs(taken.y - anchor.y) < labelHeight
                        && abs(taken.x - anchor.x) < columnTolerance
                }
                if collides { below = true }
            }
            if !below {
                takenLabelAnchors.append(CGPoint(x: rect.minX, y: rect.minY - labelHeight))
            }
            placed.append(PlacedBox(ingredient: ingredient, rect: rect, labelBelow: below))
        }
        return placed
    }
}

/// Shown when the filter passed nothing through.
///
/// Deliberately quiet, and deliberately specific: "nothing reliable" is a
/// different claim from "nothing there", and the model's weak guesses are
/// being withheld rather than having not existed. Drawing them instead would
/// make the overlay busier and less true at the same time.
private struct EmptyDetectionCaption: View {
    var body: some View {
        Text("No reliable ingredients detected")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.bottom, 10)
            .accessibilityIdentifier("no-reliable-detections")
    }
}

/// Standing reminder that live boxes are candidates.
private struct UnconfirmedCaption: View {
    let count: Int

    var body: some View {
        Text("\(count) unconfirmed · capture a photo to review")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(.bottom, 10)
            .accessibilityIdentifier("unconfirmed-detections")
    }
}

/// One box plus its label.
private struct IngredientBox: View {
    let ingredient: DetectedIngredient
    let rect: CGRect
    let labelBelow: Bool

    /// Colour carries the category, so a glance says "fruit" vs "meat"
    /// without reading every label. Amber overrides it for anything with a
    /// specific review flag - a named doubt outranks category.
    private var tint: Color {
        if ingredient.hasReviewFlag { return .orange }
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

    /// Dashed for the tentative band or a flagged candidate, so uncertainty is
    /// visible even in a screenshot. Solid means the detector is confident,
    /// which is not the same as correct - see the overlay's caption.
    private var dash: [CGFloat] {
        (ingredient.band.isDashed || ingredient.hasReviewFlag) ? [5, 3] : []
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, dash: dash))
                .frame(width: rect.width, height: rect.height)

            HStack(spacing: 3) {
                Image(systemName: ingredient.category.symbolName)
                    // Matches the label beside it so the two scale together
                    // instead of the glyph staying 8pt while the text grows.
                    .font(.caption2.weight(.bold))
                Text(ingredient.overlayLabel)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint, in: RoundedRectangle(cornerRadius: 3))
            // Above the box normally; inside it when there is no room or when
            // another label already owns that spot.
            .offset(y: labelBelow ? 2 : -16)
            .fixedSize()
        }
        .offset(x: rect.minX, y: rect.minY)
    }
}

#Preview("Detections") {
    // Portrait 720x1280 video in a landscape-ish view, to show the
    // aspect-fill crop being accounted for rather than boxes being stretched.
    let frame = IngredientDetectionFrame(
        ingredients: [
            DetectedIngredient(
                ingredientId: "banana", displayName: "Banana", category: .fruit,
                confidence: 0.91, boundingBox: CGRect(x: 0.15, y: 0.55, width: 0.35, height: 0.2),
                source: .ingredientDetector, reviewReason: nil, rawTerm: "banana", band: .strong
            ),
            DetectedIngredient(
                ingredientId: "red_meat", displayName: "Red Meat", category: .meat,
                confidence: 0.48, boundingBox: CGRect(x: 0.55, y: 0.2, width: 0.25, height: 0.25),
                source: .ingredientDetector, reviewReason: .ambiguousClass,
                rawTerm: "raw beef steak", band: .tentative
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

#Preview("Nothing reliable") {
    ZStack {
        Color.black
        YOLODetectionOverlay(
            detections: IngredientDetectionFrame(
                ingredients: [],
                sourceSize: CGSize(width: 720, height: 1280),
                source: .ingredientDetector
            )
        )
    }
    .frame(width: 360, height: 480)
}
