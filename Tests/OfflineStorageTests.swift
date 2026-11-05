import XCTest
@testable import CortexAnimeNative

final class OfflineStorageTests: XCTestCase {
    private func item() -> DownloadItem { DownloadItem(id:UUID(),animeID:42,title:"Authored test",episode:1,state:"downloaded",progress:1) }
    func testLegacyDownloadIndexDecodesWithoutNewFields() throws {
        let text = "[{\"id\":\"8B02273D-547A-4B30-A107-5F28E927AE12\",\"animeID\":42,\"title\":\"Old saved episode\",\"episode\":1,\"state\":\"downloaded\",\"progress\":1}]"
        let rows = try JSONDecoder().decode([DownloadItem].self,from:Data(text.utf8))
        XCTAssertEqual(rows.count,1);XCTAssertNil(rows[0].subtitleRequired);XCTAssertEqual(rows[0].statusLabel,"Offline ready")
    }
    func testDurableIndexRoundTripIncludesSubtitleRequirementAndLanguage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer { try? FileManager.default.removeItem(at:root) }
        let store = OfflineIndex(url:root.appendingPathComponent("downloads.json"));var row = item();row.subtitleRequired = true;row.language = "hun";row.bytesOnDisk = 1024
        try store.save([row]);let saved = try store.load()
        XCTAssertEqual(saved[0].id,row.id);XCTAssertEqual(saved[0].language,"hun");XCTAssertEqual(saved[0].subtitleRequired,true);XCTAssertEqual(saved[0].bytesOnDisk,1024)
    }
    func testCorruptPrimaryIndexFallsBackToPreviousValidIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer { try? FileManager.default.removeItem(at:root) }
        let store = OfflineIndex(url:root.appendingPathComponent("downloads.json"));var row = item()
        try store.save([row]);row.title = "New revision";try store.save([row]);try Data("broken index".utf8).write(to:store.url)
        let restored = try store.load();XCTAssertEqual(restored[0].title,"Authored test")
    }
    func testUnreadableIndexThrowsRatherThanSilentlyHidingMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer { try? FileManager.default.removeItem(at:root) }
        let store = OfflineIndex(url:root.appendingPathComponent("downloads.json"));try Data("corrupted".utf8).write(to:store.url)
        XCTAssertThrowsError(try store.load())
    }
    func testInvalidAndStoryboardCaptionsCannotBecomeOfflineReady() {
        XCTAssertFalse(OfflineStorage.captions(Data()))
        XCTAssertFalse(OfflineStorage.captions(Data("WEBVTT\n\n00:00.000 --> 00:01.000\nthumbnails/sprite.jpg#xywh=0,0,20,20\n".utf8)))
        XCTAssertTrue(OfflineStorage.captions(Data("WEBVTT\n\n00:00.000 --> 00:02.000\nAuthored caption\n".utf8)))
        XCTAssertTrue(OfflineStorage.captions(Data("1\n00:00:00,000 --> 00:00:02,000\nAuthored SRT\n".utf8)))
    }
    func testOfflinePathsRejectAbsoluteAndContainerEscapes() {
        XCTAssertNil(OfflineFiles.resolve("/etc/hosts"));XCTAssertNil(OfflineFiles.resolve("../../../../etc/hosts"));XCTAssertNil(OfflineFiles.relative(URL(fileURLWithPath:"/etc/hosts")))
    }
    func testLogicalFileByteCountIsNotAMemoryAllocation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating:1,count:1024).write(to:file);defer { try? FileManager.default.removeItem(at:file) }
        XCTAssertEqual(OfflineStorage.bytes(at:file),1024)
    }
    @MainActor func testRequiredMissingCaptionsPreventLocalPlayback() throws {
        try OfflineStorage.ensureFolder(OfflineFiles.mediaFolder)
        let movie = OfflineFiles.mediaFolder.appendingPathComponent(UUID().uuidString+".mp4")
        try Data([1,2,3]).write(to:movie);defer { try? FileManager.default.removeItem(at:movie) }
        var row = item();row.mediaKind = "file";row.relativeLocation = OfflineFiles.relative(movie);row.subtitleRequired = true
        XCTAssertNil(Downloads.shared.localURL(row));XCTAssertThrowsError(try Downloads.shared.route(for:row))
    }
    @MainActor func testActualBundledVideoImportAndSubtitlePairing() async throws {
        let video = try XCTUnwrap(Bundle.main.url(forResource:"NativePlaybackFixture",withExtension:"mp4"))
        let caption = try XCTUnwrap(Bundle.main.url(forResource:"NativePlaybackFixture",withExtension:"vtt"))
        let before = Set(Downloads.shared.items.map(\.id));try await Downloads.shared.importVideo(video)
        let imported = try XCTUnwrap(Downloads.shared.items.first(where:{ !before.contains($0.id) }));defer { Downloads.shared.remove(imported) }
        XCTAssertEqual(imported.imported,true);XCTAssertEqual(imported.state,"downloaded");XCTAssertGreaterThan(imported.bytesOnDisk ?? 0,0)
        try Downloads.shared.importSubtitles(caption,for:imported)
        let saved = try XCTUnwrap(Downloads.shared.items.first(where:{ $0.id == imported.id }))
        let route = try Downloads.shared.route(for:saved);XCTAssertTrue(route.url.isFileURL);XCTAssertTrue(try XCTUnwrap(route.subtitleURL).isFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath:video.path),"Import must copy, not remove the user's original.")
    }
}
