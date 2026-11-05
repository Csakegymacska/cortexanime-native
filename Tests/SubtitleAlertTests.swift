import XCTest
@testable import CortexAnimeNative

// 6.0: the subtitle alert contract, exercised without a network, UserDefaults or a
// notification centre. Everything the settings screen promises has to hold here.

final class SubtitleAlertPlannerTests: XCTestCase {
    private func drop(_ aid: Int, _ ep: Int, _ lang: SubtitleLanguage = .hungarian, at: TimeInterval = 1_000) -> SubtitleDrop {
        SubtitleDrop(id: "\(aid)-\(ep)-\(lang.rawValue)", animeID: aid, episode: ep, language: lang,
                     title: "Series \(aid)", at: Date(timeIntervalSince1970: at), cover: nil)
    }

    private var bothOn: SubtitleAlertPreferences {
        SubtitleAlertPreferences(enabled: true, hungarian: true, english: true, followedOnly: false)
    }

    func testFirstRunSeedsWithoutRinging() {
        let result = SubtitleAlertPlanner.plan(drops: [drop(1, 4), drop(2, 7)], preferences: bothOn,
                                              followed: [], seen: [:])
        XCTAssertTrue(result.hits.isEmpty, "a fresh install must not replay the whole catalogue")
        XCTAssertTrue(result.seeded)
        XCTAssertEqual(result.seen["hu-1"], 4)
        XCTAssertEqual(result.seen["hu-2"], 7)
    }

    func testOnlyNewerEpisodesFire() {
        let result = SubtitleAlertPlanner.plan(drops: [drop(1, 4), drop(1, 5)], preferences: bothOn,
                                              followed: [], seen: ["hu-1": 4])
        XCTAssertEqual(result.hits.map(\.episode), [5])
        XCTAssertEqual(result.seen["hu-1"], 5)
    }

    func testOneBannerPerSeriesEvenAfterACatchUp() {
        let drops = [drop(1, 5, at: 900), drop(1, 9, at: 1_200), drop(1, 7, at: 1_000)]
        let result = SubtitleAlertPlanner.plan(drops: drops, preferences: bothOn, followed: [], seen: ["hu-1": 4])
        XCTAssertEqual(result.hits.count, 1)
        XCTAssertEqual(result.hits.first?.episode, 9)
    }

    func testLanguageSwitchesAreRespected() {
        let hungarianOnly = SubtitleAlertPreferences(enabled: true, hungarian: true, english: false, followedOnly: false)
        let drops = [drop(1, 3, .hungarian), drop(1, 3, .english), drop(2, 5, .english)]
        let result = SubtitleAlertPlanner.plan(drops: drops, preferences: hungarianOnly, followed: [], seen: ["hu-1": 2, "en-2": 4])
        XCTAssertEqual(result.hits.map(\.language), [.hungarian])
        XCTAssertEqual(result.hits.first?.animeID, 1)
        XCTAssertEqual(result.seen["en-2"], 4, "a language that is off keeps its old watermark")
    }

    func testBothLanguagesProduceTwoSeparateHits() {
        let drops = [drop(1, 3, .hungarian, at: 1_100), drop(1, 3, .english, at: 1_200)]
        let result = SubtitleAlertPlanner.plan(drops: drops, preferences: bothOn, followed: [], seen: ["hu-1": 2, "en-1": 2])
        XCTAssertEqual(result.hits.count, 2)
        XCTAssertEqual(result.hits.first?.language, .english, "newest first")
    }

    func testFollowedOnlyScope() {
        let prefs = SubtitleAlertPreferences(enabled: true, hungarian: true, english: false, followedOnly: true)
        let drops = [drop(1, 3), drop(2, 3)]
        let result = SubtitleAlertPlanner.plan(drops: drops, preferences: prefs, followed: [2], seen: ["hu-1": 1, "hu-2": 1])
        XCTAssertEqual(result.hits.map(\.animeID), [2])
    }

