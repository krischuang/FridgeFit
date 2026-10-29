//
//  DynamicTypeLayoutTests.swift
//  FridgeFitTests
//

@testable import FridgeFit
import SwiftUI
import UIKit
import XCTest

/// Controls have to grow with the user's text size instead of clipping it.
///
/// The failure these guard against is `.frame(height:)` on something holding
/// text: it looks right at the default size and cuts the label in half at the
/// accessibility sizes. `minHeight` keeps the 44pt touch target without
/// capping the label, and that is the distinction measured here - a fixed box
/// reports the same height at every text size, so a test that asserts growth
/// fails the moment one comes back.
@MainActor
final class DynamicTypeLayoutTests: XCTestCase {

    /// A phone-width column. Narrow enough that long labels have to wrap,
    /// which is where clipping shows up first.
    private let width: CGFloat = 320

    // MARK: - Touch targets at the default text size

    func test_primaryButtonMeetsTheMinimumTouchTarget() {
        let height = fittingHeight(of: primaryButton, at: .large)

        XCTAssertGreaterThanOrEqual(height, 44, "HIG minimum is 44pt.")
    }

    func test_secondaryButtonMeetsTheMinimumTouchTarget() {
        XCTAssertGreaterThanOrEqual(fittingHeight(of: secondaryButton, at: .large), 44)
    }

    func test_chipMeetsTheMinimumTouchTarget() {
        XCTAssertGreaterThanOrEqual(fittingHeight(of: chip, at: .large), 44)
    }

    // MARK: - Growth at the accessibility sizes

    func test_primaryButtonGrowsWithTheTextItContains() {
        assertGrowsWithTextSize(primaryButton)
    }

    func test_secondaryButtonGrowsWithTheTextItContains() {
        assertGrowsWithTextSize(secondaryButton)
    }

    func test_chipGrowsWithTheTextItContains() {
        assertGrowsWithTextSize(chip)
    }

    /// The card surface wraps most of the app's content, so a fixed height
    /// here would clip whatever is inside it on every screen at once.
    func test_cardSurfaceGrowsWithTheTextItContains() {
        assertGrowsWithTextSize(
            Text("Two cucumbers expire tomorrow, and the yoghurt the day after.")
                .font(FridgeFitTheme.Typography.body)
                .fridgeFitCardSurface()
        )
    }

    /// Every size step from the default up to the largest, so the growth is
    /// monotonic rather than only correct at the two ends.
    func test_heightNeverShrinksAsTextGrows() {
        let sizes: [DynamicTypeSize] = [
            .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3,
            .accessibility4, .accessibility5
        ]

        var previous: CGFloat = 0
        for size in sizes {
            let height = fittingHeight(of: primaryButton, at: size)
            XCTAssertGreaterThanOrEqual(
                height, previous,
                "The button shrank going from the previous size to \(size)."
            )
            previous = height
        }
    }

    // MARK: - Fixtures

    private var primaryButton: some View {
        Button("Add to My Fridge") {}
            .buttonStyle(FridgeFitPrimaryButtonStyle())
    }

    private var secondaryButton: some View {
        Button("Choose a photo from your library") {}
            .buttonStyle(FridgeFitSecondaryButtonStyle())
    }

    private var chip: some View {
        Button("Expiring first") {}
            .buttonStyle(FridgeFitChipStyle(isSelected: false))
    }

    // MARK: - Measurement

    private func assertGrowsWithTextSize(
        _ view: some View,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let standard = fittingHeight(of: view, at: .large)
        let accessible = fittingHeight(of: view, at: .accessibility5)

        XCTAssertGreaterThan(
            accessible, standard,
            """
            Height is \(accessible)pt at accessibility5 and \(standard)pt at \
            the default size. A control that does not grow is capping its \
            label, which clips it.
            """,
            file: file,
            line: line
        )
    }

    /// The height the view asks for at `size`, given a fixed width.
    private func fittingHeight(of view: some View, at size: DynamicTypeSize) -> CGFloat {
        let controller = UIHostingController(
            rootView: view
                .environment(\.dynamicTypeSize, size)
                .frame(width: width)
        )
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        return controller.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
    }
}
