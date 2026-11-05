import XCTest
@testable import CortexAnimeNative

// 5.0: the alert planner and the radar ranker are pure functions on purpose, so the whole
// "does it notify the right series, once" contract can be checked on CI without a device.

final class AlertPlannerTests: XCTestCase {
    private func follow(_ id: Int, last: Int, notify: Bool = true) -> FollowedSeries {
        FollowedSeries(animeID: id, title: "Series \(id)", cover: nil, lastEpisode: last,
                       followedAt: Date(timeIntervalSince1970: 0), notificationsOn: notify)
    }

    private func release(_ animeID: Int, _ episode: Int, at: TimeInterval = 1_000) -> CortexRelease {
        CortexRelease(feedID: "\(animeID)-\(episode)", animeID: animeID, episode: episode,
                      title: "Series \(animeID)", airedAt: Date(timeIntervalSince1970: at), cover: nil)
    }

    func testOnlyNewEpisodesFire() {
        let (hits, updated) = AlertPlanner.plan(follows: [follow(7, last: 3)], releases: [release(7, 3), release(7, 4)])
        XCTAssertEqual(hits.map(\.episode), [4])
        XCTAssertEqual(updated.first?.lastEpisode, 4)
    }

    func testHighestEpisodeWinsSoOneBreakIsOneBanner() {
        let releases = [release(7, 5, at: 900), release(7, 9, at: 1_200), release(7, 7, at: 1_000)]
        let (hits, updated) = AlertPlanner.plan(follows: [follow(7, last: 4)], releases: releases)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.episode, 9)
        XCTAssertEqual(updated.first?.lastEpisode, 9)
    }

    func testUnfollowedSeriesAndQuietFollowsStaySilent() {
        let hits = AlertPlanner.plan(follows: [follow(7, last: 1, notify: false)], releases: [release(7, 6), release(8, 4)]).hits
        XCTAssertTrue(hits.isEmpty)
        let updated = AlertPlanner.plan(follows: [follow(7, last: 1, notify: false)], releases: [release(7, 6)]).updated
        XCTAssertEqual(updated.first?.lastEpisode, 6, "a quiet follow still advances its watermark")
    }

    func testHitsAreOrderedNewestFirst() {
        let follows = [follow(1, last: 0), follow(2, last: 0), follow(3, last: 0)]
        let releases = [release(1, 2, at: 500), release(2, 2, at: 1_500), release(3, 2, at: 1_000)]
        let hits = AlertPlanner.plan(follows: follows, releases: releases).hits
        XCTAssertEqual(hits.map(\.animeID), [2, 3, 1])
    }

    func testDegenerateInputs() {
        XCTAssertTrue(AlertPlanner.plan(follows: [], releases: [release(1, 1)]).hits.isEmpty)
        let (hits, updated) = AlertPlanner.plan(follows: [follow(5, last: 2)], releases: [])
        XCTAssertTrue(hits.isEmpty)
        XCTAssertEqual(updated.map(\.animeID), [5])
        XCTAssertTrue(AlertPlanner.plan(follows: [follow(5, last: 0)], releases: [release(5, 0)]).hits.isEmpty)
    }

    func testBaselineNeverAnnouncesTheBacklog() {
        let anime = Anime(json: ["anilistId": 42, "title": "X", "currentEpisodes": 6])!
        XCTAssertEqual(AlertPlanner.baseline(for: anime, releases: [release(42, 9), release(42, 3)]), 9)
        XCTAssertEqual(AlertPlanner.baseline(for: anime, releases: []), 6)
    }
}

final class RadarEngineTests: XCTestCase {
    private func anime(_ id: Int, genres: [String], score: Double = 8, hu: Bool = true, status: String = "FINISHED") -> Anime {
        Anime(json: ["anilistId": id, "title": "Anime \(id)", "genres": genres, "score": score,
                     "hasHungarianSubtitles": hu, "status": status, "episodes": 12])!
    }

    private func record(_ anime: Anime, completed: Bool = true) -> WatchRecord {
        WatchRecord(anime: anime, episode: 12, language: "hun", seconds: 1_300, duration: 1_400,
                    completed: completed, updatedAt: Date())
    }

    func testHistoryDrivesTheRanking() {
        let liked = anime(1, genres: ["Action"])
        let pool = [liked, anime(2, genres: ["Action"]), anime(3, genres: ["Romance"])]
        let picks = RadarEngine.suggestions(pool: pool, history: [record(liked)], favorites: [], limit: 5)
        XCTAssertEqual(picks.first?.anime.id, 2)
        XCTAssertEqual(picks.first?.reason, "Because you watch Action")
        XCTAssertFalse(picks.contains { $0.anime.id == 1 }, "already watched series stay out")
    }

