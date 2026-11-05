import Foundation
import UIKit
import ImageIO

// MARK: - Models
//
// The widgets are deliberately self-contained: no App Group, no keychain, no account
// cookies. Everything they show comes from public CortexAnime/AniList endpoints and is
// cached inside the extension container, so signing with any certificate keeps working.

/// One freshly released Hungarian-subtitled episode, straight from /api/app/epfeed.
struct CortexReleaseItem: Codable, Hashable, Identifiable, Sendable {
    let animeID: Int
    let episode: Int
    let title: String
    let airedAt: Date
    let cover: String?

    var id: Int { animeID * 1000 + episode }
    /// The feed marks brand new series with a suffix; the UI shows that as its own chip.
    var isNewSeries: Bool { title.contains("ÚJ SOROZAT") }
    var cleanTitle: String {
        title.replacingOccurrences(of: " — ÚJ SOROZAT", with: "")
            .replacingOccurrences(of: " - ÚJ SOROZAT", with: "")
            .replacingOccurrences(of: "ÚJ SOROZAT", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var coverURL: URL? {
        guard let cover, let url = URL(string: cover), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    var deepLink: URL? {
        guard animeID > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
    }
}

/// One confirmed airing from AniList, used by the "Latest airings" widget.
struct CortexAiringItem: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let episode: Int
    let airedAt: Date
    let cover: String?

    var coverURL: URL? {
        guard let cover, let url = URL(string: cover), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    var deepLink: URL? {
        guard id > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(id)")
    }
    /// Minutes still left until the next episode of the same series is out, when known.
    var relativeAge: String {
        let seconds = max(0, Int(Date().timeIntervalSince(airedAt)))
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}


/// 6.0: a subtitle drop that carries its language, so a widget row can say HU or EN.
struct CortexSubtitleItem: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let animeID: Int
    let episode: Int
    let lang: String
    let title: String
    let at: Date
    let cover: String?

    var language: String { lang.lowercased() == "en" ? "en" : "hu" }
    var languageName: String { language == "en" ? "English" : "Hungarian" }
    var badge: String { language.uppercased() }
    var coverURL: URL? {
        guard let cover, let url = URL(string: cover), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    var deepLink: URL? {
        guard animeID > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
    }
    var ageText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(at)))
        if seconds < 3_600 { return "\(max(1, seconds / 60))m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

enum CortexWidgetFetchError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Current episode data is unavailable." }
}

// MARK: - Client

struct CortexWidgetClient: Sendable {
    let session: URLSession

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = session ?? URLSession(configuration: config)
    }

    // /api/app/epfeed -> newest Hungarian episodes, already sorted newest first.
    private struct ReleasePayload: Decodable {
        struct Row: Decodable { let id: String; let aid: Int; let ep: Int; let title: String?; let ts: Double }
        let ok: Bool?
        let items: [Row]
    }

    func releases(now: Date = Date()) async throws -> [CortexReleaseItem] {
        guard let url = URL(string: "https://cortanime.eu/api/app/epfeed") else { throw CortexWidgetFetchError.unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("CortexAnimeWidget/4.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 400_000 else {
            throw CortexWidgetFetchError.unavailable
        }
        let payload = try JSONDecoder().decode(ReleasePayload.self, from: bytes)
        let rows = payload.items.prefix(24).compactMap { row -> CortexReleaseItem? in
            guard row.aid > 0, row.ep > 0, row.ts.isFinite, row.ts > 0 else { return nil }
            let date = Date(timeIntervalSince1970: row.ts / 1000)
            guard date <= now.addingTimeInterval(3600) else { return nil }
            let title = (row.title ?? "Episode \(row.ep)").trimmingCharacters(in: .whitespacesAndNewlines)
            return CortexReleaseItem(animeID: row.aid, episode: row.ep, title: title, airedAt: date, cover: nil)
        }
        guard !rows.isEmpty else { throw CortexWidgetFetchError.unavailable }
        let covers = await covers(for: rows.map(\.animeID))
        return rows.map { item in
            CortexReleaseItem(animeID: item.animeID, episode: item.episode, title: item.title,
                              airedAt: item.airedAt, cover: covers[item.animeID])
        }
    }

    // /api/app/subfeed -> Hungarian and English drops in one list, newest first.
    private struct SubtitlePayload: Decodable {
        struct Row: Decodable { let id: String?; let aid: Int; let ep: Int; let lang: String?; let ts: Double; let title: String? }
        let ok: Bool?
        let items: [Row]
    }

    func subtitles(days: Int = 14) async throws -> [CortexSubtitleItem] {
        guard var components = URLComponents(string: "https://cortanime.eu/api/app/subfeed") else { throw CortexWidgetFetchError.unavailable }
        components.queryItems = [
            URLQueryItem(name: "lang", value: "hu,en"),
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "limit", value: "60"),
        ]
        guard let url = components.url else { throw CortexWidgetFetchError.unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("CortexAnimeWidget/6.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 600_000 else {
            throw CortexWidgetFetchError.unavailable
        }
        let payload = try JSONDecoder().decode(SubtitlePayload.self, from: bytes)
        var seen = Set<Int>()
        let rows = payload.items.prefix(40).compactMap { row -> CortexSubtitleItem? in
            guard row.aid > 0, row.ep > 0, row.ts.isFinite, row.ts > 0 else { return nil }
            let stamp = row.ts > 1_000_000_000_000 ? row.ts / 1000 : row.ts
            let key = row.aid * 10 + (row.lang == "en" ? 1 : 0)
            guard seen.insert(key).inserted else { return nil }
            let title = (row.title ?? "Episode \(row.ep)").trimmingCharacters(in: .whitespacesAndNewlines)
            return CortexSubtitleItem(id: key, animeID: row.aid, episode: row.ep, lang: row.lang ?? "hu",
                                      title: title, at: Date(timeIntervalSince1970: stamp), cover: nil)
        }
        guard !rows.isEmpty else { throw CortexWidgetFetchError.unavailable }
        let covers = await covers(for: rows.map(\.animeID))
        return rows.map { item in
            CortexSubtitleItem(id: item.id, animeID: item.animeID, episode: item.episode, lang: item.lang,
                               title: item.title, at: item.at, cover: covers[item.animeID])
        }
    }

    /// One small AniList request turns the bare feed ids into posters.
    private func covers(for ids: [Int]) async -> [Int: String] {
        let unique = Array(Set(ids.filter { $0 > 0 })).prefix(20)
        guard !unique.isEmpty else { return [:] }
        let query = "query($ids:[Int]){Page(page:1,perPage:30){media(id_in:$ids,type:ANIME){id coverImage{large extraLarge}}}}"
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": ["ids": Array(unique)]])
        guard let (bytes, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 400_000,
              let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let page = data["Page"] as? [String: Any],
              let media = page["media"] as? [[String: Any]] else { return [:] }
        var result: [Int: String] = [:]
        for row in media {
            guard let id = row["id"] as? Int,
                  let images = row["coverImage"] as? [String: Any],
                  let raw = images["extraLarge"] as? String ?? images["large"] as? String,
                  let url = URL(string: raw), url.scheme == "https" else { continue }
            result[id] = raw
        }
        return result
    }

    func airings(now: Date = Date()) async throws -> [CortexAiringItem] {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": MetadataQueries.latestEpisodes,
            "variables": ["now": Int(now.timeIntervalSince1970)],
        ])
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 1_000_000,
              let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              (root["errors"] as? [[String: Any]] ?? []).isEmpty,
              let data = root["data"] as? [String: Any],
              let page = data["Page"] as? [String: Any],
              let rows = page["airingSchedules"] as? [[String: Any]] else { throw CortexWidgetFetchError.unavailable }
        var seen = Set<Int>()
        let items: [CortexAiringItem] = rows.compactMap { row in
            guard let media = row["media"] as? [String: Any],
                  media["isAdult"] as? Bool == false,
                  media["type"] as? String == "ANIME",
                  let id = media["id"] as? Int, id > 0,
                  let episode = row["episode"] as? Int, episode > 0,
                  let timestamp = (row["airingAt"] as? NSNumber)?.doubleValue,
                  timestamp.isFinite, timestamp > 0,
                  let names = media["title"] as? [String: Any],
                  let title = [names["english"] as? String, names["romaji"] as? String]
                    .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .first(where: { !$0.isEmpty }),
                  seen.insert(id).inserted else { return nil }
            let cover = (media["coverImage"] as? [String: Any])?["large"] as? String
            return CortexAiringItem(id: id, title: String(title.prefix(180)), episode: episode,
                                    airedAt: Date(timeIntervalSince1970: timestamp), cover: cover)
        }
        guard !items.isEmpty else { throw CortexWidgetFetchError.unavailable }
        return items
    }

    func artwork(_ raw: String?, maxPixel: Int) async -> Data? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (bytes, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true, bytes.count <= 900_000,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.86)
    }
}

// MARK: - On-device cache

/// Keeps the last good payload inside the extension container so a dead network still
/// shows yesterday's list instead of an empty widget.
enum CortexWidgetCache {
    static func url(_ name: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("cortex-widget-" + name + ".json")
    }
    static func save<T: Encodable>(_ value: T, name: String) {
        guard let url = url(name), let data = try? JSONEncoder().encode(value), data.count <= 400_000 else { return }
        try? data.write(to: url, options: .atomic)
    }
    static func load<T: Decodable>(_ type: T.Type, name: String, maxAge: TimeInterval) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url), data.count <= 400_000,
              let value = try? JSONDecoder().decode(type, from: data) else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) <= maxAge else { return nil }
        return value
    }
}
