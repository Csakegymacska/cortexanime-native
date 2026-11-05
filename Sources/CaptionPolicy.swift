import Foundation

/// Reject positively identified non-dialogue files, not tracks that merely timed out.
enum CaptionPolicy {
    struct Prepared { let tracks: [SubtitleTrack];let data: [String:Data] }
    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)
    static func matches(_ track: SubtitleTrack,language: String) -> Bool {
        let pattern = language == "hun" ? "magyar|hungarian|^hu[n]?$" : language == "fra" ? "français|french|^fr[a]?$" : "english|^en[g]?$"
        return track.url != nil && track.label.range(of:pattern,options:[.regularExpression,.caseInsensitive]) != nil
    }
    static func language(_ track: SubtitleTrack) -> String? { ["hun","eng","fra"].first { matches(track,language:$0) } }
    static func prepare(_ tracks: [SubtitleTrack],language: String,fetch: Fetch = { try await URLSession.shared.data(for:$0) }) async throws -> Prepared {
        let candidates = tracks.filter { matches($0,language:language) }
        guard !candidates.isEmpty else { return Prepared(tracks:tracks,data:[:]) }
        let deadline = Date().addingTimeInterval(15)
        var valid: [String:Data] = [:], invalid = Set<String>()
        for track in candidates.prefix(8) {
            try Task.checkCancellation()
            guard let url = track.url,deadline.timeIntervalSinceNow > 0 else { break }
            do {
                var request = URLRequest(url:url);request.timeoutInterval = min(5,max(1,deadline.timeIntervalSinceNow));request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data,response) = try await fetch(request)
                // A failed request is not evidence that a subtitle track does not exist.
                guard let http = response as? HTTPURLResponse,(200..<300).contains(http.statusCode),data.count <= 2_000_000,let text = String(data:data,encoding:.utf8) else { continue }
                if !WebVTT.parse(text).isEmpty { valid[track.file] = data }
                else if text.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("WEBVTT") { invalid.insert(track.file) }
            } catch { if Task.isCancelled { throw CancellationError() } }
        }
        try Task.checkCancellation()
        // Prefer verified dialogue, but retain unverified candidates for player-side retry.
        let kept = tracks.enumerated().filter { !invalid.contains($0.element.file) }.sorted {
            let a = valid[$0.element.file] != nil,b = valid[$1.element.file] != nil
            return a == b ? $0.offset < $1.offset : a
        }.map(\.element)
        return Prepared(tracks:kept,data:valid)
    }
}
