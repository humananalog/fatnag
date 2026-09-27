import XCTest
@testable import ScaleOnDevicePolish

final class OnDevicePolishEligibilityTests: XCTestCase {
    func testAppleIntelligenceDevicesNeverInstall() {
        let policy = OnDevicePolishEligibility.policy(
            appleIntelligenceDeviceCapable: true,
            physicalMemoryBytes: 8_000_000_000
        )
        XCTAssertEqual(policy, .appleIntelligenceDevice)
        XCTAssertFalse(
            OnDevicePolishEligibility.shouldAutoInstall(appleIntelligenceDeviceCapable: true)
        )
    }

    func testCompatiblePhonesInstallWhenNotAICapable() {
        #if targetEnvironment(simulator)
        let policy = OnDevicePolishEligibility.policy(
            appleIntelligenceDeviceCapable: false,
            physicalMemoryBytes: 6_000_000_000
        )
        if case .unsupported = policy {
            // Expected on simulator.
        } else {
            XCTFail("Simulator should skip install")
        }
        #else
        let policy = OnDevicePolishEligibility.policy(
            appleIntelligenceDeviceCapable: false,
            physicalMemoryBytes: 6_000_000_000
        )
        XCTAssertEqual(policy, .installSidecar)
        XCTAssertTrue(
            OnDevicePolishEligibility.shouldAutoInstall(appleIntelligenceDeviceCapable: false)
        )
        #endif
    }

    func testLowMemoryUnsupported() {
        let policy = OnDevicePolishEligibility.policy(
            appleIntelligenceDeviceCapable: false,
            physicalMemoryBytes: 1_000_000_000
        )
        #if targetEnvironment(simulator)
        if case .unsupported = policy { /* ok */ } else { XCTFail() }
        #else
        if case .unsupported(let reason) = policy {
            XCTAssertTrue(reason.lowercased().contains("memory"))
        } else {
            XCTFail("Expected unsupported for low RAM")
        }
        #endif
    }

    func testParseTitleBody() {
        let raw = """
            TITLE: Alex, step up
            BODY: Scale is waiting. Keep the streak honest.
            """
        let parsed = OnDevicePolishParsers.parseTitleBody(
            raw,
            fallbackTitle: "Hey",
            fallbackBody: "Body"
        )
        XCTAssertEqual(parsed.title, "Alex, step up")
        XCTAssertTrue(parsed.body.contains("Scale is waiting"))
    }

    func testParseNotifyNo() {
        let raw = """
            NOTIFY: no
            REASON: Duplicate mild noise
            """
        let parsed = OnDevicePolishParsers.parseNotify(raw)
        XCTAssertFalse(parsed.shouldNotify)
        XCTAssertEqual(parsed.reason, "Duplicate mild noise")
    }
}
