import XCTest
@testable import CortexAnimeNative

final class WatchGuardPolicyTests: XCTestCase {
    func testEpisodeThresholdClamps() {
        XCTAssertEqual(WatchGuardPolicy.clampedEpisodes(0), 2)
        XCTAssertEqual(WatchGuardPolicy.clampedEpisodes(1), 2)
        XCTAssertEqual(WatchGuardPolicy.clampedEpisodes(4), 4)
        XCTAssertEqual(WatchGuardPolicy.clampedEpisodes(99), 8)
    }

    func testMinuteThresholdNormalization() {
        XCTAssertEqual(WatchGuardPolicy.normalizedMinutes(0), 0)
        XCTAssertEqual(WatchGuardPolicy.normalizedMinutes(-30), 0)
        XCTAssertEqual(WatchGuardPolicy.normalizedMinutes(.nan), 0)
        XCTAssertEqual(WatchGuardPolicy.normalizedMinutes(10), 30)
        XCTAssertEqual(WatchGuardPolicy.normalizedMinutes(150), 150)
        XCTAssertEqual(WatchGuardPolicy.normalizedMinutes(9_999), 600)
    }

    func testAskBeforeNextEpisode() {
        XCTAssertFalse(WatchGuardPolicy.askBeforeNextEpisode(enabled: false, threshold: 4, finished: 9))
        XCTAssertFalse(WatchGuardPolicy.askBeforeNextEpisode(enabled: true, threshold: 4, finished: 0))
        XCTAssertFalse(WatchGuardPolicy.askBeforeNextEpisode(enabled: true, threshold: 4, finished: 3))
        XCTAssertTrue(WatchGuardPolicy.askBeforeNextEpisode(enabled: true, threshold: 4, finished: 4))
        XCTAssertTrue(WatchGuardPolicy.askBeforeNextEpisode(enabled: true, threshold: 4, finished: 7))
    }

    func testAskDuringPlayback() {
        XCTAssertFalse(WatchGuardPolicy.askDuringPlayback(enabled: true, minutesLimit: 0, minutesPlayed: 400))
        XCTAssertFalse(WatchGuardPolicy.askDuringPlayback(enabled: true, minutesLimit: 150, minutesPlayed: 149.9))
        XCTAssertTrue(WatchGuardPolicy.askDuringPlayback(enabled: true, minutesLimit: 150, minutesPlayed: 150))
        XCTAssertFalse(WatchGuardPolicy.askDuringPlayback(enabled: false, minutesLimit: 150, minutesPlayed: 400))
        XCTAssertFalse(WatchGuardPolicy.askDuringPlayback(enabled: true, minutesLimit: 150, minutesPlayed: .nan))
    }

    func testHumanReadableText() {
        XCTAssertEqual(WatchGuardPolicy.durationText(45), "45 minutes")
        XCTAssertEqual(WatchGuardPolicy.durationText(60), "1 hour")
        XCTAssertEqual(WatchGuardPolicy.durationText(150), "2 h 30 min")
        XCTAssertEqual(WatchGuardPolicy.countdownText(30), "Pausing in 30 s")
        XCTAssertEqual(WatchGuardPolicy.countdownText(0), "Pausing")
    }
}

final class WatchGuardModelTests: XCTestCase {
    private let keys = [WatchGuardPolicy.enabledKey, WatchGuardPolicy.episodeKey, WatchGuardPolicy.minutesKey]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    @MainActor func testDefaultsMatchTheProductPromise() async throws {
        let guardModel = WatchGuard()
        XCTAssertTrue(guardModel.enabled)
        XCTAssertEqual(guardModel.episodeThreshold, 4)
        XCTAssertEqual(guardModel.minuteThreshold, 150)
        XCTAssertNil(guardModel.asking)
    }

    @MainActor func testFourthEpisodeHoldsBeforeAutoplay() async throws {
        let guardModel = WatchGuard()
        for _ in 0..<3 {
            guardModel.noteEpisodeFinished()
            XCTAssertFalse(guardModel.shouldHoldBeforeNextEpisode())
        }
        guardModel.noteEpisodeFinished()
        XCTAssertTrue(guardModel.shouldHoldBeforeNextEpisode())
        XCTAssertEqual(guardModel.asking, WatchGuard.Reason.episodes(4))
        XCTAssertEqual(guardModel.remaining, WatchGuardPolicy.countdownSeconds)
    }

    @MainActor func testAcknowledgementRestartsTheChain() async throws {
        let guardModel = WatchGuard()
        for _ in 0..<4 { guardModel.noteEpisodeFinished() }
        XCTAssertTrue(guardModel.shouldHoldBeforeNextEpisode())
        guardModel.acknowledge()
        XCTAssertNil(guardModel.asking)
        XCTAssertEqual(guardModel.episodesFinished, 0)
        XCTAssertFalse(guardModel.shouldHoldBeforeNextEpisode())
    }

    @MainActor func testInteractionResetsTheChain() async throws {
        let guardModel = WatchGuard()
        for _ in 0..<4 { guardModel.noteEpisodeFinished() }
        guardModel.noteInteraction()
        XCTAssertFalse(guardModel.shouldHoldBeforeNextEpisode())
        XCTAssertNil(guardModel.asking)
    }

    @MainActor func testDisabledGuardNeverAsks() async throws {
        UserDefaults.standard.set(false, forKey: WatchGuardPolicy.enabledKey)
        let guardModel = WatchGuard()
        for _ in 0..<9 { guardModel.noteEpisodeFinished() }
        XCTAssertFalse(guardModel.shouldHoldBeforeNextEpisode())
        for _ in 0..<400 { guardModel.tick(playing: true, seconds: 60) }
        XCTAssertNil(guardModel.asking)
    }

    @MainActor func testLongPlaybackTickAsksOnce() async throws {
        UserDefaults.standard.set(30.0, forKey: WatchGuardPolicy.minutesKey)
        let guardModel = WatchGuard()
        // 30 minutes of ticks, five seconds each.
        for _ in 0..<359 { guardModel.tick(playing: true) }
        XCTAssertNil(guardModel.asking)
        guardModel.tick(playing: true)
        XCTAssertEqual(guardModel.asking, WatchGuard.Reason.longPlayback(30))
    }

    @MainActor func testPausedTicksDoNotAccumulate() async throws {
        UserDefaults.standard.set(30.0, forKey: WatchGuardPolicy.minutesKey)
        let guardModel = WatchGuard()
        for _ in 0..<600 { guardModel.tick(playing: false) }
        XCTAssertNil(guardModel.asking)
    }
}
