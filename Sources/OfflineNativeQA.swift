#if DEBUG
import Foundation
import AVFoundation

/// Simulator-only, authored HTTPS fixture. No provider media or production account writes.
@MainActor enum OfflineNativeQA {
    static func wait(_ seconds: Double,_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if condition() { return };try await Task.sleep(for:.milliseconds(150)) }
        throw AppFailure.message("Offline QA timed out.")
    }
    static func report(_ name: String,_ row: [String:Any]) throws {
        let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:row,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(name+".json"),options:.atomic)
    }
    static func run(_ store: Downloads) async throws -> PlaybackRoute? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--offline-download-cold-qa") {
            let anime = Anime(json:["id":999999,"title":"Authored offline QA fixture","episodes":1,"status":"FINISHED"])!
            let movie = "https://127.0.0.1:9443/NativePlaybackFixture.mp4",caption = "https://127.0.0.1:9443/NativePlaybackFixture.vtt"
            let info = try JSONDecoder().decode(StreamInfo.self,from:JSONSerialization.data(withJSONObject:["found":true,"streamUrl":movie,"type":"mp4","downloadAllowed":true,"downloadUrl":movie]))
            try await store.start(anime:anime,episode:1,info:info,subtitle:SubtitleTrack(file:caption,label:"Authored fixture captions"),language:"eng")
            let pending = Anime(json:["id":999998,"title":"Paused queue persistence QA","episodes":1,"status":"FINISHED"])!
            _ = try store.enqueue(anime:pending,episodes:[1],language:"eng")
            guard let queued = store.items.first(where:{ $0.animeID == 999998 }) else { throw AppFailure.message("Missing queued fixture.") }
            store.pause(queued)
            try await wait(65) { store.items.contains { $0.animeID == 999999 && ["downloaded","failed"].contains($0.state) } }
            guard let item = store.items.first(where:{ $0.animeID == 999999 }),item.state == "downloaded",let local = store.localURL(item),let vtt = store.subtitleURL(item) else { throw AppFailure.message(store.items.first(where:{ $0.animeID == 999999 })?.note ?? "The actual download failed.") }
            try report("plus-offline-download",["downloaded":true,"localVideo":local.isFileURL,"localCaptions":vtt.isFileURL,"bytes":item.bytesOnDisk ?? 0,"pausedUnresolved":store.items.contains { $0.animeID == 999998 && $0.state == "paused" && $0.mediaKind == nil },"source":"authored-loopback-HTTPS","mockDownload":false])
            return nil
        }
        try await wait(10) { store.qaReconciled } // Wait for actual URLSession reconciliation, not an assumed delay.
        guard let item = store.items.first(where:{ $0.animeID == 999999 && $0.state == "downloaded" }) else { throw AppFailure.message("The real saved download did not survive cold launch.") }
        let route = try store.route(for:item)
        if args.contains("--offline-player-ui-qa") { return route }
        let paused = store.items.contains { $0.animeID == 999998 && $0.state == "paused" && $0.queueRequest == true && $0.mediaKind == nil }
        guard paused,route.url.isFileURL,route.subtitleURL?.isFileURL == true,route.reload == nil,route.next == nil else { throw AppFailure.message("Cold launch lost queue state or attempted a remote playback fallback.") }
        UserDefaults.standard.removeObject(forKey:"resume."+route.key)
        let playback = Playback(route:route);defer { playback.stop() }
        playback.start();try await wait(18) { playback.phase == .playing && playback.position > 1 && !playback.subtitle.isEmpty }
        let duration = playback.duration
        playback.player.pause();try await Task.sleep(for:.milliseconds(400));let before = playback.position
        playback.player.play();try await wait(5) { playback.phase == .playing && playback.position > before+0.2 }
        playback.seek(22);try await wait(6) { playback.position >= 21 && playback.subtitle.contains("Native AVPlayer") }
        guard duration>35 else { throw AppFailure.message("The local video duration is invalid.") }
        try report("plus-offline-cold-playback",["coldLaunch":true,"pausedUnresolvedPreserved":paused,"localVideo":route.url.isFileURL,"localCaptions":true,"duration":duration,"position":playback.position,"subtitle":playback.subtitle,"pauseResume":true,"seek":true,"networkFallback":false,"physicalDevice":false])
        return nil
    }
}
#endif
