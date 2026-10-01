import XCTest
@testable import TheScale

final class FatnagWordmarkTests: XCTestCase {
    func testSettingsBrandFatJokeIsLocalized() {
        XCTAssertEqual(
            StringCatalogLookup.string(key: "settings.brand.fat", language: "en"),
            "fat"
        )
        XCTAssertEqual(
            StringCatalogLookup.string(key: "settings.brand.fat", language: "fr"),
            "graisse"
        )
        XCTAssertEqual(
            StringCatalogLookup.string(key: "settings.brand.fat", language: "de"),
            "Fett"
        )
        XCTAssertEqual(
            StringCatalogLookup.string(key: "settings.brand.fat", language: "ja"),
            "脂肪"
        )
    }

    func testLegacyFatKeyIsGoneSoWordmarkStaysEnglish() {
        XCTAssertNil(
            StringCatalogLookup.string(key: "fat", language: "fr"),
            "Bare Text(\"fat\") must not localize — wordmark stays English everywhere except Settings jokeFat"
        )
    }
}
