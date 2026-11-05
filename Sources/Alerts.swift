import Foundation
import SwiftUI
import UserNotifications
import BackgroundTasks

// MARK: - Model

/// One series the viewer follows. Device-local, no account required.
struct FollowedSeries: Codable, Identifiable, Hashable, Sendable {
    let animeID: Int
    var title: String
    var cover: String?
    /// Highest episode number CortexAnime has already published for this series.
    var lastEpisode: Int
    var followedAt: Date
    var notificationsOn: Bool

    var id: Int { animeID }
    var coverURL: URL? { Anime.imageURL(cover) }
    var deepLink: URL? {
        guard animeID > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
    }
}

struct EpisodeAlertHit: Identifiable, Hashable, Sendable {
    let animeID: Int
    let title: String
    let episode: Int
    let at: Date
    var id: String { "\(animeID)-\(episode)" }
    var deepLink: URL? {
        guard animeID > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
    }
}

/// The comparison itself is pure so it can be tested without a network, a user or a notification centre.
enum AlertPlanner {
    /// Returns the new episodes worth a notification plus follows with an advanced watermark.
    /// Only the highest new episode of a series is announced: coming back to five episodes at once
    /// should not fire five separate banners.
    static func plan(follows: [FollowedSeries], releases: [CortexRelease]) -> (hits: [EpisodeAlertHit], updated: [FollowedSeries]) {
        guard !follows.isEmpty, !releases.isEmpty else { return ([], follows) }
        var latest: [Int: CortexRelease] = [:]
        for item in releases where item.animeID > 0 && item.episode > 0 {
            if let current = latest[item.animeID], current.episode >= item.episode { continue }
            latest[item.animeID] = item
        }
        var hits: [EpisodeAlertHit] = []
        var updated = follows
        for index in updated.indices {
            let follow = updated[index]
            guard let release = latest[follow.animeID], release.episode > follow.lastEpisode else { continue }
            updated[index].lastEpisode = release.episode
            if follow.notificationsOn {
                hits.append(EpisodeAlertHit(animeID: follow.animeID, title: follow.title, episode: release.episode, at: release.airedAt))
            }
        }
        hits.sort { $0.at == $1.at ? $0.animeID < $1.animeID : $0.at > $1.at }
        return (hits, updated)
    }

    /// Baseline watermark for a newly followed series: never announce what already exists.
    static func baseline(for anime: Anime, releases: [CortexRelease]) -> Int {
        let fromFeed = releases.filter { $0.animeID == anime.id }.map(\.episode).max() ?? 0
        return max(fromFeed, anime.availableEpisodes ?? 0)
    }
}

// MARK: - Notification delegate

/// Kept separate from the centre so the delegate methods stay nonisolated and the store stays
/// main-actor bound. A tapped notification simply hands its deep link back to the app.
final class CortexNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let identifier = response.notification.request.identifier
        let animeID = content.userInfo["aid"] as? Int ?? 0

        switch response.actionIdentifier {
        case AlertCategory.muteAction:
            guard animeID > 0 else { return }
            await MainActor.run { AlertCenter.shared.setNotifications(false, for: animeID) }

        case AlertCategory.laterAction:
            // Snoozing keeps the same dressed banner — cover, subtitle, buttons — one hour out.
            guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
            let request = UNNotificationRequest(
                identifier: identifier + "-snooze-\(Int(Date().timeIntervalSince1970))",
                content: copy,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
            )
            try? await UNUserNotificationCenter.current().add(request)

        default:
            guard let raw = content.userInfo["url"] as? String,
                  let url = URL(string: raw) else { return }
            await MainActor.run { AlertCenter.shared.pendingLink = url }
        }
    }
}

// MARK: - Store

@MainActor final class AlertCenter: ObservableObject {
    static let shared = AlertCenter()
    static let backgroundIdentifier = "eu.cortex.anime.port.refresh"
    static let followKey = "alerts.follows.v1"
    static let checkKey = "alerts.lastCheck.v1"

    @Published private(set) var follows: [FollowedSeries]
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastCheck: Date?
    @Published private(set) var recent: [EpisodeAlertHit] = []
    @Published private(set) var checking = false
    @Published var pendingLink: URL?

