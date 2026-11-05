import XCTest
import AVFoundation
@testable import CortexAnimeNative

final class NativeIntegrationTests: XCTestCase {
    func testBleachReleaseCountIsNineOfTenWithoutInventedEpisodes() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource:"FixtureBleach",withExtension:"json"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let media = try XCTUnwrap((root["data"] as? [String:Any])?["Media"] as? [String:Any])
        let anime = try XCTUnwrap(Anime(json:media,now:1792497600))
        XCTAssertEqual(anime.id,185874);XCTAssertEqual(anime.episodes,10);XCTAssertEqual(anime.availableEpisodes,9)
        XCTAssertEqual(anime.episodeLimit(language:"hun"),9);XCTAssertEqual(anime.episodeLimit(language:"eng"),9)
    }
    func testHungarianCatalogCurrentCountDoesNotDisableWatch() throws {
        let anime = try XCTUnwrap(Anime(json:["id":213657,"title":"Mission: Yozakura Family Season 2 Part 2","episodes":12,"totalEpisodes":12,"currentEpisodes":2,"status":"RELEASING","hasHungarianSubtitles":true]))
        XCTAssertEqual(anime.availableEpisodes,2);XCTAssertEqual(anime.episodeLimit(language:"hun"),2)
        XCTAssertEqual(anime.episodes,12)
    }
    func testLatestPastScheduleIsNotOverriddenByStaleNextMetadata() throws {
        let anime = try XCTUnwrap(Anime(json:["id":185874,"episodes":10,"status":"RELEASING","nextAiringEpisode":["episode":2,"airingAt":200],"airingSchedule":["nodes":[["episode":9,"airingAt":99]]]],now:100))
        XCTAssertEqual(anime.availableEpisodes,9)
    }
    func testUpcomingAndUnknownCountsNeverBecomeTwelvePlayableEpisodes() {
        XCTAssertEqual(Anime(json:["id":1,"episodes":12,"status":"NOT_YET_RELEASED"])?.availableEpisodes,0)
        XCTAssertNil(Anime(json:["id":1,"episodes":12,"status":"RELEASING"])?.availableEpisodes)
        XCTAssertEqual(Anime(json:["id":1,"episodes":12,"status":"RELEASING"])?.episodeLimit(language:"eng"),0)
        XCTAssertEqual(Anime(json:["id":1,"episodes":12,"status":"FINISHED"])?.availableEpisodes,12)
    }
    func testPastScheduleAndFutureNextEpisodeAreHandledSeparately() {
        let anime = Anime(json:["id":1,"episodes":12,"status":"RELEASING","airingSchedule":["nodes":[["episode":3,"airingAt":99]]]],now:100)
        XCTAssertEqual(anime?.availableEpisodes,3)
        let future = Anime(json:["id":1,"episodes":12,"status":"RELEASING","nextAiringEpisode":["episode":4,"airingAt":101]],now:100)
        XCTAssertEqual(future?.availableEpisodes,3)
    }
    @MainActor func testAPIPathAndQueryDoNotAllowAnotherOrigin() throws {
        let api = APIClient();let url = try api.url("/api/messages",query:["with":"Name & Other"])
        XCTAssertEqual(url.host,"cortanime.eu");XCTAssertEqual(URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,"Name & Other")
        for path in ["https://other.invalid/","//other.invalid/","/api\\evil"] { XCTAssertThrowsError(try api.url(path)) }
    }
    @MainActor func testRealNativeFixturePlaybackSeekCaptionsPauseAndResume() async throws {
        let route = PlaybackRoute(title:"Authored test fixture",url:try XCTUnwrap(Bundle.main.url(forResource:"NativePlaybackFixture",withExtension:"mp4")),key:"test.fixture.integration",subtitleURL:Bundle.main.url(forResource:"NativePlaybackFixture",withExtension:"vtt"))
        UserDefaults.standard.removeObject(forKey:"resume."+route.key)
        let playback = Playback(route:route);defer { playback.stop();UserDefaults.standard.removeObject(forKey:"resume."+route.key) }
        playback.start();try await wait(seconds:12) { playback.phase == .playing && playback.position > 1 }
        XCTAssertGreaterThan(playback.duration,35);XCTAssertTrue(playback.subtitle.contains("Authored"))
        playback.player.pause();try await wait(seconds:3) { playback.phase == .paused }
        playback.seek(22);try await wait(seconds:4) { playback.position > 21 && playback.subtitle.contains("Native AVPlayer") }
        playback.player.play();try await wait(seconds:4) { playback.phase == .playing && playback.position > 23 }
        playback.seek(8);try await wait(seconds:4) { playback.position >= 8 && playback.position < 12 }
    }
    @MainActor func testActualPrivateFixtureDownloadThenLocalPlayback() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let movie = env["OFFLINE_FIXTURE_URL"] ?? env["TEST_RUNNER_OFFLINE_FIXTURE_URL"],
              let caption = env["OFFLINE_CAPTION_URL"] ?? env["TEST_RUNNER_OFFLINE_CAPTION_URL"] else {
            throw XCTSkip("The private authored HTTPS fixture URLs are only supplied by the offline QA job.")
        }
        let store = Downloads.shared
        for item in store.items where item.animeID == 999999 { store.remove(item) }
        let anime = try XCTUnwrap(Anime(json:["id":999999,"title":"Authored offline QA fixture","episodes":1,"status":"FINISHED"]))
        let info = try JSONDecoder().decode(StreamInfo.self,from:JSONSerialization.data(withJSONObject:["found":true,"streamUrl":movie,"type":"mp4","downloadAllowed":true,"downloadUrl":movie]))
        // Only the authored clip receives this test permission, never a real provider response.
        try await store.start(anime:anime,episode:1,info:info,subtitle:SubtitleTrack(file:caption,label:"Authored fixture captions"))
        try await wait(seconds:65) { store.items.contains { $0.animeID == 999999 && ["downloaded","failed"].contains($0.state) } }
        let item = try XCTUnwrap(store.items.first { $0.animeID == 999999 })
        XCTAssertEqual(item.state,"downloaded","The real HTTPS download must finish and pass AVAsset validation.")
        let local = try XCTUnwrap(store.localURL(item)),vtt = try XCTUnwrap(store.subtitleURL(item))
        XCTAssertTrue(local.isFileURL);XCTAssertTrue(vtt.isFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath:local.path));XCTAssertTrue(FileManager.default.fileExists(atPath:vtt.path))
        let savedIndex = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("downloads.json")
        let restored = try JSONDecoder().decode([DownloadItem].self,from:Data(contentsOf:savedIndex))
        XCTAssertTrue(restored.contains { $0.id == item.id && $0.state == "downloaded" })
        if let stop = env["OFFLINE_STOP_URL"] ?? env["TEST_RUNNER_OFFLINE_STOP_URL"],let url = URL(string:stop) {
            _ = try await URLSession.shared.data(from:url)
            try await Task.sleep(for:.milliseconds(500))
            do {
                var request = URLRequest(url:try XCTUnwrap(URL(string:movie)));request.timeoutInterval = 2;request.cachePolicy = .reloadIgnoringLocalCacheData
                _ = try await URLSession.shared.data(for:request)
                XCTFail("The authored remote source must be unavailable before validating offline playback.")
            } catch { /* Expected: source server has been shut down. */ }
        } else { XCTFail("The controlled offline-source shutdown URL was not provided.") }
        let route = PlaybackRoute(title:item.title,url:local,key:"offline.qa.fixture",subtitleURL:vtt,episodeLabel:"Episode 1 · Offline")
        UserDefaults.standard.removeObject(forKey:"resume."+route.key)
        let playback = Playback(route:route);defer { playback.stop() }
        playback.start();try await wait(seconds:15) { playback.phase == .playing && playback.position > 1 && !playback.subtitle.isEmpty }
        XCTAssertGreaterThan(playback.duration,35)
        XCTAssertTrue(playback.route.url.isFileURL,"Offline playback may not fall back to a streaming URL.")
        playback.seek(22);try await wait(seconds:5) { playback.position >= 21 && playback.subtitle.contains("Native AVPlayer") }
    }
    @MainActor func testLiveHomeAndReportedYozakuraDetailWithoutFixtures() async throws {
        guard ProcessInfo.processInfo.environment["CORTEX_LIVE_QA"] == "1" else { throw XCTSkip("Live API checks are opt-in.") }
        XCTAssertFalse(CatalogModel.fixture,"Live tests must not substitute recorded metadata.")
        let model = CatalogModel(api:APIClient());await model.load()
        XCTAssertFalse(model.trending.isEmpty,"Production home fallback must return real titles.")
        XCTAssertFalse(model.seasonal.isEmpty)
        XCTAssertNil(model.error)
        let detail = try await model.detail(213657)
        XCTAssertEqual(detail.id,213657);XCTAssertEqual(detail.year,2026)
        XCTAssertGreaterThan(detail.episodeLimit(language:"hun"),0,"Explicit released data must enable Watch Now.")
    }
    @MainActor func testNativeLiveDarkSummonerEpisodesTwoAndThree() async throws {
        guard ProcessInfo.processInfo.environment["CORTEX_LIVE_QA"] == "1" else { throw XCTSkip("Live source checks are opt-in; fixture playback is separate.") }
        let model = CatalogModel(api:APIClient())
        let anime = try XCTUnwrap(Anime(json:["id":208025,"title":"The Dark Summoner","episodes":12,"airedEpisodes":3,"status":"RELEASING"]))
        for episode in [2,3] {
            let info = try await model.resolve(anime,episode:episode,language:"eng")
            let route = try model.route(for:anime,episode:episode,language:"eng",info:info)
            let playback = Playback(route:route);defer { playback.stop() }
            playback.start();try await wait(seconds:28) { playback.phase == .failed || playback.phase == .playing && playback.position > 2 }
            XCTAssertEqual(playback.phase,.playing,"Native live episode \(episode): \(playback.error ?? "not playing")")
            guard playback.phase == .playing else { continue }
            XCTAssertGreaterThan(playback.duration,65)
            playback.seek(65);try await wait(seconds:10) { playback.phase == .failed || playback.phase == .playing && playback.position > 66 }
            XCTAssertEqual(playback.phase,.playing);XCTAssertGreaterThan(playback.position,66)
            let evidence = "Native AVPlayer live read-only check: anime=208025 episode=\(episode) phase=\(playback.phase.rawValue) seconds=\(Int(playback.position)) duration=\(Int(playback.duration))"
            let attachment = XCTAttachment(string:evidence);attachment.name = "live-native-208025-\(episode)";attachment.lifetime = .keepAlways;add(attachment)
            playback.stop()
        }
    }
    @MainActor func testNativeProductionHLSDownloadThenLocalCaptionPlayback() async throws {
        // A real provider download is slower and flakier than a unit test should be, so it is
        // opt-in: the offline QA job sets CORTEX_LIVE_DOWNLOAD_QA=1.
        guard ProcessInfo.processInfo.environment["CORTEX_LIVE_DOWNLOAD_QA"] == "1" else {
            throw XCTSkip("Live provider download checks are opt-in.")
        }
        let store = Downloads.shared
        let anime = try XCTUnwrap(Anime(json:["id":207191,"title":"Love Potion offline integration","episodes":3,"status":"FINISHED"]))
        for row in store.items where row.animeID == anime.id { store.remove(row) }
        defer { for row in store.items where row.animeID == anime.id { store.remove(row) } }
        let info = try await CatalogModel(api:APIClient()).resolve(anime,episode:3,language:"hun",refresh:true)
        XCTAssertNil(info.downloadAllowed,"This case specifically exercises a normal provider reply without the old private grant.")
        try await store.start(anime:anime,episode:3,info:info,subtitle:try XCTUnwrap(info.subtitle(language:"hun")),language:"hun")
        try await wait(seconds:150) { store.items.contains { $0.animeID == anime.id && ["downloaded","failed"].contains($0.state) } }
        let row = try XCTUnwrap(store.items.first(where:{ $0.animeID == anime.id }))
        XCTAssertEqual(row.state,"downloaded",row.note ?? "The actual HLS package must pass offline validation.")
        let route = try store.route(for:row);XCTAssertTrue(route.url.isFileURL);XCTAssertNil(route.reload);XCTAssertNil(route.next)
        let vtt = try XCTUnwrap(route.subtitleURL),cues = WebVTT.parse(try String(contentsOf:vtt,encoding:.utf8))
        let cue = try XCTUnwrap(cues.first(where:{ $0.end-$0.start >= 2 && $0.start > 5 }))
        let playback = Playback(route:route);defer { playback.stop() }
        playback.start();try await wait(seconds:15) { playback.phase == .playing && playback.position > 1 }
        playback.player.pause();playback.seek(cue.start+0.3)
        try await wait(seconds:8) { playback.position >= cue.start && !playback.subtitle.isEmpty }
        let proof = XCTAttachment(string:"Actual production HLS 207191/3: local package, selected Hungarian captions, offline-cache validation and local seek/caption playback; bytes=\(row.bytesOnDisk ?? 0), cues=\(cues.count). Remote production source was not shut down; this is not an airplane-mode certification.")
        proof.name = "actual-production-hls-offline-local";proof.lifetime = .keepAlways;add(proof)
    }
    @MainActor private func wait(seconds: Double,predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { if predicate() { return };try await Task.sleep(for:.milliseconds(100)) }
        XCTFail("Timed out waiting for a real native playback transition.")
        throw NSError(domain:"NativePlaybackTest",code:1,userInfo:[NSLocalizedDescriptionKey:"Native playback transition timed out"])
    }
}
