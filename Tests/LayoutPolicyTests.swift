import XCTest
import UIKit
@testable import CortexAnimeNative

/// 6.4: the shell decision is a pure function, so the foldable / landscape cases can be proven
/// without the hardware.
final class LayoutPolicyTests: XCTestCase {
    func testCompactPhoneKeepsTheTabLayout() {
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .phone, horizontal: .compact), .phone)
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .phone, horizontal: nil), .phone)
    }

    func testWidePhoneGetsTheRailNotTheIPadSidebar() {
        // Unfolded foldable inner display and any landscape iPhone report .regular while still
        // being a phone; the iPad split shell used to swallow those screens.
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .phone, horizontal: .regular), .widePhone)
    }

    func testIPadIsUntouched() {
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .pad, horizontal: .regular), .pad)
        // Split View can drop an iPad into a compact width: it keeps the pad shell contract.
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .pad, horizontal: .compact), .pad)
    }

    func testUserCanPinTheWideLayoutOnADeviceThatReportsCompact() {
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .phone, horizontal: .compact, forceWide: true), .widePhone)
        // The pin never overrides an iPad.
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .pad, horizontal: .regular, forceWide: true), .pad)
    }

    func testQAArgumentForcesTheWideShellEverywhere() {
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .phone, horizontal: .compact, qaForced: true), .widePhone)
        XCTAssertEqual(CortexLayoutPolicy.mode(idiom: .pad, horizontal: .regular, qaForced: true), .widePhone)
        XCTAssertEqual(CortexLayoutPolicy.qaArgument, "--wide-phone-qa")
    }

    func testLayoutPreferenceDefaultsToOffAndPersists() {
        let defaults = UserDefaults(suiteName: "layout-tests-\(UUID().uuidString)")!
        let preferences = LayoutPreferences(defaults: defaults)
        XCTAssertFalse(preferences.forceWide, "A normal iPhone must keep the tab layout by default.")
        preferences.forceWide = true
        XCTAssertTrue(LayoutPreferences(defaults: defaults).forceWide, "The switch has to survive a relaunch.")
        preferences.forceWide = false
        XCTAssertFalse(LayoutPreferences(defaults: defaults).forceWide)
    }

    func testLayoutTitlesAreStableForTheProfileRow() {
        XCTAssertEqual(CortexLayoutMode.phone.title, "Phone")
        XCTAssertEqual(CortexLayoutMode.widePhone.title, "Wide phone")
        XCTAssertEqual(CortexLayoutMode.pad.title, "Pad")
        XCTAssertEqual(CortexLayoutMode.allCases.count, 3)
    }
}