    /// Under XCTest the system prompt and the scheduler are off-limits: the store must stay testable.
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private static let delegate = CortexNotificationDelegate()
    private var configured = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded = defaults.data(forKey: Self.followKey).flatMap { try? JSONDecoder().decode([FollowedSeries].self, from: $0) } ?? []
        follows = decoded.sorted { $0.followedAt > $1.followedAt }
        lastCheck = defaults.object(forKey: Self.checkKey) as? Date
    }

    // MARK: Follows

    func isFollowing(_ animeID: Int) -> Bool { follows.contains { $0.animeID == animeID } }

    func follow(_ anime: Anime, releases: [CortexRelease]? = nil) {
        let feed = releases ?? ReleaseFeed.shared.items
        guard anime.id > 0, !isFollowing(anime.id) else { return }
        let entry = FollowedSeries(animeID: anime.id,
                                   title: anime.title,
                                   cover: anime.cover?.absoluteString,
                                   lastEpisode: AlertPlanner.baseline(for: anime, releases: feed),
                                   followedAt: Date(),
                                   notificationsOn: true)
        follows.insert(entry, at: 0)
        persist()
        scheduleBackgroundRefresh()
        if authorization == .notDetermined { Task { await requestAuthorization() } }
    }

    func unfollow(_ animeID: Int) {
        follows.removeAll { $0.animeID == animeID }
        persist()
        ReleaseSchedule.shared.cancel(animeID: animeID)
    }

    func toggle(_ anime: Anime, releases: [CortexRelease]? = nil) {
        if isFollowing(anime.id) { unfollow(anime.id) } else { follow(anime, releases: releases) }
    }

    func setNotifications(_ enabled: Bool, for animeID: Int) {
        guard let index = follows.firstIndex(where: { $0.animeID == animeID }) else { return }
        follows[index].notificationsOn = enabled
        persist()
        if enabled {
            if authorization == .notDetermined { Task { await requestAuthorization() } }
            Task { await ReleaseSchedule.shared.refresh(follows: follows) }
        } else {
            ReleaseSchedule.shared.cancel(animeID: animeID)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(follows) { defaults.set(data, forKey: Self.followKey) }
    }

    // MARK: Permissions

    func loadAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        if Self.isTesting { return false }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await loadAuthorization()
            if granted { scheduleBackgroundRefresh() }
            return granted
        } catch {
            await loadAuthorization()
            return false
        }
    }

    func configure() {
        guard !configured else { return }
        configured = true
        center.delegate = Self.delegate
        AlertCategory.register(center: center)
        loadBackgroundTask()
        Task { await loadAuthorization() }
        // Warm the queued airing banners on every launch, not only after a feed check.
        Task { await ReleaseSchedule.shared.refresh(follows: follows) }
    }

    // MARK: Checking the release feed

    /// Compares the published Hungarian release feed against the followed series.
    @discardableResult
    func check(feed: ReleaseFeed? = nil, notify: Bool = true) async -> [EpisodeAlertHit] {
        let feed = feed ?? ReleaseFeed.shared
        guard !follows.isEmpty, !checking else { return [] }
        checking = true
        defer { checking = false }
        await feed.load(force: true)
        let (hits, updated) = AlertPlanner.plan(follows: follows, releases: feed.items)
        let changed = updated != follows
        if changed { follows = updated.sorted { $0.followedAt > $1.followedAt }; persist() }
        lastCheck = Date()
        defaults.set(lastCheck, forKey: Self.checkKey)
        if !hits.isEmpty {
            recent = Array((hits + recent).uniqued().prefix(20))
            if notify { await deliver(hits) }
        }
        scheduleBackgroundRefresh()
        // Every confirmed check is also a chance to refresh what iOS will fire on its own.
        await ReleaseSchedule.shared.refresh(follows: follows)
        return hits
    }

    private func deliver(_ hits: [EpisodeAlertHit]) async {
        await loadAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }
        for hit in hits.prefix(5) {
            let followed = follows.first { $0.animeID == hit.animeID }
            let identifier = "episode-\(hit.animeID)-\(hit.episode)"
            let alert = RichAlert(
                animeID: hit.animeID,
                title: hit.title,
                episode: hit.episode,
                kicker: "Episode \(hit.episode) · Hungarian subtitle",
                body: "The Hungarian subtitle is live\(Self.timing(hit.at)). Tap to watch.",
                deepLink: hit.deepLink,
                cover: followed?.coverURL,
                category: AlertCategory.episode,
                identifier: identifier,
                badge: nil
            )
            let content = await alert.content()
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            // The pre-scheduled airing banner already did its job for this episode.
            center.removePendingNotificationRequests(withIdentifiers: ["airing-\(hit.animeID)-\(hit.episode)"])
        }
    }

    /// "just now" / "two minutes ago" — the age is what makes the banner feel live.
    private static func timing(_ date: Date) -> String {
        let seconds = Int(abs(Date().timeIntervalSince(date)))
        if seconds < 90 { return " just now" }
        if seconds < 3600 { return " \(seconds / 60) min ago" }
        return ""
    }

    func sendTestNotification() async {
        if authorization == .notDetermined { await requestAuthorization() }
        guard authorization == .authorized || authorization == .provisional else { return }
        let sample = follows.first
        let identifier = "cortex-test-\(Int(Date().timeIntervalSince1970))"
        let alert = RichAlert(
            animeID: sample?.animeID ?? 0,
            title: sample?.title ?? "CortexAnime alerts are on",
            episode: sample?.lastEpisode,
            kicker: "Test banner · this is the new style",
            body: "Cover art, a Play button and a one-hour snooze. A real episode looks exactly like this.",
            deepLink: sample?.deepLink,
            cover: sample?.coverURL,
            category: AlertCategory.episode,
            identifier: identifier,
            badge: nil
        )
        let content = await alert.content()
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        try? await center.add(request)
    }

    // MARK: Background refresh

    private func loadBackgroundTask() {
        guard !Self.isTesting else { return }
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in AlertCenter.shared.run(refresh) }
        }
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh(after seconds: TimeInterval = 45 * 60) {
        guard !Self.isTesting else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func run(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await check()
            // 6.0: the same wake-up also looks at the subtitle feed, so an English or
            // Hungarian drop can arrive without the app ever being opened.
            await checkSubtitles()
            if !Task.isCancelled { task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = { work.cancel() }
    }
}

private extension Array where Element == EpisodeAlertHit {
    func uniqued() -> [EpisodeAlertHit] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Screen

struct NativeAlerts: View {
    @ObservedObject private var alerts = AlertCenter.shared
    @ObservedObject private var schedule = ReleaseSchedule.shared
    @ObservedObject private var catalogModel = ReleaseFeed.shared
    @EnvironmentObject private var catalog: CatalogModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    private var authorizationText: String {
        switch alerts.authorization {
        case .authorized: return "Notifications are on"
        case .provisional: return "Quiet delivery is on"
        case .denied: return "Notifications are blocked in iOS Settings"
        case .ephemeral: return "Temp notifications are on"
        case .notDetermined: return "Notifications are off"
        @unknown default: return "Notifications are off"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                NavigationLink { NativeNotificationSettings() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.and.waves.left.and.right.fill").foregroundStyle(Color.cortexPurple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subtitle notification settings").font(.caption.bold())
                            Text("Hungarian and English switches, test banner, history")
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(12).foregroundStyle(.white)
                    .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.cortexPurple.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("alerts.notificationSettings")
                permissionCard
                if !schedule.queued.isEmpty { scheduleCard }
                if alerts.follows.isEmpty { emptyState } else { followedList }
                if !alerts.recent.isEmpty { recentList }
                explainer
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.cortexBlack)
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cortexBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("alerts.close")
            }
        }
        .task { await alerts.loadAuthorization() }
        .task { await ReleaseSchedule.shared.refresh(follows: alerts.follows) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Episode alerts").font(.system(size: 28, weight: .black)).accessibilityIdentifier("alerts.title")
            Text("Follow a series and CortexAnime tells you when the next Hungarian episode lands. Everything is checked on this device — there is no account and no server-side subscription.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            if let last = alerts.lastCheck {
                Text("Last check: " + last.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    .accessibilityIdentifier("alerts.lastCheck")
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: alerts.authorization == .authorized ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.title2).foregroundStyle(alerts.authorization == .authorized ? Color.cortexPurple : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(authorizationText).font(.subheadline.bold()).accessibilityIdentifier("alerts.authorization")
                    Text("Alerts arrive as local notifications.").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    Task { await alerts.requestAuthorization() }
                } label: {
                    Label("Enable", systemImage: "bell").font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.cortexPurple.opacity(0.2), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("alerts.enable")

                Button {
                    Task { await alerts.sendTestNotification() }
                } label: {
                    Label("Test", systemImage: "paperplane").font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("alerts.test")

                Button {
                    Task { busy = true; await alerts.check(); busy = false }
                } label: {
                    Label(busy ? "Checking…" : "Check now", systemImage: "arrow.clockwise").font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain).disabled(busy)
                .accessibilityIdentifier("alerts.check")
            }
        }
        .padding(14)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cortexPurple.opacity(0.25)))
    }

    /// What iOS will fire on its own. This is the part that works while the app is closed.
    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark.fill").foregroundStyle(Color.cortexPurple)
                Text("Queued while the app is closed").font(.caption.bold())
                Spacer(minLength: 0)
                Text("\(schedule.queued.count)").font(.caption2.bold()).foregroundStyle(.white.opacity(0.45))
            }
            Text("iOS fires these itself, even on days CortexAnime is never opened.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            ForEach(schedule.queued.prefix(5), id: \.self) { slot in
                HStack(spacing: 8) {
                    Text(title(for: slot)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("ep \(slot.episode) · \(slot.airingAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(14)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cortexPurple.opacity(0.18)))
        .accessibilityIdentifier("alerts.schedule")
    }

    private func title(for slot: ReleaseSchedule.Slot) -> String {
        alerts.follows.first { $0.animeID == slot.animeID }?.title ?? "Episode \(slot.episode)"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Nothing followed yet")
            Text("Open a series and tap the bell, or start with one of these.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(suggestions) { anime in
                            VStack(alignment: .leading, spacing: 8) {
                                AnimeArtwork(url: anime.cover).frame(width: 104, height: 152).clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(anime.title).font(.system(size: 11, weight: .bold)).lineLimit(2).frame(width: 104, alignment: .leading)
                                Button {
                                    alerts.follow(anime, releases: catalogModel.items)
                                } label: {
                                    Label("Follow", systemImage: "bell.badge").font(.system(size: 10, weight: .black))
                                        .frame(width: 104).frame(minHeight: 34)
                                        .background(Color.cortexPurple.opacity(0.18), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .foregroundStyle(.white)
                            .cortexShelfTilt(strength: 12)
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private var suggestions: [Anime] {
        Array(catalog.titles.filter { !alerts.isFollowing($0.id) && $0.hasHungarian }.prefix(8))
    }

    private var followedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Following")
            ForEach(alerts.follows) { follow in
                HStack(spacing: 12) {
                    AnimeArtwork(url: follow.coverURL).frame(width: 46, height: 66).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(follow.title).font(.subheadline.bold()).lineLimit(2)
                        Text("Last seen episode \(follow.lastEpisode)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Toggle("", isOn: Binding(get: { follow.notificationsOn }, set: { alerts.setNotifications($0, for: follow.animeID) }))
                        .labelsHidden().tint(Color.cortexPurple)
                        .accessibilityLabel("Notifications for \(follow.title)")
                    Button(role: .destructive) {
                        alerts.unfollow(follow.animeID)
                    } label: {
                        Image(systemName: "trash").font(.footnote).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("Unfollow \(follow.title)")
                }
                .padding(11)
                .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 15))
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Already announced")
            ForEach(alerts.recent) { hit in
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill").foregroundStyle(Color.cortexPurple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title).font(.caption.bold()).lineLimit(1)
                        Text("Episode \(hit.episode) · \(hit.at.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "How it works")
            Text("• The app compares your follows with the published Hungarian release feed.")
            Text("• Checks run when the app opens and, in the background, at most once every 45 minutes when iOS allows it.")
            Text("• Only the newest missing episode is announced, so a long break cannot spam you.")
            Text("• Nothing leaves the device except the normal catalog request.")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.55))
    }
}
