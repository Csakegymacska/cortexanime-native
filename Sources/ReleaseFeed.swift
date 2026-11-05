import Foundation

/// One published Hungarian episode, as listed by GET /api/app/epfeed.
///
/// The feed is the only place in the product that knows what actually got subtitles,
/// so the app uses it for the "New in Hungarian" shelf, the releases screen and the
/// widget content. AniList is only asked for the poster art of those ids.
struct CortexRelease: Identifiable, Hashable, Codable {
    let feedID: String
    let animeID: Int
    let episode: Int
    let title: String
    let airedAt: Date
    var cover: URL?

    var id: String { feedID }

    var isNewSeries: Bool { title.contains("ÚJ SOROZAT") || title.uppercased().contains("NEW SERIES") }

    var cleanTitle: String {
        title.replacingOccurrences(of: " — ÚJ SOROZAT", with: "").replacingOccurrences(of: " — NEW SERIES", with: "").replacingOccurrences(of: " - NEW SERIES", with: "")
            .replacingOccurrences(of: " - ÚJ SOROZAT", with: "")
            .replacingOccurrences(of: "ÚJ SOROZAT", with: "").replacingOccurrences(of: "NEW SERIES", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var deepLink: URL? {
        guard animeID > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
    }

    var watchLink: URL? {
        guard animeID > 0, episode > 0 else { return nil }
        return URL(string: "https://cortanime.eu/watch/\(animeID)/\(episode)")
    }

    var ageText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(airedAt)))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) h ago" }
        let days = seconds / 86_400
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(airedAt) { return "Today" }
        if calendar.isDateInYesterday(airedAt) { return "Yesterday" }
        return airedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

enum ReleaseFeedError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The release feed is unavailable right now." }
}

@MainActor final class ReleaseFeed: ObservableObject {
    static let shared = ReleaseFeed()

    @Published private(set) var items: [CortexRelease] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?
    @Published private(set) var fromCache = false

    private var lastAttempt: Date?
    private let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("cortex-releases-v1.json")
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        loadCache()
    }

    private func loadCache() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let stored = try? JSONDecoder().decode([CortexRelease].self, from: data), !stored.isEmpty else { return }
        items = stored
        if let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path) {
            updated = attributes[.modificationDate] as? Date
        }
        fromCache = true
    }

    /// Refreshes at most once every two minutes unless `force` is set.
    func load(force: Bool = false) async {
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 120 { return }
        guard !loading else { return }
        loading = true
        lastAttempt = Date()
        defer { loading = false }
        do {
            let fetched = try await fetch()
            try Task.checkCancellation()
            items = fetched
            updated = Date()
            fromCache = false
            error = nil
            if let cacheURL, let data = try? JSONEncoder().encode(fetched) {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            self.error = error.localizedDescription
            fromCache = !items.isEmpty
        }
    }

    private struct FeedPayload: Decodable {
        struct Row: Decodable {
            let id: String?
            let aid: Int
            let ep: Int
            let title: String?
            let ts: Double
        }
        let ok: Bool?
        let items: [Row]
    }

    private func fetch() async throws -> [CortexRelease] {
        guard let url = URL(string: "https://cortanime.eu/api/app/epfeed") else { throw ReleaseFeedError.unavailable }
        var request = URLRequest(url: url)
        request.setValue("CortexAnime/4.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 400_000 else {
            throw ReleaseFeedError.unavailable
        }
        let payload = try JSONDecoder().decode(FeedPayload.self, from: bytes)
        let rows = payload.items.compactMap { row -> CortexRelease? in
            guard row.aid > 0, row.ep > 0, row.ts.isFinite, row.ts > 0 else { return nil }
            let stamp = row.ts > 1_000_000_000_000 ? row.ts / 1000 : row.ts
            let title = (row.title ?? "Episode \(row.ep)").trimmingCharacters(in: .whitespacesAndNewlines)
            return CortexRelease(feedID: row.id ?? "\(row.aid)-\(row.ep)", animeID: row.aid, episode: row.ep,
                                 title: title, airedAt: Date(timeIntervalSince1970: stamp), cover: nil)
        }
        guard !rows.isEmpty else { throw ReleaseFeedError.unavailable }
        let covers = await coverMap(for: rows.map(\.animeID))
        return rows.map { row in
            var copy = row
            copy.cover = covers[row.animeID].flatMap(Anime.imageURL)
            return copy
        }
    }

    private func coverMap(for ids: [Int]) async -> [Int: String] {
        let unique = Array(Set(ids.filter { $0 > 0 })).prefix(30)
        guard !unique.isEmpty else { return [:] }
        let query = "query($ids:[Int]){Page(page:1,perPage:50){media(id_in:$ids,type:ANIME){id coverImage{large extraLarge}}}}"
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
            guard let id = row["id"] as? Int, let images = row["coverImage"] as? [String: Any],
                  let raw = images["extraLarge"] as? String ?? images["large"] as? String else { continue }
            result[id] = raw
        }
        return result
    }
}
