//
//  ScreenshotCaptureUITests.swift
//  FridgeFitUITests
//
//  TEMPORARY, throwaway automation written for Assessment 4 App Store
//  screenshot capture. Drives the real running app through its existing
//  navigation and add-ingredient flows and writes PNGs straight to
//  Assessment4ScreenshotCapture/raw/. Not part of the product's permanent
//  test suite — safe to delete once screenshots are captured.
//

import XCTest

final class ScreenshotCaptureUITests: XCTestCase {

    private let outputDir = "/Users/kai/Desktop/2026 Spring/Advanced iOS/FridgeFit/Assessment4ScreenshotCapture/raw"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 25)
        Thread.sleep(forTimeInterval: 3)

        capture(app, "01_Home_Dashboard_Light")

        tapTab(app, "My Fridge")
        Thread.sleep(forTimeInterval: 1.5)
        seedPantry(app)
        Thread.sleep(forTimeInterval: 1)
        capture(app, "02_Pantry_Inventory_Light")

        let smartScanButton = app.buttons["Smart Scan"]
        if tapWhenReady(smartScanButton, timeout: 5) {
            Thread.sleep(forTimeInterval: 1.5)
            capture(app, "03_Smart_Scan_Light")
            _ = tapWhenReady(app.buttons["Close Smart Scan"], timeout: 4)
            Thread.sleep(forTimeInterval: 1.5)
        }

        tapTab(app, "Discover")
        Thread.sleep(forTimeInterval: 1.5)
        _ = tapWhenReady(app.buttons["Find new recipes"], timeout: 4)
        Thread.sleep(forTimeInterval: 6)
        capture(app, "04_Discover_Recipes_Light")

        tapTab(app, "Recipes")
        Thread.sleep(forTimeInterval: 1.5)
        _ = tapWhenReady(app.buttons["Find My Recipes"], timeout: 4)
        Thread.sleep(forTimeInterval: 3)
        capture(app, "05_Saved_Recipe_Availability_Light")

        tapTab(app, "Home")
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "06_AI_Pantry_Ideas_Light")

        tapTab(app, "Profile")
        Thread.sleep(forTimeInterval: 1)
        let connectedDevicesPredicate = NSPredicate(format: "label CONTAINS[c] %@", "Connected Devices")
        let connectedDevicesRow = app.buttons.matching(connectedDevicesPredicate).firstMatch
        if tapWhenReady(connectedDevicesRow, timeout: 5) {
            Thread.sleep(forTimeInterval: 1.5)
            capture(app, "08_Camera_Mode_Optional")
        }

        tapTab(app, "My Fridge")
        Thread.sleep(forTimeInterval: 1)
    }

    /// Run separately after `xcrun simctl ui <udid> appearance dark`, with a
    /// fresh `app.launch()` so the new system appearance is actually picked
    /// up (an already-running process can stay on the old scheme).
    func testCaptureDarkModeScreenshot() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 25)
        Thread.sleep(forTimeInterval: 2)

        tapTab(app, "My Fridge")
        Thread.sleep(forTimeInterval: 2)
        capture(app, "07_Pantry_Dark_Mode")
    }

    // MARK: - Helpers

    /// Polls `exists && isHittable` instead of relying on XCUITest's brief
    /// built-in retry window, which is too short to survive a sheet-dismiss
    /// animation (observed causing spurious "not hittable" hard failures).
    @discardableResult
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                element.tap()
                return true
            }
            usleep(250_000)
        }
        return false
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        tapWhenReady(app.tabBars.buttons[name], timeout: 6)
    }

    private func seedPantry(_ app: XCUIApplication) {
        let templates = [
            "Eggs", "Milk", "Chicken Breast", "Tomato",
            "Spinach", "Cheddar Cheese", "Rice", "Frozen Peas",
        ]
        for name in templates {
            addTemplate(app, name)
        }
    }

    private func addTemplate(_ app: XCUIApplication, _ name: String) {
        guard tapWhenReady(app.buttons["Add ingredient"], timeout: 10) else { return }

        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", name)
        let tile = app.buttons.matching(predicate).firstMatch
        guard tapWhenReady(tile, timeout: 8) else {
            _ = tapWhenReady(app.navigationBars.buttons["Cancel"], timeout: 2)
            return
        }
        Thread.sleep(forTimeInterval: 1.0)

        // Already-in-pantry detection is a real async Firestore round-trip,
        // so give it a generous window rather than checking once. Cancel out
        // immediately if seen — do NOT fall through to "Add to Pantry": that
        // re-triggers the same duplicate error and leaves the sheet stuck
        // open for the rest of the run (this hung the entire test 3 times
        // before this fix).
        if pollsForDuplicate(app, timeout: 8) {
            _ = tapWhenReady(app.navigationBars.buttons["Cancel"], timeout: 3)
            Thread.sleep(forTimeInterval: 0.8)
            return
        }

        if tapWhenReady(app.buttons["Add to Pantry"], timeout: 6) {
            // Safety net: our own tap may be what surfaces a duplicate error
            // that hadn't shown up yet. If so, cancel rather than leaving a
            // stuck sheet for the rest of the run.
            if pollsForDuplicate(app, timeout: 3) {
                _ = tapWhenReady(app.navigationBars.buttons["Cancel"], timeout: 3)
            }
        } else {
            _ = tapWhenReady(app.navigationBars.buttons["Cancel"], timeout: 2)
        }
        Thread.sleep(forTimeInterval: 1.8)
    }

    private func pollsForDuplicate(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.buttons["Update Existing Item"].exists {
                return true
            }
            usleep(200_000)
        }
        return false
    }
}
