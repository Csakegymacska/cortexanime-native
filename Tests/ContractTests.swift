import XCTest
@testable import CortexAnimeNative

final class LocalProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { do { let (code,data) = try Self.handler!(request);let response = HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!;client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self) } catch { client?.urlProtocol(self,didFailWithError:error) } }
    override func stopLoading() {}
}
final class ContractTests: XCTestCase {
    @MainActor func testNativeAPIUsesJSONAndCorrectHTTPMethodsWithoutLiveWrites() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [LocalProtocol.self];let client = APIClient(session:URLSession(configuration:config))
        defer { LocalProtocol.handler = nil }
        for (path,method) in [("/api/auth/register","POST"),("/api/user/profile","PATCH"),("/api/comments","DELETE"),("/api/friends/request","POST"),("/api/messages","POST"),("/api/watchparty/control","POST")] {
            LocalProtocol.handler = { request in XCTAssertEqual(request.httpMethod,method);XCTAssertEqual(request.url?.path,path);XCTAssertEqual(request.url?.host,"cortanime.eu");XCTAssertEqual(request.value(forHTTPHeaderField:"Content-Type"),"application/json");return (200,Data(#"{"ok":true}"#.utf8)) }
            let result = try await client.json(path,method:method,body:["test":"synthetic"]);XCTAssertEqual(result["ok"] as? Bool,true)
        }
    }
    @MainActor func testUnauthorizedAccountActionShowsServerErrorNotSuccess() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [LocalProtocol.self];let client = APIClient(session:URLSession(configuration:config));defer { LocalProtocol.handler = nil }
        LocalProtocol.handler = { _ in (401,Data(#"{"error":"Not authenticated"}"#.utf8)) }
        do { _ = try await client.json("/api/friends");XCTFail("Unauthorized response must not pass.") } catch { XCTAssertEqual(error.localizedDescription,"Not authenticated") }
    }
    @MainActor func testGraphQLSchemaErrorIsReportedAndUsesInjectedTransport() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [LocalProtocol.self]
        let client = APIClient(session:URLSession(configuration:config));defer { LocalProtocol.handler = nil }
        LocalProtocol.handler = { request in
            XCTAssertEqual(request.url?.host,"graphql.anilist.co")
            return (400,Data(#"{"errors":[{"message":"Unknown argument sort on field airingSchedule"}],"data":null}"#.utf8))
        }
        do { _ = try await client.graph("query{Media(id:1){id}}");XCTFail("Schema failure must not become generic HTTP 400.") }
        catch { XCTAssertEqual(error.localizedDescription,"AniList: Unknown argument sort on field airingSchedule") }
    }
    @MainActor func testDirectDetailKeepsKnownPlannedTotalButOnlyTwoReleased() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [LocalProtocol.self]
        let client = APIClient(session:URLSession(configuration:config));defer { LocalProtocol.handler = nil }
        LocalProtocol.handler = { _ in (200,Data(#"{"data":{"Media":{"id":213657,"title":{"romaji":"Yozakura"},"episodes":null,"seasonYear":2026,"status":"RELEASING"},"aired":{"airingSchedules":[{"episode":2,"airingAt":1}]}}}"#.utf8)) }
        let seed = try XCTUnwrap(Anime(json:["id":213657,"episodes":12,"currentEpisodes":2,"status":"RELEASING"]))
        let detail = try await CatalogModel(api:client).detail(213657,cached:seed)
        XCTAssertEqual(detail.episodes,12);XCTAssertEqual(detail.availableEpisodes,2)
        XCTAssertEqual(detail.year,2026);XCTAssertEqual(detail.episodeLimit(language:"hun"),2)
    }
    func testDragNavigationClampsAndSelectsEveryTab() {
        XCTAssertEqual(NativeGesturePolicy.tabIndex(x:-100,width:375,count:5),0)
        XCTAssertEqual(NativeGesturePolicy.tabIndex(x:1000,width:375,count:5),4)
        for index in 0..<5 {
            let center = 8+(Double(index)+0.5)*(375-16)/5
            XCTAssertEqual(NativeGesturePolicy.tabIndex(x:center,width:375,count:5),index)
        }
        XCTAssertEqual(NativeGesturePolicy.tabProgress(x:0,width:0,count:5),0)
        XCTAssertEqual(NativeGesturePolicy.tabProgress(x:100,width:375,count:0),0)
    }
    func testCardSwipeIgnoresVerticalScrollAndShortTaps() {
        XCTAssertEqual(NativeGesturePolicy.pageDelta(horizontal:-70,vertical:5),1)
        XCTAssertEqual(NativeGesturePolicy.pageDelta(horizontal:70,vertical:5),-1)
        XCTAssertEqual(NativeGesturePolicy.pageDelta(horizontal:60,vertical:100),0)
        XCTAssertEqual(NativeGesturePolicy.pageDelta(horizontal:20,vertical:0),0)
        XCTAssertEqual(NativeGesturePolicy.pageDelta(horizontal:.infinity,vertical:0),0)
    }
    func testWidgetFeedRejectsFutureAdultNonAnimeAndDeduplicatesLatest() {
        func row(_ id: Int,_ ep: Int,_ at: Double,adult: Bool = false,type: String = "ANIME",english: String = "Title") -> [String:Any] {
            ["episode":ep,"airingAt":at,"media":["id":id,"isAdult":adult,"type":type,"title":["english":english,"romaji":"Fallback"],"coverImage":["large":"http://insecure.invalid/cover.jpg"]]]
        }
        let rows = [row(1,1,700),row(1,2,900),row(2,1,800,adult:true),row(3,4,1001),row(4,3,850,type:"MANGA"),row(5,1,850,english:" ")]
        let items = CortexWidgetEpisode.parse(["Page":["airingSchedules":rows]],now:Date(timeIntervalSince1970:1000))
        XCTAssertEqual(items.map(\.id),[1,5]);XCTAssertEqual(items[0].episode,2)
        XCTAssertEqual(items[1].title,"Fallback");XCTAssertNil(items[0].cover)
        XCTAssertEqual(items[0].deepLink?.absoluteString,"cortexanime-native-port://anime/1")
    }
    @MainActor func testWidgetFetchUsesPublicInjectedTransportWithoutCookies() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [LocalProtocol.self]
        let client = CortexWidgetFeedClient(session:URLSession(configuration:config));defer { LocalProtocol.handler = nil }
        LocalProtocol.handler = { request in
            XCTAssertEqual(request.url?.host,"graphql.anilist.co");XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));XCTAssertNil(request.value(forHTTPHeaderField:"Cookie"))
            return (200,Data(#"{"data":{"Page":{"airingSchedules":[{"episode":2,"airingAt":99,"media":{"id":1,"type":"ANIME","isAdult":false,"title":{"english":"Recorded test title"}}}]}}}"#.utf8))
        }
        let snapshot = try await client.fetch(now:Date(timeIntervalSince1970:100))
        XCTAssertEqual(snapshot.items.first?.episode,2)
    }
    @MainActor func testDetailRefreshRetainsExplicitReleasedCountAndHUFlagWithoutAiringData() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [LocalProtocol.self]
        let client = APIClient(session:URLSession(configuration:config));defer { LocalProtocol.handler = nil }
        LocalProtocol.handler = { _ in (200,Data(#"{"data":{"Media":{"id":213657,"episodes":null,"status":"RELEASING"},"aired":{"airingSchedules":[]}}}"#.utf8)) }
        let seed = try XCTUnwrap(Anime(json:["id":213657,"episodes":12,"currentEpisodes":2,"status":"RELEASING","hasHungarianSubtitles":true]))
        let result = try await CatalogModel(api:client).detail(213657,cached:seed)
        XCTAssertEqual(result.episodes,12);XCTAssertEqual(result.availableEpisodes,2);XCTAssertTrue(result.hasHungarian)
    }
    func testMetadataQueriesUseSupportedLatestReleaseContract() {
        XCTAssertFalse(MetadataQueries.fields.contains("airingSchedule"))
        XCTAssertTrue(MetadataQueries.detail.contains("airingSchedules(mediaId:$id,notYetAired:false,sort:TIME_DESC)"))
        XCTAssertFalse(MetadataQueries.home.contains("airingSchedule(notYetAired"))
    }
    func testCaptionCachePreservesValidCuesAndRejectsStoryboard() throws {
        let source = URL(string:"https://native-fixture.invalid/"+UUID().uuidString+".vtt")!
        defer { try? FileManager.default.removeItem(at:SubtitleCache.file(for:source)) }
        let data = Data("WEBVTT\n\n00:01.000 --> 00:04.000\nAuthored cache cue".utf8)
        try SubtitleCache.save(data,source:source);XCTAssertEqual(SubtitleCache.load(source),data)
        XCTAssertThrowsError(try SubtitleCache.save(Data("not a caption".utf8),source:source))
        XCTAssertThrowsError(try SubtitleCache.save(Data(repeating:65,count:2_000_001),source:source))
    }
    func testDecorationsAndWebsiteInformationAreRealBundledResources() throws {
        // 6.8: the decorations are drawn in code instead of loaded from a remote CDN, so the
        // catalogue itself is the resource that has to be complete and resolvable.
        XCTAssertGreaterThanOrEqual(CortexDecoration.all.count, 100)
        XCTAssertEqual(Set(CortexDecoration.all.map(\.id)).count, CortexDecoration.all.count)
        XCTAssertTrue(DecorationCategory.allCases.allSatisfy { !CortexDecoration.matching($0).isEmpty })
        XCTAssertNotNil(CortexDecoration.named("frame_cosmic"))
        XCTAssertNotNil(CortexDecoration.named("glow_fireflies"))
        XCTAssertNil(CortexDecoration.named("none"))
        // An id from the retired catalogue still resolves to something drawable.
        XCTAssertNotNil(CortexDecoration.named("frame_galaxy_2024_legacy"))
        XCTAssertNotNil(CortexDecoration.named("glow_gold_holiday"))
        // 7.0: two layers are encoded in one stored string and both resolve back.
        let stack = CortexDecoration.encode(frame: "frame_galaxy", aura: "glow_fireflies")
        XCTAssertEqual(stack, "frame_galaxy|glow_fireflies")
        XCTAssertEqual(CortexDecoration.list(stack).map(\.id), ["frame_galaxy", "glow_fireflies"])
        XCTAssertEqual(CortexDecoration.list(stack).filter { $0.slot == .frame }.count, 1)
        XCTAssertEqual(CortexDecoration.list("frame_galaxy|").count, 1)
        XCTAssertEqual(CortexDecoration.list("none").count, 0)
        XCTAssertTrue(CortexDecoration.all.allSatisfy { !$0.name.isEmpty && $0.price >= 0 })
        // 7.1: a new account must be able to look good without credits.
        let free = CortexDecoration.all.filter(\.isFree)
        XCTAssertGreaterThanOrEqual(free.count, 30)
        XCTAssertGreaterThanOrEqual(free.filter { $0.slot == .aura }.count, 18)
        XCTAssertNotNil(CortexDecoration.named("glow_soft"))

        let file = try XCTUnwrap(Bundle.main.url(forResource:"WebsiteInformation",withExtension:"json"));let entries = try JSONDecoder().decode([String:[InformationEntry]].self,from:Data(contentsOf:file))
        XCTAssertEqual(entries["faq"]?.count,11);XCTAssertGreaterThan(entries["privacy"]?.count ?? 0,5)
    }
}
