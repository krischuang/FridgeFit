//
//  SpoonacularConfigurationTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class SpoonacularConfigurationTests: XCTestCase {
    func test_sanitized_trimsWhitespaceAndNewlines() {
        XCTAssertEqual(SpoonacularConfiguration.sanitized("  abc123\n"), "abc123")
    }

    func test_sanitized_rejectsEmptyPlaceholderAndUnexpandedSetting() {
        XCTAssertNil(SpoonacularConfiguration.sanitized(nil))
        XCTAssertNil(SpoonacularConfiguration.sanitized("   "))
        XCTAssertNil(SpoonacularConfiguration.sanitized("your-spoonacular-api-key-here"))
        XCTAssertNil(SpoonacularConfiguration.sanitized("$(SPOONACULAR_API_KEY)"))
    }

    func test_load_prefersEnvironmentVariable() {
        let configuration = SpoonacularConfiguration.load(environment: ["SPOONACULAR_API_KEY": "from-env"])
        XCTAssertEqual(configuration?.apiKey, "from-env")
    }
}