    func testFavoritesOutweighAWatch() {
        let saved = anime(9, genres: ["Mystery"])
        let pool = [saved, anime(10, genres: ["Mystery"]), anime(11, genres: ["Sports"])]
        let picks = RadarEngine.suggestions(pool: pool, history: [], favorites: [9], limit: 3)
        XCTAssertEqual(picks.first?.anime.id, 10)
    }

    func testHungarianAndAiringTiebreakers() {
        let pool = [anime(1, genres: [], hu: false), anime(2, genres: [], hu: true), anime(3, genres: [], hu: false, status: "RELEASING")]
        let picks = RadarEngine.suggestions(pool: pool, history: [], favorites: [], limit: 3)
        XCTAssertEqual(picks.map(\.anime.id), [2, 3, 1])
    }

    func testLimitAndEmptyPool() {
        let pool = (1...40).map { anime($0, genres: ["Drama"]) }
        XCTAssertEqual(RadarEngine.suggestions(pool: pool, history: [], favorites: [], limit: 5).count, 5)
        XCTAssertTrue(RadarEngine.suggestions(pool: [], history: [], favorites: [], limit: 5).isEmpty)
    }

    func testRelatedSkipsTheSeed() {
        let seed = anime(1, genres: ["Action", "Drama"])
        let pool = [seed, anime(2, genres: ["Drama"]), anime(3, genres: ["Comedy"])]
        let related = RadarEngine.related(to: seed, pool: pool)
        XCTAssertFalse(related.contains { $0.id == 1 })
        XCTAssertEqual(related.first?.id, 2)
    }
}

final class AdaptiveShellTests: XCTestCase {
    func testDeepLinksResolveToAnimeIDs() {
        XCTAssertEqual(CortexSectionLink.animeID(from: URL(string: "cortexanime-native-port://anime/129190")!), 129190)
        XCTAssertEqual(CortexSectionLink.animeID(from: URL(string: "https://cortanime.eu/anime/129190")!), 129190)
        XCTAssertEqual(CortexSectionLink.animeID(from: URL(string: "https://cortanime.eu/watch/129190/3")!), 129190)
        XCTAssertNil(CortexSectionLink.animeID(from: URL(string: "cortexanime-native-port://home")!))
        XCTAssertNil(CortexSectionLink.animeID(from: URL(string: "https://evil.example/anime/129190")!))
        XCTAssertNil(CortexSectionLink.animeID(from: URL(string: "https://cortanime.eu/anime/0")!))
    }

    func testEverySectionIsReachable() {
        let all = CortexSection.browsing + CortexSection.library
        XCTAssertEqual(Set(all).count, CortexSection.allCases.count)
        XCTAssertTrue(all.allSatisfy { !$0.icon.isEmpty && !$0.rawValue.isEmpty })
    }

    func testWhatsNewBumpsToSix() {
        XCTAssertEqual(WhatsNew.version, "6.4")
        XCTAssertEqual(WhatsNew.key, "whatsNew.seen.640")
        XCTAssertFalse(WhatsNew.features.isEmpty)
    }
}

final class FollowStoreTests: XCTestCase {
    @MainActor func testFollowUnfollowRoundTrip() {
        let defaults = UserDefaults(suiteName: "alerts-tests-\(UUID().uuidString)")!
        let center = AlertCenter(defaults: defaults)
        let anime = Anime(json: ["anilistId": 77, "title": "Frieren", "currentEpisodes": 4])!
        XCTAssertFalse(center.isFollowing(77))
        center.follow(anime, releases: [])
        XCTAssertTrue(center.isFollowing(77))
        XCTAssertEqual(center.follows.first?.lastEpisode, 4)
        center.setNotifications(false, for: 77)
        XCTAssertEqual(center.follows.first?.notificationsOn, false)
        center.unfollow(77)
        XCTAssertTrue(center.follows.isEmpty)
        XCTAssertTrue(AlertCenter(defaults: defaults).follows.isEmpty, "state is persisted")
    }

    @MainActor func testFollowsSurviveRelaunch() {
        let defaults = UserDefaults(suiteName: "alerts-tests-\(UUID().uuidString)")!
        let anime = Anime(json: ["anilistId": 88, "title": "Bleach", "currentEpisodes": 366])!
        AlertCenter(defaults: defaults).follow(anime, releases: [])
        let reopened = AlertCenter(defaults: defaults)
        XCTAssertEqual(reopened.follows.map(\.animeID), [88])
        XCTAssertEqual(reopened.follows.first?.title, "Bleach")
    }
}
