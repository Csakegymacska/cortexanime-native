import Foundation

/// Download capability is checked against the native media, not an absent private API flag.
/// An explicit service refusal remains authoritative. No DRM keys are extracted or bypassed.
enum OfflineSource {
    static func candidate(_ info: StreamInfo) throws -> URL {
        guard info.downloadAllowed != false else { throw AppFailure.message("This source explicitly disables offline downloads.") }
        if let dedicated = info.downloadUrl {
            guard let url = secure(dedicated) else { throw AppFailure.message("The offline source address is invalid.") };return url
        }
        guard let url = info.playbackURL else { throw AppFailure.message("No native media source is available for this episode.") }
        guard ["hls","m3u8","mp4","m4v","mov","file","direct","video/mp4","application/vnd.apple.mpegurl"].contains(info.type?.lowercased() ?? "") || ["m3u8","mp4","m4v","mov"].contains(url.pathExtension.lowercased()) else { throw AppFailure.message("This source does not expose a supported HLS or video file.") }
        return url
    }
    static func secure(_ raw: String) -> URL? {
        guard let u = URL(string:raw),u.scheme?.lowercased() == "https",u.host != nil,u.user == nil,u.password == nil else { return nil };return u
    }
    static func validateManifest(_ text: String,requireEnd: Bool) throws {
        guard text.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw AppFailure.message("The source did not return an HLS playlist.") }
        let upper = text.uppercased()
        if upper.contains("SKD:") || upper.contains("COM.APPLE.STREAMINGKEYDELIVERY") || upper.contains("METHOD=SAMPLE-AES") || upper.contains("KEYFORMAT=\"") && !upper.contains("KEYFORMAT=\"IDENTITY\"") {
            throw AppFailure.message("This protected stream needs an offline licence that is not available in this app.")
        }
        if requireEnd && !upper.contains("#EXT-X-ENDLIST") { throw AppFailure.message("This is a live or unfinished stream, not a complete offline episode.") }
    }
    static func inspect(_ info: StreamInfo) async throws -> (URL,Bool) {
        let url = try candidate(info)
        let hint = info.type?.lowercased() ?? ""
        let hls = url.pathExtension.lowercased() == "m3u8" || !["mp4","m4v","mov"].contains(url.pathExtension.lowercased()) && ["hls","m3u8","application/vnd.apple.mpegurl"].contains(hint)
        if hls {
            let (text,base) = try await playlist(url);try validateManifest(text,requireEnd:false)
            if text.contains("#EXT-X-STREAM-INF:") {
                let lines = text.components(separatedBy:.newlines).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
                guard let i = lines.firstIndex(where:{ $0.hasPrefix("#EXT-X-STREAM-INF:") }),let next = lines.dropFirst(i+1).first(where:{ !$0.isEmpty && !$0.hasPrefix("#") }),let variant = URL(string:next,relativeTo:base)?.absoluteURL,secure(variant.absoluteString) != nil else { throw AppFailure.message("No secure offline HLS variant was found.") }
                let (media,_) = try await playlist(variant);try validateManifest(media,requireEnd:true)
            } else { try validateManifest(text,requireEnd:true) }
        }
        return (url,!hls)
    }
    private static func playlist(_ url: URL) async throws -> (String,URL) {
        var request = URLRequest(url:url);request.timeoutInterval = 15;request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes,response) = try await URLSession.shared.bytes(for:request);try await APIClient.check(response)
        guard let final = response.url,secure(final.absoluteString) != nil,response.expectedContentLength <= 524_288 else { throw AppFailure.message("The playlist response is unsafe or too large.") }
        var data = Data();data.reserveCapacity(16_384)
        for try await byte in bytes { guard data.count < 524_288 else { throw AppFailure.message("The playlist is too large.") };data.append(byte) }
        guard let text = String(data:data,encoding:.utf8) else { throw AppFailure.message("The playlist could not be read.") };return (text,final)
    }
}

enum DownloadQueuePolicy {
    static let activeStates: Set<String> = ["resolving","resuming","downloading","verifying"]
    static func missingEpisodes(_ requested: [Int],limit: Int,existing: [DownloadItem],animeID: Int) -> [Int] {
        let saved = Set(existing.filter { $0.animeID == animeID && $0.state != "failed" }.map(\.episode))
        return Set(requested).filter { $0 > 0 && $0 <= limit && !saved.contains($0) }.sorted()
    }
    /// Download subtitle pick: the selected language first, then English, then no subtitles.
    /// A missing subtitle track must never block the video download.
    static func pickSubtitle(from info: StreamInfo,language: String) -> SubtitleTrack? {
        if let exact = info.subtitle(language: language) { return exact }
        if language != "eng", let english = info.subtitle(language: "eng") { return english }
        return nil
    }
    /// Automatic retries for transient host hiccups (5xx bursts, timeouts) before giving up.
    static let maxAutoRetries = 3
    static func retryDelay(attempt: Int) -> TimeInterval {
        switch min(3,max(1,attempt)) {
        case 1: return 8
        case 2: return 25
        default: return 60
        }
    }
    /// True when the failure is a temporary host/network problem worth retrying on its own.
    static func isTransient(_ error: Error) -> Bool {
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                 .dnsLookupFailed, .resourceUnavailable, .internationalRoamingOff, .dataNotAllowed:
                return true
            default: break
            }
        }
        let ns = error as NSError
        // CoreMedia delivery errors from HLS transfers (e.g. -16849 with an upstream HTTP 5xx).
        if ns.domain == "CoreMediaErrorDomain" { return true }
        let text = error.localizedDescription
        for marker in ["HTTP 502","HTTP 503","HTTP 504","HTTP 429","Service Unavailable","temporarily busy","timed out","The connection was lost"] {
            if text.contains(marker) { return true }
        }
        return false
    }
    /// Actionable transfer errors instead of raw NSURLErrorDomain text.
    static func friendly(_ error: Error) -> String {
        guard let url = error as? URLError else {
            let text = error.localizedDescription
            if isTransient(error) { return text.contains("HTTP 5") || text.contains("HTTP 429") ? "The video host is temporarily busy. \(text)" : text }
            return text
        }
        switch url.code {
        case .dataNotAllowed: return "This download needs Wi-Fi. Connect to Wi-Fi and retry this episode."
        case .internationalRoamingOff: return "This download needs a non-roaming connection. Retry it on a home network."
        case .notConnectedToInternet, .networkConnectionLost: return "The connection was lost. This episode retries automatically when you are back online."
        case .timedOut, .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable: return "The video host is temporarily busy. This episode retries automatically — tap Retry to try it now."
        default: return url.localizedDescription
        }
    }
}
