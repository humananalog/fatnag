import XCTest
@testable import TheScale

final class ScaleLegalTests: XCTestCase {
    func testAllDocumentsAreNonEmptyAndAvoidEmDashes() {
        for doc in ScaleLegal.Document.allCases {
            XCTAssertFalse(doc.title.isEmpty, doc.rawValue)
            XCTAssertGreaterThan(doc.body.count, 200, doc.rawValue)
            XCTAssertFalse(doc.body.contains("\u{2014}"), doc.rawValue)
            XCTAssertFalse(doc.body.contains("\u{2013}"), doc.rawValue)
        }
    }

    func testControllerAndContact() {
        XCTAssertEqual(ScaleLegal.controllerName, "Human Analog Limited")
        XCTAssertEqual(ScaleLegal.privacyEmail, "privacy@humananalog.ai")
        XCTAssertEqual(ScaleLegal.minimumAgeYears, 18)
        XCTAssertTrue(ScaleLegal.privacyPolicyURL.absoluteString.contains("humananalog"))
        XCTAssertTrue(ScaleLegal.termsOfUseURL.absoluteString.contains("humananalog"))
        XCTAssertTrue(ScaleLegal.supportURL.absoluteString.contains("the-scale/support"))
    }

    func testPrivacyMentionsGDPRAndNoSale() {
        let body = ScaleLegal.privacyPolicyBody.lowercased()
        XCTAssertTrue(body.contains("gdpr"))
        XCTAssertTrue(body.contains("consent"))
        XCTAssertTrue(body.contains("do not sell"))
        XCTAssertTrue(ScaleLegal.usStatePrivacyBody.lowercased().contains("ccpa")
            || ScaleLegal.usStatePrivacyBody.lowercased().contains("california"))
    }

    func testExportJSONContainsController() throws {
        let data = try ScaleDataRights.exportLocalDataJSON(profile: .default)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("Human Analog Limited"))
        XCTAssertTrue(json.contains("exportedAt"))
    }

    func testLegalAcceptanceStoreRoundTrip() {
        LegalAcceptanceStore.clear()
        XCTAssertNil(LegalAcceptanceStore.acceptedAt)
        LegalAcceptanceStore.markAccepted(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(LegalAcceptanceStore.acceptedAt?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 0.1)
        LegalAcceptanceStore.clear()
        XCTAssertNil(LegalAcceptanceStore.acceptedAt)
    }
}