    func testTurningTheScopeOffLaterCannotReleaseABacklog() {
        let drops = [drop(1, 6), drop(2, 9)]
        let seeded = SubtitleAlertPlanner.plan(drops: drops, preferences: bothOn, followed: [], seen: [:])
        let reopened = SubtitleAlertPlanner.plan(drops: drops, preferences: bothOn, followed: [], seen: seeded.seen)
        XCTAssertTrue(reopened.hits.isEmpty, "watermarks are tracked for every series, followed or not")
    }

    func testMasterSwitchSilencesButStillTracks() {
        var prefs = bothOn
        prefs.enabled = false
        let result = SubtitleAlertPlanner.plan(drops: [drop(1, 8)], preferences: prefs, followed: [], seen: ["hu-1": 7])
        XCTAssertTrue(result.hits.isEmpty)
        XCTAssertEqual(result.seen["hu-1"], 8)
    }

    func testDegenerateInputs() {
        XCTAssertTrue(SubtitleAlertPlanner.plan(drops: [], preferences: bothOn, followed: [], seen: [:]).hits.isEmpty)
        let nothingWanted = SubtitleAlertPreferences(enabled: true, hungarian: false, english: false, followedOnly: false)
        XCTAssertTrue(SubtitleAlertPlanner.plan(drops: [drop(1, 2)], preferences: nothingWanted, followed: [], seen: ["hu-1": 1]).hits.isEmpty)
        XCTAssertTrue(SubtitleAlertPlanner.plan(drops: [drop(0, 2), drop(1, 0)], preferences: bothOn, followed: [], seen: ["hu-0": 1, "hu-1": 1]).hits.isEmpty)
    }

    func testHitsAreCappedAndOrdered() {
        let drops = (1...9).map { drop($0, 2, .hungarian, at: TimeInterval($0)) }
        let seen = Dictionary(uniqueKeysWithValues: (1...9).map { ("hu-\($0)", 1.0) })
        let result = SubtitleAlertPlanner.plan(drops: drops, preferences: bothOn, followed: [], seen: seen)
        XCTAssertEqual(result.hits.count, 5)
        XCTAssertEqual(result.hits.map(\.animeID), [9, 8, 7, 6, 5])
    }
}

final class SubtitleFeedDecodingTests: XCTestCase {
    func testSubtitleDropRoundTripsThroughJSON() throws {
        let original = SubtitleDrop(id: "212144-5-hu", animeID: 212144, episode: 5, language: .hungarian,
                                    title: "With Vengeance", at: Date(timeIntervalSince1970: 1_700_000_000),
                                    cover: URL(string: "https://example.com/c.jpg"))
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(SubtitleDrop.self, from: data)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.deepLink?.absoluteString.contains("212144"), true)
        XCTAssertEqual(restored.watchLink?.absoluteString, "https://cortanime.eu/watch/212144/5")
    }

    func testPreferencesSummariseWhatIsOn() {
        var prefs = SubtitleAlertPreferences()
        XCTAssertEqual(prefs.summary, "Hungarian · every series")
        prefs.english = true
        prefs.followedOnly = true
        XCTAssertEqual(prefs.summary, "Hungarian + English · followed series")
        prefs.enabled = false
        XCTAssertEqual(prefs.summary, "Off")
        XCTAssertTrue(prefs.isSilent)
        var none = SubtitleAlertPreferences()
        none.hungarian = false
        XCTAssertTrue(none.isSilent)
    }

    @MainActor func testSettingsPersistAndReset() {
        let suite = UserDefaults(suiteName: "cortex-subtitle-tests-\(UUID().uuidString)")!
        let settings = SubtitleAlertSettings(defaults: suite)
        settings.english = true
        settings.setLanguage(.hungarian, on: false)
        let reloaded = SubtitleAlertSettings(defaults: suite)
        XCTAssertTrue(reloaded.english)
        XCTAssertFalse(reloaded.hungarian)
        reloaded.commit(seen: ["hu-1": 3])
        XCTAssertEqual(SubtitleAlertSettings(defaults: suite).seen["hu-1"], 3)
        reloaded.resetWatermarks()
        XCTAssertTrue(SubtitleAlertSettings(defaults: suite).seen.isEmpty)
    }
}
