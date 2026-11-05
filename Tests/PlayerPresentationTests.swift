import XCTest
@testable import CortexAnimeNative

final class PlayerPresentationTests: XCTestCase {
    func testSubtitleSizeClampsAndRejectsNonfiniteValues() {
        XCTAssertEqual(SubtitleSizePolicy.clamped(8),14)
        XCTAssertEqual(SubtitleSizePolicy.clamped(90),40)
        XCTAssertEqual(SubtitleSizePolicy.clamped(28),28)
        XCTAssertEqual(SubtitleSizePolicy.clamped(.nan),20)
        XCTAssertEqual(SubtitleSizePolicy.clamped(.infinity),20)
    }
    @MainActor func testPlayingHidesAfterInactivityAndVideoTapReveals() async throws {
        let chrome = PlayerChromeState(delay:.milliseconds(40));defer { chrome.cancel() }
        chrome.update(playing:true)
        try await Task.sleep(for:.milliseconds(160))
        XCTAssertFalse(chrome.visible)
        chrome.toggleFromVideo();XCTAssertTrue(chrome.visible)
    }
    @MainActor func testPauseKeepsControlsVisible() async throws {
        let chrome = PlayerChromeState(delay:.milliseconds(40));defer { chrome.cancel() }
        chrome.update(playing:false)
        try await Task.sleep(for:.milliseconds(160))
        XCTAssertTrue(chrome.visible)
        chrome.toggleFromVideo();XCTAssertTrue(chrome.visible)
    }
    @MainActor func testScrubbingPreventsHideUntilRelease() async throws {
        let chrome = PlayerChromeState(delay:.milliseconds(40));defer { chrome.cancel() }
        chrome.update(playing:true,scrubbing:true)
        try await Task.sleep(for:.milliseconds(160));XCTAssertTrue(chrome.visible)
        chrome.update(playing:true)
        try await Task.sleep(for:.milliseconds(160));XCTAssertFalse(chrome.visible)
    }
    @MainActor func testSettingsAndPartyPreventHide() async throws {
        let chrome = PlayerChromeState(delay:.milliseconds(40));defer { chrome.cancel() }
        chrome.update(playing:true,settingsOpen:true)
        try await Task.sleep(for:.milliseconds(160));XCTAssertTrue(chrome.visible)
        chrome.update(playing:true,partyOpen:true)
        try await Task.sleep(for:.milliseconds(160));XCTAssertTrue(chrome.visible)
    }
    @MainActor func testVoiceOverAndInactiveScenePreventHide() async throws {
        let chrome = PlayerChromeState(delay:.milliseconds(40));defer { chrome.cancel() }
        chrome.update(playing:true,voiceOver:true)
        try await Task.sleep(for:.milliseconds(160));XCTAssertTrue(chrome.visible)
        chrome.update(playing:true,active:false)
        try await Task.sleep(for:.milliseconds(160));XCTAssertTrue(chrome.visible)
    }
    @MainActor func testInteractionCancelsOlderTimer() async throws {
        let chrome = PlayerChromeState(delay:.milliseconds(200));defer { chrome.cancel() }
        chrome.update(playing:true)
        try await Task.sleep(for:.milliseconds(120));chrome.interacted()
        try await Task.sleep(for:.milliseconds(120));XCTAssertTrue(chrome.visible)
        try await Task.sleep(for:.milliseconds(160));XCTAssertFalse(chrome.visible)
    }
    @MainActor func testDisappearanceCancelsPendingHide() async throws {
        let chrome = PlayerChromeState(delay:.milliseconds(40))
        chrome.update(playing:true);chrome.cancel()
        try await Task.sleep(for:.milliseconds(160));XCTAssertTrue(chrome.visible)
    }
}
