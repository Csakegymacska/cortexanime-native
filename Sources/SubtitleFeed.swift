import Foundation
import SwiftUI
import UserNotifications

// MARK: - Language
//
// 6.0: a subtitle is no longer automatically Hungarian. Every drop now carries the
// language it was published in, so the alerts can be turned on per language and the
// widgets can badge a row with HU or EN instead of guessing.

enum SubtitleLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case hungarian = "hu"
    case english = "en"

    var id: String { rawValue }
    var name: String { self == .hungarian ? "Hungarian" : "English" }
    var badge: String { rawValue.uppercased() }
    var headline: String { self == .hungarian ? "New Hungarian subtitle" : "New English subtitle" }
    var symbol: String { self == .hungarian ? "character.book.closed.fill" : "globe.europe.africa.fill" }

    var color: Color {
        self == .hungarian
            ? Color(red: 0.34, green: 0.90, blue: 0.63)
            : Color(red: 0.36, green: 0.66, blue: 1.00)
    }
}

// MARK: - Model

/// One published subtitle track, as returned by GET /api/app/subfeed.
struct SubtitleDrop: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let animeID: Int
    let episode: Int
    let language: SubtitleLanguage
    let title: String
    let at: Date
    var cover: URL?

    var deepLink: URL? {
        guard animeID > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
    }

    var watchLink: URL? {
        guard animeID > 0, episode > 0 else { return nil }
        return URL(string: "https://cortanime.eu/watch/\(animeID)/\(episode)")
    }

    var episodeText: String { "Episode \(episode)" }

    var ageText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(at)))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        let days = seconds / 86_400
        return days == 1 ? "yesterday" : "\(days)d ago"
    }

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(at) { return "Today" }
        if calendar.isDateInYesterday(at) { return "Yesterday" }
        return at.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// MARK: - Preferences

/// What the viewer asked for in Settings → Notifications. Pure data so the planner can be
/// exercised in a unit test without UserDefaults, a network or a notification centre.
struct SubtitleAlertPreferences: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var hungarian: Bool = true
    var english: Bool = false
    var followedOnly: Bool = false

    var languages: [SubtitleLanguage] {
        var result: [SubtitleLanguage] = []
        if hungarian { result.append(.hungarian) }
        if english { result.append(.english) }
        return result
    }

    var isSilent: Bool { !enabled || languages.isEmpty }

    var summary: String {
        guard enabled else { return "Off" }
        let names = languages.map(\.name)
        guard !names.isEmpty else { return "No language selected" }
        return names.joined(separator: " + ") + (followedOnly ? " · followed series" : " · every series")
    }
}

@MainActor final class SubtitleAlertSettings: ObservableObject {
    static let shared = SubtitleAlertSettings()
    static let preferencesKey = "alerts.subtitles.preferences.v1"
    static let seenKey = "alerts.subtitles.seen.v1"
    static let checkKey = "alerts.subtitles.lastCheck.v1"

    @Published var enabled: Bool { didSet { persist() } }
    @Published var hungarian: Bool { didSet { persist() } }
    @Published var english: Bool { didSet { persist() } }
    @Published var followedOnly: Bool { didSet { persist() } }
    @Published private(set) var seen: [String: Double]
    @Published private(set) var lastCheck: Date?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.preferencesKey)
            .flatMap { try? JSONDecoder().decode(SubtitleAlertPreferences.self, from: $0) }
            ?? SubtitleAlertPreferences()
        enabled = stored.enabled
        hungarian = stored.hungarian
        english = stored.english
        followedOnly = stored.followedOnly
        seen = defaults.data(forKey: Self.seenKey)
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        lastCheck = defaults.object(forKey: Self.checkKey) as? Date
    }

    var preferences: SubtitleAlertPreferences {
        SubtitleAlertPreferences(enabled: enabled, hungarian: hungarian, english: english, followedOnly: followedOnly)
    }

    func setLanguage(_ language: SubtitleLanguage, on: Bool) {
        switch language {
        case .hungarian: hungarian = on
        case .english: english = on
        }
    }

    func isOn(_ language: SubtitleLanguage) -> Bool {
        language == .hungarian ? hungarian : english
    }

    func commit(seen next: [String: Double], checkedAt: Date = Date()) {
        guard next != seen else {
            lastCheck = checkedAt
            defaults.set(checkedAt, forKey: Self.checkKey)
            return
        }
        seen = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.seenKey) }
        lastCheck = checkedAt
        defaults.set(checkedAt, forKey: Self.checkKey)
    }

    /// Used by the "forget what I have seen" row: the next check silently re-seeds.
    func resetWatermarks() {
        seen = [:]
        defaults.removeObject(forKey: Self.seenKey)
    }

    private func persist() {
        let value = preferences
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.preferencesKey) }
    }
}

