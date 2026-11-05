import XCTest
import SwiftUI
@testable import CortexAnimeNative

final class AnimeTests: XCTestCase {
    func testWebVTTParsingWithSettingsAndMultilineText() {
        let fixture = "WEBVTT\n\n1\n00:00:01.000 --> 00:00:03.500 align:center\nFirst line\nSecond line\n\n"
        let cues = WebVTT.parse(fixture)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].start, 1)
        XCTAssertEqual(cues[0].end, 3.5)
        XCTAssertEqual(cues[0].text, "First line\nSecond line")
    }
    func testDownloadRequiresExplicitGrantAndDedicatedURL() throws {
        let noGrant = try JSONDecoder().decode(StreamInfo.self, from: Data("{\"found\":true,\"streamUrl\":\"https://example.org/master.m3u8\"}".utf8))
        XCTAssertNotNil(noGrant.playbackURL)
        XCTAssertNil(noGrant.approvedDownloadURL)
        let granted = try JSONDecoder().decode(StreamInfo.self, from: Data("{\"downloadAllowed\":true,\"downloadUrl\":\"https://example.org/offline.m3u8\"}".utf8))
        XCTAssertNotNil(granted.approvedDownloadURL)
        let insecure = try JSONDecoder().decode(StreamInfo.self, from: Data("{\"downloadAllowed\":true,\"downloadUrl\":\"http://example.org/offline.m3u8\"}".utf8))
        XCTAssertNil(insecure.approvedDownloadURL)
    }
    func testNotReleasedEpisodeIsRecognisedAsUnpublished() throws {
        // The live resolver answers an unpublished episode with found:false + notReleased:true.
        // It must decode, must never look playable, and must be distinguishable from a
        // source that exists but could not be resolved.
        let info = try JSONDecoder().decode(StreamInfo.self, from: Data(#"{"found":false,"notReleased":true,"anilistId":"207191","episode":4,"audio":"sub","nextEpisode":4,"airingAt":0}"#.utf8))
        XCTAssertNil(info.playbackURL)
        XCTAssertEqual(info.notReleased, true)
        let broken = try JSONDecoder().decode(StreamInfo.self, from: Data(#"{"found":false}"#.utf8))
        XCTAssertNil(broken.notReleased)
    }
    func testCatalogHandlesBothAPITitleShapes() {
        let a = Anime(json: ["id": 1, "title": "Fixture title", "cover": "https://example.org/cover.jpg", "episodes": 3])
        let b = Anime(json: ["id": 2, "title": ["english": "English fixture", "romaji": "Romaji fixture"], "coverImage": ["large": "https://example.org/a.jpg"]])
        XCTAssertEqual(a?.title, "Fixture title")
        XCTAssertEqual(b?.title, "English fixture")
        XCTAssertNil(Anime(json: ["title": "Missing ID fixture"]))
    }

    func testResumeRejectsFinishedInvalidAndLivePositions() {
        XCTAssertEqual(PlaybackPolicy.resumePosition(saved: 500, duration: 1400), 500)
        for saved in [0.0, 2, 1390, 1400, 1500, Double.nan, Double.infinity] {
            XCTAssertNil(PlaybackPolicy.resumePosition(saved: saved, duration: 1400))
        }
        XCTAssertNil(PlaybackPolicy.resumePosition(saved: 50, duration: .infinity))
        XCTAssertNil(PlaybackPolicy.resumePosition(saved: 50, duration: 0))
    }
    func testCaptionIndexIncludesOverlappingCuesAndSeekingBackwards() {
        let timeline = CueTimeline([Cue(start: 0, end: 100, text: "Long"), Cue(start: 5, end: 7, text: "Short"), Cue(start: 8, end: 12, text: "Next")])
        XCTAssertEqual(timeline.text(at: 6), "Long\nShort")
        XCTAssertEqual(timeline.text(at: 10), "Long\nNext")
        XCTAssertEqual(timeline.text(at: 6), "Long\nShort")
        XCTAssertEqual(timeline.text(at: 101), "")
        XCTAssertEqual(timeline.text(at: .nan), "")
    }
    func testVTTRejectsInvalidTimesAndIgnoresNotes() {
        XCTAssertNil(WebVTT.time("00:99:00"))
        XCTAssertNil(WebVTT.time("-1:05"))
        XCTAssertNil(WebVTT.time("00:nan"))
        let cues = WebVTT.parse("\u{feff}WEBVTT\r\n\r\nNOTE ignored\r\n00:01 --> 00:02\r\nNot a cue\r\n\r\n00:03.000 --> 00:05.000\r\n<b>A &amp; B</b>")
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.text, "A & B")
    }
    func testMissingRequestedSubtitleDoesNotSilentlySelectAnotherLanguage() throws {
        let info = try JSONDecoder().decode(StreamInfo.self, from: Data(#"{"tracks":[{"file":"https://example.org/en.vtt","label":"English"}]}"#.utf8))
        XCTAssertNil(info.subtitle(language: "hun"))
        XCTAssertEqual(info.subtitle(language: "eng")?.label, "English")
    }
    func testEmbedAndCredentialURLsAreNotNativeStreams() throws {
        for json in [#"{"found":true,"type":"embed","streamUrl":"https://example.org/player"}"#, #"{"streamUrl":"https://user:secret@example.org/master.m3u8"}"#, #"{"found":false,"streamUrl":"https://example.org/master.m3u8"}"#] {
            XCTAssertNil(try JSONDecoder().decode(StreamInfo.self, from: Data(json.utf8)).playbackURL)
        }
    }
    func testReleasedEpisodeLimitAndImageValidation() {
        let anime = Anime(json: ["id": 1, "title": "Unit fixture", "episodes": 12, "airedEpisodes": 3, "cover": "", "banner": "https://example.org/banner.jpg", "hasHungarianSub": true])!
        XCTAssertEqual(anime.episodeLimit(language: "hun"), 3)
        XCTAssertEqual(anime.episodeLimit(language: "eng"), 3)
        XCTAssertNil(anime.cover)
        XCTAssertNotNil(anime.banner)
        XCTAssertTrue(anime.hasHungarian)
    }
    @MainActor func testMissingOfflinePackageFailsImmediatelyWithoutFakeBuffering() async {
        let route = PlaybackRoute(title: "Unit fixture", url: URL(fileURLWithPath: "/not-present/cortex-test.movpkg"), key: "test.missing", subtitleURL: nil)
        let playback = Playback(route: route)
        playback.open(route)
        XCTAssertEqual(playback.phase, .failed)
        XCTAssertFalse(playback.isWaiting)
        XCTAssertNotNil(playback.error)
        playback.stop()
    }
    @MainActor func testRefreshRoutePreservesEpisodeAndLanguageIdentity() async throws {
        let model = CatalogModel(api: APIClient())
        let anime = Anime(json: ["id": 100, "title": "Unit fixture", "episodes": 12, "airedEpisodes": 3])!
        let info = try JSONDecoder().decode(StreamInfo.self, from: Data(#"{"found":true,"type":"hls","streamUrl":"https://example.org/master.m3u8"}"#.utf8))
        let route = try model.route(for: anime, episode: 3, language: "hun", info: info)
        XCTAssertEqual(route.key, "100.3")
        XCTAssertEqual(route.episodeLabel, "Episode 3")
        XCTAssertNotNil(route.reload)
        XCTAssertNil(route.next)
        XCTAssertNotNil(try model.route(for: anime, episode: 2, language: "hun", info: info).next)
    }
    func testAppearanceThemesHaveDistinctNamesAndStableIDs() {
        XCTAssertEqual(CortexTheme.allCases.count, 8)
        XCTAssertEqual(Set(CortexTheme.allCases.map(\.name)).count, 8)
        XCTAssertEqual(Set(CortexTheme.allCases.map(\.suggestedIcon)).count, 8)
        XCTAssertEqual(AppIconChoice.allCases.count, 8)
        XCTAssertEqual(CortexTheme.cosmic.name, "Dark Cosmic")
        for theme in CortexTheme.allCases { XCTAssertEqual(CortexTheme(rawValue: theme.id), theme) }
    }
    @MainActor func testLibraryPersistsActualHistoryAndWatchlist() throws {
        let name = "cortex.library.test." + UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let anime = Anime(json: ["id": 42, "title": "Unit fixture", "episodes": 12])!
        let library = AnimeLibrary(defaults: defaults); library.toggle(42)
        library.record(anime: anime, episode: 3, language: "hun", seconds: 145, duration: 1400)
        let restored = AnimeLibrary(defaults: defaults)
        XCTAssertTrue(restored.favorites.contains(42)); XCTAssertEqual(restored.history.first?.seconds, 145)
        XCTAssertEqual(restored.history.first?.episode, 3); XCTAssertEqual(restored.history.first?.language, "hun")
        restored.record(anime: anime, episode: 4, language: "eng", seconds: 1200, duration: 1200, completed: true)
        XCTAssertEqual(restored.history.count, 1); XCTAssertTrue(restored.history[0].completed)
        restored.clearHistory(); XCTAssertTrue(AnimeLibrary(defaults: defaults).history.isEmpty)
    }
    @MainActor func testHistoryRejectsInvalidProgressAndHasFiniteBound() {
        let name = "cortex.library.bounds." + UUID().uuidString; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let library = AnimeLibrary(defaults: defaults)
        for id in 1...45 { library.record(anime: Anime(json: ["id": id])!, episode: 1, language: "hun", seconds: 10, duration: .infinity) }
        XCTAssertEqual(library.history.count, 40); XCTAssertEqual(library.history.first?.id, 45)
        let first = library.history[0].anime
        library.record(anime: first, episode: 1, language: "hun", seconds: .nan, duration: 10)
        XCTAssertEqual(library.history.count, 40); XCTAssertEqual(library.history[0].duration, 0)
        library.removeHistory([45]); XCTAssertEqual(library.history.count, 39)
    }
    @MainActor func testSleepTimerActuallyExpiresAndCanBeCancelled() async throws {
        let model = Playback(route: PlaybackRoute(title: "Unit fixture", url: URL(fileURLWithPath: "/not-present.movpkg"), key: "test.sleep", subtitleURL: nil))
        model.setSleepTimer(seconds: 0.05); XCTAssertNotNil(model.sleepDeadline)
        try await Task.sleep(for: .milliseconds(150)); XCTAssertNil(model.sleepDeadline)
        model.setSleepTimer(minutes: 15); XCTAssertNotNil(model.sleepDeadline)
        model.setSleepTimer(minutes: nil); XCTAssertNil(model.sleepDeadline)
        model.stop()
    }

    func testStoryboardVTTNeverBecomesVisibleDialogue() {
        let text = "WEBVTT\n\n00:00.000 --> 00:10.000\nthumbnails/\nsprite_0.webp#xywh=480,0,160,90\n\n00:10.000 --> 00:12.000\nActual dialogue"
        let cues = WebVTT.parse(text)
        XCTAssertEqual(cues.count, 1); XCTAssertEqual(cues.first?.text, "Actual dialogue")
    }

}
