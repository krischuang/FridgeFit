//
//  FridgeFitColorTokenTests.swift
//  FridgeFitTests
//

import SwiftUI
import UIKit
import XCTest
@testable import FridgeFit

final class FridgeFitColorTokenTests: XCTestCase {
    func testApprovedCorePaletteResolvesInLightAndDarkAppearances() {
        assertHex(FridgeFitTheme.ColorToken.canvas, light: 0xF7F5EC, dark: 0x202821)
        assertHex(FridgeFitTheme.ColorToken.secondaryBackground, light: 0xEEF1E9, dark: 0x253027)
        assertHex(FridgeFitTheme.ColorToken.card, light: 0xFFFFFF, dark: 0x2A342E)
        assertHex(FridgeFitTheme.ColorToken.primary, light: 0x356B52, dark: 0x8FC59B)
        assertHex(FridgeFitTheme.ColorToken.brandFill, light: 0x356B52, dark: 0x3C7056)
        assertHex(FridgeFitTheme.ColorToken.textPrimary, light: 0x26352C, dark: 0xF1F4EF)
        assertHex(FridgeFitTheme.ColorToken.textSecondary, light: 0x637064, dark: 0xB9C3B9)
    }

    func testMeaningfulTextPairsMeetNormalTextContrast() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(FridgeFitTheme.ColorToken.textPrimary, on: FridgeFitTheme.ColorToken.canvas, style: style, minimum: 4.5)
            assertContrast(FridgeFitTheme.ColorToken.textSecondary, on: FridgeFitTheme.ColorToken.card, style: style, minimum: 4.5)
            assertContrast(FridgeFitTheme.ColorToken.disabledText, on: FridgeFitTheme.ColorToken.disabledSurface, style: style, minimum: 4.5)
            assertContrast(FridgeFitTheme.ColorToken.errorText, on: FridgeFitTheme.ColorToken.errorBackground, style: style, minimum: 4.5)
            assertContrast(.white, on: FridgeFitTheme.ColorToken.brandFill, style: style, minimum: 4.5)
        }
    }

    func testAuthenticationErrorBannerUsesAccessibleSemanticColors() {
        assertHex(AuthMessageBanner.Tone.error.foreground, light: 0xB43C31, dark: 0xFF9C8C)
        assertHex(AuthMessageBanner.Tone.error.background, light: 0xFCEBE7, dark: 0x453B34)

        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(
                AuthMessageBanner.Tone.error.foreground,
                on: AuthMessageBanner.Tone.error.background,
                style: style,
                minimum: 4.5
            )
        }
    }

    func testControlBordersMeetNonTextContrast() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            assertContrast(FridgeFitTheme.ColorToken.controlBorder, on: FridgeFitTheme.ColorToken.card, style: style, minimum: 3)
            assertContrast(FridgeFitTheme.ColorToken.controlBorder, on: FridgeFitTheme.ColorToken.canvas, style: style, minimum: 3)
        }
    }

    func testKitchenStatusLabelsRemainReadableOnTintedCardBackgrounds() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for status in [KitchenTheme.urgent, KitchenTheme.soon, KitchenTheme.low] {
                let foreground = resolved(status, style: style)
                let card = resolved(FridgeFitTheme.ColorToken.card, style: style)
                let tintedBackground = composite(foreground, alpha: 0.12, over: card)
                XCTAssertGreaterThanOrEqual(contrast(foreground, tintedBackground), 4.5)
            }
        }
    }

    private func assertHex(_ color: Color, light: UInt32, dark: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(hex(resolved(color, style: .light)), light, file: file, line: line)
        XCTAssertEqual(hex(resolved(color, style: .dark)), dark, file: file, line: line)
    }

    private func assertContrast(_ foreground: Color, on background: Color, style: UIUserInterfaceStyle, minimum: Double, file: StaticString = #filePath, line: UInt = #line) {
        let ratio = contrast(resolved(foreground, style: style), resolved(background, style: style))
        XCTAssertGreaterThanOrEqual(ratio, minimum, "Contrast was \(ratio):1 in \(style == .dark ? "Dark" : "Light") Mode", file: file, line: line)
    }

    private func resolved(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func components(_ color: UIColor) -> (red: Double, green: Double, blue: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (Double(red), Double(green), Double(blue))
    }

    private func hex(_ color: UIColor) -> UInt32 {
        let value = components(color)
        return UInt32((value.red * 255).rounded()) << 16
            | UInt32((value.green * 255).rounded()) << 8
            | UInt32((value.blue * 255).rounded())
    }

    private func composite(_ foreground: UIColor, alpha: Double, over background: UIColor) -> UIColor {
        let front = components(foreground)
        let back = components(background)
        return UIColor(
            red: front.red * alpha + back.red * (1 - alpha),
            green: front.green * alpha + back.green * (1 - alpha),
            blue: front.blue * alpha + back.blue * (1 - alpha),
            alpha: 1
        )
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: UIColor) -> Double {
        let value = components(color)
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(value.red) + 0.7152 * linear(value.green) + 0.0722 * linear(value.blue)
    }
}

@MainActor
final class AuthAccessibilityRenderingTests: XCTestCase {
    func testAuthenticationFieldPreservesMinimumHeightAndExpandsAtAccessibility3() {
        let defaultHeight = fieldHeight(dynamicTypeSize: .large)
        let accessibilityHeight = fieldHeight(dynamicTypeSize: .accessibility3)

        XCTAssertGreaterThanOrEqual(defaultHeight, 52)
        XCTAssertGreaterThan(accessibilityHeight, defaultHeight)
    }

    func testLoginRendersAtDefaultDynamicType() {
        assertRenders(LoginView().environmentObject(AuthViewModel(observesAuthState: false)))
    }

    func testLoginRendersAtAccessibility3DynamicType() {
        assertRenders(
            LoginView()
                .environmentObject(AuthViewModel(observesAuthState: false))
                .environment(\.dynamicTypeSize, .accessibility3)
        )
    }

    func testRegistrationRendersAtDefaultDynamicType() {
        assertRenders(RegisterView().environmentObject(AuthViewModel(observesAuthState: false)))
    }

    func testRegistrationRendersAtAccessibility3DynamicType() {
        assertRenders(
            RegisterView()
                .environmentObject(AuthViewModel(observesAuthState: false))
                .environment(\.dynamicTypeSize, .accessibility3)
        )
    }

    private func fieldHeight(dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let field = AuthField(label: "Email Address", systemImage: "envelope", isFocused: false) {
            TextField("", text: .constant(""), prompt: AuthFieldPrompt.text("alex@fridgefit.app"))
        }
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .fixedSize(horizontal: false, vertical: true)

        let controller = UIHostingController(rootView: field)
        return controller.sizeThatFits(in: CGSize(width: 350, height: CGFloat.greatestFiniteMagnitude)).height
    }

    private func assertRenders(
        _ view: some View,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let size = CGSize(width: 393, height: 852)
        let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        XCTAssertGreaterThan(image.size.width, 0, file: file, line: line)
        XCTAssertGreaterThan(image.size.height, 0, file: file, line: line)
    }
}