// MARK: - Planner
//
// The whole "did something new land, and should it ring" contract lives here as a pure
// function: no UserDefaults, no UNUserNotificationCenter, no network. The store below
// only feeds it data and delivers whatever comes back.

enum SubtitleAlertPlanner {
    struct Hit: Identifiable, Hashable, Sendable {
        let animeID: Int
        let episode: Int
        let language: SubtitleLanguage
        let title: String
        let at: Date

        var id: String { "\(language.rawValue)-\(animeID)-\(episode)" }
        var key: String { "\(language.rawValue)-\(animeID)" }
        var headline: String { language.headline }
        var body: String { "\(title) — Episode \(episode)" }

        var deepLink: URL? {
            guard animeID > 0 else { return nil }
            return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
        }
    }

    struct Result: Equatable, Sendable {
        var hits: [Hit]
        var seen: [String: Double]
        /// First run on a device: everything currently published is old news.
        var seeded: Bool
    }

    static func plan(drops: [SubtitleDrop],
                     preferences: SubtitleAlertPreferences,
                     followed: Set<Int>,
                     seen: [String: Double]) -> Result {
        guard !drops.isEmpty else { return Result(hits: [], seen: seen, seeded: false) }
        let wanted = preferences.languages
        // The newest drop of each (language, series) pair is the one worth a banner: a
        // series that jumps three episodes is still one notification.
        var best: [String: SubtitleDrop] = [:]
        for drop in drops where drop.animeID > 0 && drop.episode > 0 {
            guard !wanted.isEmpty, wanted.contains(drop.language) else { continue }
            let key = "\(drop.language.rawValue)-\(drop.animeID)"
            if let current = best[key], current.episode >= drop.episode { continue }
            best[key] = drop
        }
        guard !best.isEmpty else { return Result(hits: [], seen: seen, seeded: false) }
        let seeding = seen.isEmpty
        var next = seen
        var hits: [Hit] = []
        for (key, drop) in best {
            let watermark = seen[key] ?? 0
            let eligible = preferences.enabled && !wanted.isEmpty
                && (!preferences.followedOnly || followed.contains(drop.animeID))
            if !seeding, eligible, Double(drop.episode) > watermark {
                hits.append(Hit(animeID: drop.animeID, episode: drop.episode, language: drop.language,
                                title: drop.title, at: drop.at))
            }
            // Watermarks advance for every language-matching series, followed or not, so
            // switching "only followed series" off later cannot release a backlog.
            next[key] = max(watermark, Double(drop.episode))
        }
        hits.sort { $0.at == $1.at ? $0.animeID < $1.animeID : $0.at > $1.at }
        return Result(hits: Array(hits.prefix(5)), seen: next, seeded: seeding)
    }
}

// MARK: - Feed

@MainActor final class SubtitleFeed: ObservableObject {
    static let shared = SubtitleFeed()
    static let endpoint = "https://cortanime.eu/api/app/subfeed"

    @Published private(set) var drops: [SubtitleDrop] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?
    @Published private(set) var fromCache = false

