import XCTest
@testable import CortexAnimeNative

final class DownloadQueueTests: XCTestCase {
    private func source(_ fields: [String:Any]) throws -> StreamInfo { try JSONDecoder().decode(StreamInfo.self,from:JSONSerialization.data(withJSONObject:fields)) }
    func testMissingPrivateGrantDoesNotRejectNativeHLS() throws {
        let info = try source(["found":true,"streamUrl":"https://example.org/master.m3u8","type":"hls"])
        XCTAssertEqual(try OfflineSource.candidate(info).path,"/master.m3u8")
    }
    func testExplicitRefusalCannotBeOverriddenByPlaybackURL() throws {
        let info = try source(["found":true,"streamUrl":"https://example.org/video.mp4","type":"mp4","downloadAllowed":false,"downloadUrl":"https://example.org/offline.mp4"])
        XCTAssertThrowsError(try OfflineSource.candidate(info))
    }
    func testEmbedsAndInsecureURLsAreNotDownloadSources() throws {
        let cases: [[String:Any]] = [["found":true,"streamUrl":"http://example.org/movie.mp4","type":"mp4"],["found":true,"streamUrl":"https://example.org/frame","type":"iframe"],["downloadUrl":"https://user:password@example.org/file.mp4"]]
        for fields in cases { XCTAssertThrowsError(try OfflineSource.candidate(source(fields))) }
    }
    func testFairPlayAndLivePlaylistsAreRejectedWithoutBypass() throws {
        XCTAssertThrowsError(try OfflineSource.validateManifest("#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://asset\"\n#EXT-X-ENDLIST",requireEnd:true))
        XCTAssertThrowsError(try OfflineSource.validateManifest("#EXTM3U\n#EXTINF:6\nsegment.ts",requireEnd:true))
        XCTAssertNoThrow(try OfflineSource.validateManifest("#EXTM3U\n#EXTINF:6\nsegment.ts\n#EXT-X-ENDLIST",requireEnd:true))
    }
    func testSeasonPlanningSkipsDuplicatesSavedAndUnreleasedEpisodes() {
        let saved = DownloadItem(id:UUID(),animeID:42,title:"Test",episode:2,state:"downloaded",progress:1)
        var failed = saved;failed.id = UUID();failed.episode = 3;failed.state = "failed"
        XCTAssertEqual(DownloadQueuePolicy.missingEpisodes([0,1,1,2,3,4,12],limit:3,existing:[saved,failed],animeID:42),[1,3])
    }
    func testSubtitleFallbackPrefersSelectedLanguageThenEnglishThenVideoOnly() throws {
        let both = try source(["found":true,"streamUrl":"https://example.org/master.m3u8","type":"hls","tracks":[
            ["file":"https://example.org/en.vtt","label":"English","kind":"captions"],
            ["file":"https://example.org/hu.vtt","label":"Magyar","kind":"subtitles"]]])
        XCTAssertEqual(DownloadQueuePolicy.pickSubtitle(from:both,language:"hun")?.file,"https://example.org/hu.vtt")
        XCTAssertEqual(DownloadQueuePolicy.pickSubtitle(from:both,language:"eng")?.file,"https://example.org/en.vtt")
        let englishOnly = try source(["found":true,"streamUrl":"https://example.org/master.m3u8","type":"hls","tracks":[
            ["file":"https://example.org/en.vtt","label":"English","kind":"captions"]]])
        XCTAssertEqual(DownloadQueuePolicy.pickSubtitle(from:englishOnly,language:"hun")?.label,"English")
        let none = try source(["found":true,"streamUrl":"https://example.org/master.m3u8","type":"hls"])
        XCTAssertNil(DownloadQueuePolicy.pickSubtitle(from:none,language:"hun"))
    }
    func testTransferFailuresMapToActionableMessages() {
        XCTAssertEqual(DownloadQueuePolicy.friendly(URLError(.dataNotAllowed)),"This download needs Wi-Fi. Connect to Wi-Fi and retry this episode.")
        XCTAssertTrue(DownloadQueuePolicy.friendly(URLError(.timedOut)).contains("Retry"))
        XCTAssertEqual(DownloadQueuePolicy.friendly(AppFailure.message("Custom failure")),"Custom failure")
    }
    @MainActor func testQueueContinuesAfterResolutionErrors() async throws {
        let store = Downloads.shared,original = store.sourceResolver;var order: [Int] = []
        let anime = try XCTUnwrap(Anime(json:["id":999996,"title":"Queue error QA","episodes":3,"status":"FINISHED"]))
        defer { for row in store.items where row.animeID == anime.id { store.remove(row) };store.sourceResolver = original }
        store.sourceResolver = { _,episode,_ in order.append(episode);throw AppFailure.message("Authored resolver error") }
        XCTAssertEqual(try store.enqueue(anime:anime,episodes:[1,2,3],language:"hun"),3)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline && order.count < 3 { try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertEqual(order,[1,2,3]);XCTAssertTrue(store.items.filter { $0.animeID == anime.id }.allSatisfy { $0.state == "failed" })
    }
    @MainActor func testQueueIsPersistedAndUnresolvedPauseResumesWithoutLosingIt() throws {
        let store = Downloads.shared,original = store.sourceResolver;store.sourceResolver = nil
        let anime = try XCTUnwrap(Anime(json:["id":999997,"title":"Queue persistence QA","episodes":12,"currentEpisodes":3,"status":"RELEASING"]))
        defer { for row in store.items where row.animeID == anime.id { store.remove(row) };store.sourceResolver = original }
        XCTAssertEqual(try store.enqueue(anime:anime,episodes:Array(1...12),language:"hun"),3)
        XCTAssertEqual(try store.enqueue(anime:anime,episodes:[1,2,3],language:"hun"),0)
        let row = try XCTUnwrap(store.items.first(where:{ $0.animeID == anime.id }));store.pause(row)
        let paused = try XCTUnwrap(store.items.first(where:{ $0.id == row.id }));XCTAssertEqual(paused.state,"paused");store.resume(paused)
        let index = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("downloads.json")
        let records = try JSONDecoder().decode([DownloadItem].self,from:Data(contentsOf:index)).filter { $0.animeID == anime.id }
        XCTAssertEqual(records.count,3);XCTAssertTrue(records.allSatisfy { $0.state == "queued" && $0.queueRequest == true && $0.batchID == row.batchID && $0.subtitleRequired == true })
    }
    @MainActor func testActualSerialQueueDownloadsTwoAuthoredVideosWithoutPrivateGrantFields() async throws {
        let env = ProcessInfo.processInfo.environment
        // The authored fixtures only exist in the offline CI job; a plain unit run skips.
        guard let movie = env["OFFLINE_FIXTURE_URL"] ?? env["TEST_RUNNER_OFFLINE_FIXTURE_URL"],
              let caption = env["OFFLINE_CAPTION_URL"] ?? env["TEST_RUNNER_OFFLINE_CAPTION_URL"] else {
            throw XCTSkip("The authored offline fixtures are only served by the offline QA job.")
        }
        let anime = try XCTUnwrap(Anime(json:["id":999998,"title":"Actual serial offline QA","episodes":2,"status":"FINISHED"]))
        let info = try source(["found":true,"streamUrl":movie,"type":"mp4","tracks":[["file":caption,"label":"English","kind":"captions"]]])
        let store = Downloads.shared,original = store.sourceResolver;var order: [Int] = []
        defer { for row in store.items where row.animeID == anime.id { store.remove(row) };store.sourceResolver = original }
        store.sourceResolver = { _,episode,_ in
            XCTAssertFalse(store.items.contains { $0.animeID == anime.id && $0.episode != episode && DownloadQueuePolicy.activeStates.contains($0.state) })
            order.append(episode);return info
        }
        XCTAssertEqual(try store.enqueue(anime:anime,episodes:[1,2],language:"eng"),2)
        let deadline = Date().addingTimeInterval(70)
        while Date() < deadline {
            let rows = store.items.filter { $0.animeID == anime.id }
            if rows.count == 2 && rows.allSatisfy({ ["downloaded","failed"].contains($0.state) }) { break }
            try await Task.sleep(for:.milliseconds(200))
        }
        let rows = store.items.filter { $0.animeID == anime.id };XCTAssertEqual(order,[1,2]);XCTAssertEqual(rows.count,2)
        for row in rows { XCTAssertEqual(row.state,"downloaded",row.note ?? "Offline validation did not finish");XCTAssertTrue(try store.route(for:row).url.isFileURL);XCTAssertNotNil(store.subtitleURL(row)) }
    }
}
