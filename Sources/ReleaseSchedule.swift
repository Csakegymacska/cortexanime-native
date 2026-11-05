import Combine
import Foundation
import UserNotifications

/// The airing calendar behind "the banner arrived while the app was closed".
///
/// A local notification can only be created while the app is running — unless it was
/// handed to the system earlier. iOS fires a scheduled request on its own, even after
/// days without a launch, so every moment of runtime is used here to keep the next
/// weeks of followed series sitting in the system queue.
@MainActor final class ReleaseSchedule: ObservableObject {
    static let shared = ReleaseSchedule()

    /// Airing time plus the typical wait for a published subtitle. Measured on a real
    /// drop: the episode aired at 16:20 UTC and the Hungarian track was live at 16:31.
    static let lead: TimeInterval = 15 * 60
    static let identifierPrefix = "airing-"
    static let maximumPending = 20
    static let horizon: TimeInterval = 21 * 86_400
    static let cacheKey = "alerts.airing.v1"

    struct Slot: Codable, Hashable, Sendable {
        let animeID: Int
        let episode: Int
        let airingAt: Date
    }

    @Published private(set) var slots: [Slot] = []

    private let defaults = UserDefaults.standard
    private var lastRefresh: Date?
    private var refreshing = false

    init() {
        if let data = defaults.data(forKey: Self.cacheKey),
           let stored = try? JSONDecoder().decode([Slot].self, from: data) {
            slots = stored
        }
        lastRefresh = defaults.object(forKey: Self.cacheKey + ".at") as? Date
    }

    /// What is already queued in iOS, soonest first.
    var queued: [Slot] {
        slots.filter { $0.airingAt > Date() }.sorted { $0.airingAt < $1.airingAt }
    }

    /// Asks the airing calendar for every followed series and re-places the queued banners.
    /// Throttled to one fetch every three hours unless `force` is set.
    @discardableResult
    func refresh(follows: [FollowedSeries], force: Bool = false) async -> Int {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return 0 }
        let ids = follows.filter(\.notificationsOn).map(\.animeID)
        guard !ids.isEmpty, !refreshing else { return queued.count }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 3 * 3600 {
            return queued.count
        }
        refreshing = true
        defer { refreshing = false }

        let previous = slots
        let fetched = await airingSlots(for: ids)
        if !fetched.isEmpty {
            slots = fetched
            if let data = try? JSONEncoder().encode(fetched) { defaults.set(data, forKey: Self.cacheKey) }
            lastRefresh = Date()
            defaults.set(lastRefresh, forKey: Self.cacheKey + ".at")
        }
        await place(follows: follows, replacing: previous)
        return queued.count
    }

    /// Drops every queued banner for a series that was unfollowed or muted.
    func cancel(animeID: Int) {
        let doomed = slots.filter { $0.animeID == animeID }.map { Self.identifier(for: $0) }
        slots.removeAll { $0.animeID == animeID }
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: doomed)
    }

    // MARK: Placement

    private func place(follows: [FollowedSeries], replacing previous: [Slot] = []) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: previous.map { Self.identifier(for: $0) })

        let now = Date()
        let muted = Set(follows.filter { !$0.notificationsOn }.map(\.animeID))
        var covers: [Int: URL] = [:]
        var titles: [Int: String] = [:]
        for follow in follows {
            titles[follow.animeID] = follow.title
            if let cover = follow.coverURL { covers[follow.animeID] = cover }
        }

        let upcoming = slots
            .filter { !muted.contains($0.animeID) }
            .filter { $0.airingAt.addingTimeInterval(Self.lead) > now }
            .filter { $0.airingAt.timeIntervalSince(now) < Self.horizon }
            .sorted { $0.airingAt == $1.airingAt ? $0.animeID < $1.animeID : $0.airingAt < $1.airingAt }
            .prefix(Self.maximumPending)

        for slot in upcoming {
            let fireAt = slot.airingAt.addingTimeInterval(Self.lead)
            let identifier = Self.identifier(for: slot)
            let alert = RichAlert(
                animeID: slot.animeID,
                title: titles[slot.animeID] ?? "Episode \(slot.episode)",
                episode: slot.episode,
                kicker: "Episode \(slot.episode) · \(slot.airingAt.formatted(.dateTime.hour().minute()))",
                body: "The episode is out. Hungarian subtitles usually follow within minutes — tap to check.",
                deepLink: URL(string: "\(CortexNativeAddress.scheme)://anime/\(slot.animeID)"),
                cover: covers[slot.animeID],
                category: AlertCategory.episode,
                identifier: identifier,
                badge: nil
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt),
                repeats: false
            )
            let content = await alert.content()
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    // MARK: Airing calendar

    private func airingSlots(for ids: [Int]) async -> [Slot] {
        let query = "query($ids:[Int]){Page(page:1,perPage:50){media(id_in:$ids,type:ANIME){id nextAiringEpisode{episode airingAt}}}}"
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co") ?? URL(fileURLWithPath: "/"))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": ["ids": ids]])
        let session = URLSession(configuration: .ephemeral)

        guard let (bytes, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 400_000,
              let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let page = data["Page"] as? [String: Any],
              let media = page["media"] as? [[String: Any]] else { return [] }

        var result: [Slot] = []
        for row in media {
            guard let id = row["id"] as? Int,
                  let next = row["nextAiringEpisode"] as? [String: Any],
                  let episode = next["episode"] as? Int,
                  let stamp = next["airingAt"] as? Double, stamp > 0 else { continue }
            result.append(Slot(animeID: id, episode: episode, airingAt: Date(timeIntervalSince1970: stamp)))
        }
        return result
    }

    // MARK: Helpers

    private static func identifier(for slot: Slot) -> String {
        identifierPrefix + "\(slot.animeID)-\(slot.episode)"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(slots) { defaults.set(data, forKey: Self.cacheKey) }
    }
}