    private var lastAttempt: Date?
    private let session: URLSession
    private var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("cortex-subtitles-v1.json")
    }

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        loadCache()
    }

    private func loadCache() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let stored = try? JSONDecoder().decode([SubtitleDrop].self, from: data), !stored.isEmpty else { return }
        drops = stored
        fromCache = true
        if let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path) {
            updated = attributes[.modificationDate] as? Date
        }
    }

    func load(force: Bool = false, days: Int = 14) async {
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 90 { return }
        guard !loading else { return }
        loading = true
        lastAttempt = Date()
        defer { loading = false }
        do {
            let fetched = try await fetch(days: days)
            try Task.checkCancellation()
            guard !fetched.isEmpty else {
                error = "No subtitle drops in the last \(days) days."
                return
            }
            drops = fetched
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
            fromCache = !drops.isEmpty
        }
    }

    func recent(days: Int = 7, languages: Set<SubtitleLanguage> = Set(SubtitleLanguage.allCases), limit: Int = 20) -> [SubtitleDrop] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return drops
            .filter { $0.at >= cutoff && languages.contains($0.language) }
            .sorted { $0.at > $1.at }
            .prefix(limit)
            .map { $0 }
    }

    func count(language: SubtitleLanguage, days: Int = 7) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return drops.filter { $0.language == language && $0.at >= cutoff }.count
    }

    var latest: SubtitleDrop? { drops.first }

    private struct Payload: Decodable {
        struct Row: Decodable {
            let id: String?
            let aid: Int
            let ep: Int
            let lang: String?
            let ts: Double
            let title: String?
        }
        let ok: Bool?
        let items: [Row]
    }

    private func fetch(days: Int) async throws -> [SubtitleDrop] {
        guard var components = URLComponents(string: Self.endpoint) else { throw ReleaseFeedError.unavailable }
        components.queryItems = [
            URLQueryItem(name: "lang", value: "hu,en"),
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "limit", value: "80"),
        ]
        guard let url = components.url else { throw ReleaseFeedError.unavailable }
        var request = URLRequest(url: url)
        request.setValue("CortexAnime/6.4", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 600_000 else {
            throw ReleaseFeedError.unavailable
        }
        let payload = try JSONDecoder().decode(Payload.self, from: bytes)
        let rows = payload.items.compactMap { row -> SubtitleDrop? in
            guard row.aid > 0, row.ep > 0, row.ts.isFinite, row.ts > 0 else { return nil }
            let language = SubtitleLanguage(rawValue: (row.lang ?? "hu").lowercased()) ?? .hungarian
            let stamp = row.ts > 1_000_000_000_000 ? row.ts / 1000 : row.ts
            let title = (row.title ?? "Episode \(row.ep)").trimmingCharacters(in: .whitespacesAndNewlines)
            return SubtitleDrop(id: row.id ?? "\(row.aid)-\(row.ep)-\(language.rawValue)",
                                animeID: row.aid, episode: row.ep, language: language,
                                title: title, at: Date(timeIntervalSince1970: stamp), cover: nil)
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
        let unique = Array(Set(ids.filter { $0 > 0 })).prefix(40)
        guard !unique.isEmpty else { return [:] }
        let query = "query($ids:[Int]){Page(page:1,perPage:50){media(id_in:$ids,type:ANIME){id coverImage{extraLarge large}}}}"
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": ["ids": Array(unique)]])
        guard let (bytes, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 500_000,
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

// MARK: - Alert centre integration

extension AlertCenter {
    /// Compares the published subtitle feed against what this device already knows and
    /// delivers one banner per series per language. Called from the app becoming active and
    /// from the background refresh task, so no server-side subscription is involved.
    @discardableResult
    func checkSubtitles(notify: Bool = true) async -> [SubtitleAlertPlanner.Hit] {
        let settings = SubtitleAlertSettings.shared
        guard settings.enabled, !settings.preferences.languages.isEmpty else { return [] }
        let feed = SubtitleFeed.shared
        await feed.load(force: true)
        guard !feed.drops.isEmpty else { return [] }
        let followed = Set(follows.map(\.animeID))
        let result = SubtitleAlertPlanner.plan(drops: feed.drops, preferences: settings.preferences,
                                               followed: followed, seen: settings.seen)
        settings.commit(seen: result.seen)
        guard !result.seeded, !result.hits.isEmpty else { return [] }
        if notify { await deliverSubtitles(result.hits) }
        return result.hits
    }

    private func deliverSubtitles(_ hits: [SubtitleAlertPlanner.Hit]) async {
        await loadAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }
        let published = SubtitleFeed.shared.drops
        for hit in hits.prefix(5) {
            let cover = published.first {
                $0.animeID == hit.animeID && $0.episode == hit.episode && $0.language == hit.language
            }?.cover
            let alert = RichAlert(
                animeID: hit.animeID,
                title: hit.title,
                episode: hit.episode,
                kicker: "Episode \(hit.episode) · \(hit.language.name) subtitle",
                body: "\(hit.language.headline) is live. Tap to watch.",
                deepLink: hit.deepLink,
                cover: cover,
                category: AlertCategory.subtitle,
                identifier: "subtitle-\(hit.id)",
                badge: nil
            )
            let content = await alert.content()
            try? await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: "subtitle-\(hit.id)", content: content, trigger: nil))
        }
    }
}
