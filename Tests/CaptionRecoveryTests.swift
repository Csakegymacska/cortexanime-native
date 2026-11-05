import XCTest
import AVFoundation
@testable import CortexAnimeNative

final class CaptionRecoveryTests: XCTestCase {
    private let dialogue = Data("WEBVTT\n\n00:00:00.000 --> 00:00:39.000\nAuthored caption recovery check\n".utf8)
    private func track(_ file: String = "one") -> SubtitleTrack { SubtitleTrack(file:"https://fixture.invalid/"+file+".vtt",label:"Magyar") }
    func testTimeoutDoesNotEraseSubtitleTrack() async throws {
        let t = track()
        let prepared = try await CaptionPolicy.prepare([t],language:"hun",fetch:{ _ in throw URLError(.timedOut) })
        XCTAssertEqual(prepared.tracks,[t]);XCTAssertTrue(prepared.data.isEmpty)
    }
    func testHTTPFailureDoesNotEraseSubtitleTrack() async throws {
        let t = track()
        let prepared = try await CaptionPolicy.prepare([t],language:"hun",fetch:{ request in
            (Data(),HTTPURLResponse(url:request.url!,statusCode:503,httpVersion:nil,headerFields:nil)!)
        })
        XCTAssertEqual(prepared.tracks,[t])
    }
    func testValidDialogueIsPreferredOverUnverifiedCandidate() async throws {
        let a = track("first"),b = track("second"),data = dialogue
        let prepared = try await CaptionPolicy.prepare([a,b],language:"hun",fetch:{ request in
            if request.url == a.url { throw URLError(.timedOut) }
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        XCTAssertEqual(prepared.tracks,[b,a]);XCTAssertEqual(prepared.data[b.file],data)
    }
    func testConfirmedStoryboardStillCannotBecomeDialogue() async throws {
        let t = track(),data = Data("WEBVTT\n\n00:00.000 --> 00:10.000\nthumbnails/sprite.jpg#xywh=0,0,100,100\n".utf8)
        let prepared = try await CaptionPolicy.prepare([t],language:"hun",fetch:{ request in
            (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        XCTAssertTrue(prepared.tracks.isEmpty)
    }
    func testTemporaryHTMLResponseDoesNotEraseTrack() async throws {
        let t = track(),data = Data("<html>Temporarily unavailable</html>".utf8)
        let prepared = try await CaptionPolicy.prepare([t],language:"hun",fetch:{ request in
            (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        XCTAssertEqual(prepared.tracks,[t]);XCTAssertTrue(prepared.data.isEmpty)
    }
    @MainActor func testPreparedBytesReachNativePlayerWithoutSecondHTTPSFetch() async throws {
        let t = track(UUID().uuidString)
        var info = try JSONDecoder().decode(StreamInfo.self,from:Data("{\"found\":true}".utf8))
        info.tracks = [t];info.preparedCaptions = [t.file:dialogue]
        var route = PlaybackRoute(title:"Authored caption recovery",url:try XCTUnwrap(Bundle.main.url(forResource:"NativePlaybackFixture",withExtension:"mp4")),key:"caption.recovery.fixture",subtitleURL:t.url)
        route.info = info;UserDefaults.standard.removeObject(forKey:"resume."+route.key)
        let player = Playback(route:route);defer { player.stop() }
        player.start()
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline && (player.captionCueCount != 1 || player.position < 1) { try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertEqual(player.captionCueCount,1)
        XCTAssertTrue(player.subtitle.contains("Authored caption recovery"))
        XCTAssertGreaterThan(player.position,0)
        XCTAssertEqual(player.selectedCaption,t.file)
    }
}
