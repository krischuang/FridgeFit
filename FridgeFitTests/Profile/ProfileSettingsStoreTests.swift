import XCTest
@testable import FridgeFit

final class ProfileSettingsStoreTests: XCTestCase {
    func test_storeRoundTripsPresentationPreferences() throws {
        let suiteName = "ProfileSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsProfileSettingsStore(defaults: defaults, key: "settings")
        let expected = ProfileSettings(measurementSystem: .imperial, defaultServingSize: 5)

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func test_storeUsesSafeDefaultsWhenNoValueExists() throws {
        let suiteName = "ProfileSettingsStoreTests.empty.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            UserDefaultsProfileSettingsStore(defaults: defaults, key: "settings").load(),
            ProfileSettings()
        )
    }

    func test_servingSizeIsClampedToSupportedDisplayRange() {
        var settings = ProfileSettings()

        settings.setServingSize(0)
        XCTAssertEqual(settings.defaultServingSize, 1)

        settings.setServingSize(99)
        XCTAssertEqual(settings.defaultServingSize, 12)
    }
}
