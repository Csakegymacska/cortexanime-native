import Foundation

enum CortexNativeAddress {
    static let scheme = "cortexanime-native-port"
    static let home = URL(string:"cortexanime-native-port://home")!
}

/// Public airing metadata only. This is not confirmation of playable video or HU subtitles.
struct CortexWidgetEpisode: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let episode: Int
    let airedAt: Date
    let cover: URL?
    var deepLink: URL? { guard id > 0 else { return nil };return URL(string:"\(CortexNativeAddress.scheme)://anime/\(id)") }

    static func parse(_ data: [String:Any],now: Date = Date()) -> [Self] {
        let rows = (data["Page"] as? [String:Any])?["airingSchedules"] as? [[String:Any]] ?? []
        var seen = Set<Int>()
        return rows.compactMap { row -> Self? in
            guard let media = row["media"] as? [String:Any],media["isAdult"] as? Bool == false,media["type"] as? String == "ANIME",
                  let id = media["id"] as? Int,id > 0,let episode = row["episode"] as? Int,episode > 0,
                  let timestamp = (row["airingAt"] as? NSNumber)?.doubleValue,timestamp.isFinite,timestamp > 0,timestamp <= now.timeIntervalSince1970,
                  let names = media["title"] as? [String:Any],
                  let title = [names["english"] as? String,names["romaji"] as? String].compactMap({ $0?.trimmingCharacters(in:.whitespacesAndNewlines) }).first(where:{ !$0.isEmpty }) else { return nil }
            let raw = (media["coverImage"] as? [String:Any])?["large"] as? String
            let cover = raw.flatMap { URL(string:$0) }.flatMap { url -> URL? in
                guard url.scheme == "https",url.host != nil,url.user == nil,url.password == nil else { return nil };return url
            }
            return Self(id:id,title:String(title.prefix(180)),episode:episode,airedAt:Date(timeIntervalSince1970:timestamp),cover:cover)
        }.sorted { $0.airedAt == $1.airedAt ? $0.id < $1.id : $0.airedAt > $1.airedAt }
            .filter { seen.insert($0.id).inserted }
    }
}

struct CortexWidgetSnapshot: Codable, Sendable {
    let fetchedAt: Date
    let items: [CortexWidgetEpisode]
}

enum CortexWidgetFeedError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Current episode data is unavailable." }
}

/// Independent extension cache: deliberately no App Group, Keychain or account cookie dependency.
struct CortexWidgetFeedClient: Sendable {
    let session: URLSession
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false;config.httpCookieStorage = nil;config.httpCookieAcceptPolicy = .never
        config.urlCache = nil;config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8;config.timeoutIntervalForResource = 12
        self.session = session ?? URLSession(configuration:config)
    }
    func fetch(now: Date = Date()) async throws -> CortexWidgetSnapshot {
        var request = URLRequest(url:URL(string:"https://graphql.anilist.co")!)
        request.httpMethod = "POST";request.httpShouldHandleCookies = false
        request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject:["query":MetadataQueries.latestEpisodes,"variables":["now":Int(now.timeIntervalSince1970)]])
        let (bytes,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse,(200..<300).contains(http.statusCode),bytes.count <= 1_000_000,
              let root = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              (root["errors"] as? [[String:Any]] ?? []).isEmpty,let data = root["data"] as? [String:Any] else { throw CortexWidgetFeedError.unavailable }
        let items = Array(CortexWidgetEpisode.parse(data,now:now).prefix(10))
        guard !items.isEmpty else { throw CortexWidgetFeedError.unavailable }
        return CortexWidgetSnapshot(fetchedAt:now,items:items)
    }
    func artwork(for item: CortexWidgetEpisode) async -> Data? {
        guard let url = item.cover,url.scheme == "https",url.host != nil,url.user == nil,url.password == nil else { return nil }
        var request = URLRequest(url:url);request.timeoutInterval = 5;request.httpShouldHandleCookies = false
        guard let (bytes,response) = try? await session.data(for:request),let http = response as? HTTPURLResponse,http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true,bytes.count <= 750_000 else { return nil }
        return bytes
    }
}
