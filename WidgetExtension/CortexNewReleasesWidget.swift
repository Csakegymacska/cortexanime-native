import SwiftUI
import WidgetKit

// "New in Hungarian" — the 4.0 widget that shows what CortexAnime actually published,
// straight from /api/app/epfeed, instead of generic airing data.

struct ReleasesEntry: TimelineEntry {
    let date: Date
    let items: [CortexReleaseItem]
    let artwork: [Int: Data]
    let accent: [Int: Int]
    let saved: Bool
    let todayCount: Int
    static var empty: Self { Self(date: Date(), items: [], artwork: [:], accent: [:], saved: false, todayCount: 0) }
}

struct ReleasesProvider: TimelineProvider {
    private let cacheName = "releases-v2"

    func placeholder(in context: Context) -> ReleasesEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping (ReleasesEntry) -> Void) {
        if context.isPreview { completion(.empty); return }
        Task { completion(await entry(family: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReleasesEntry>) -> Void) {
        Task {
            let item = await entry(family: context.family)
            // Releases land in bursts; a 20 minute refresh keeps the widget close to live.
            completion(Timeline(entries: [item], policy: .after(Date().addingTimeInterval(20 * 60))))
        }
    }

    private func entry(family: WidgetFamily) async -> ReleasesEntry {
        let client = CortexWidgetClient()
        var items: [CortexReleaseItem]
        var saved = false
        do {
            items = try await client.releases()
            CortexWidgetCache.save(items, name: cacheName)
        } catch {
            guard let cached = CortexWidgetCache.load([CortexReleaseItem].self, name: cacheName, maxAge: 24 * 3600),
                  !cached.isEmpty else { return .empty }
            items = cached; saved = true
        }
        let limit = family == .systemSmall ? 1 : family == .systemMedium ? 2 : family == .systemLarge ? 4 : 7
        let shown = Array(items.prefix(limit))
        let pixel = family == .systemSmall ? 460 : family == .systemMedium ? 360 : 240
        var artwork: [Int: Data] = [:]
        await withTaskGroup(of: (Int, Data?).self) { group in
            for item in shown {
                group.addTask { (item.id, await client.artwork(item.cover, maxPixel: pixel)) }
            }
            for await (id, bytes) in group { if let bytes { artwork[id] = bytes } }
        }
        var accent: [Int: Int] = [:]
        for (id, bytes) in artwork { accent[id] = CxWidget.dominantRGB(bytes) }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let today = items.filter { $0.airedAt >= startOfDay }.count
        return ReleasesEntry(date: Date(), items: shown, artwork: artwork, accent: accent,
                             saved: saved, todayCount: today)
    }
}

// MARK: - Views

struct ReleasesWidgetView: View {
    let entry: ReleasesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    private var first: CortexReleaseItem? { entry.items.first }

    private var small: some View {
        Group {
            if let item = first {
                CxHeroBanner(title: item.cleanTitle, episode: item.episode, caption: caption(item),
                             artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                             badge: item.isNewSeries ? "NEW" : "HU")
                    .widgetURL(item.deepLink)
            } else {
                CxEmptyState(headline: "New in Hungarian", detail: "Waiting for the next release.")
                    .widgetURL(CortexNativeAddress.home)
            }
        }
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.purple) }
    }
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            CxBrandMark(trailing: "HU · \(entry.todayCount) TODAY")
            if entry.items.isEmpty {
                CxEmptyState(headline: "New in Hungarian", detail: "Waiting for the next release.")
            } else {
                HStack(spacing: 10) {
                    if let item = first {
                        if let link = item.deepLink {
                            Link(destination: link) {
                                CxHeroBanner(title: item.cleanTitle, episode: item.episode, caption: caption(item),
                                             artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                             badge: item.isNewSeries ? "NEW" : "HU", showsAction: false)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(entry.items.dropFirst().prefix(2)) { item in
                            if let link = item.deepLink {
                                Link(destination: link) {
                                    CxMiniRow(title: item.cleanTitle, episode: item.episode, caption: caption(item),
                                              artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                              badge: item.isNewSeries ? "NEW" : nil)
                                }.buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            Circle().fill(CxWidget.mint).frame(width: 5, height: 5)
                            Text("\(entry.items.count) fresh").font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.purple) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            CxBrandMark(trailing: "HU · \(entry.todayCount) TODAY")
            if entry.items.isEmpty {
                CxEmptyState(headline: "New in Hungarian", detail: "Waiting for the next release.")
            } else {
                if let item = first, let link = item.deepLink {
                    Link(destination: link) {
                        CxHeroBanner(title: item.cleanTitle, episode: item.episode, caption: caption(item),
                                     artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                     badge: item.isNewSeries ? "NEW" : "HU")
                            .frame(height: 118)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain)
                }
                VStack(spacing: 7) {
                    ForEach(entry.items.dropFirst().prefix(3)) { item in
                        if let link = item.deepLink {
                            Link(destination: link) {
                                CxMiniRow(title: item.cleanTitle, episode: item.episode, caption: caption(item),
                                          artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                          badge: item.isNewSeries ? "NEW" : nil)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Text(entry.saved ? "Saved copy ·" : "Updated")
                Text(entry.date, style: .relative)
                Spacer(minLength: 0)
                Text("cortanime.eu")
            }
            .font(.system(size: 8.5)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.purple) }
        .widgetURL(CortexNativeAddress.home)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("HU").font(.system(size: 9, weight: .heavy)).foregroundStyle(CxWidget.purple)
                Text("\(entry.todayCount)").font(.system(size: 17, weight: .heavy)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.todayCount == 0 ? "No new Hungarian episodes today"
                            : "\(entry.todayCount) new Hungarian episodes today")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let item = first {
                Text("CORTEX · NEW IN HU").font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                Text(item.cleanTitle).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text("EP \(item.episode) · \(caption(item))").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("CORTEX ANIME").font(.system(size: 11, weight: .heavy))
                Text("No new Hungarian episodes yet").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(first?.deepLink)
    }

    private var inline: some View {
        Group {
            if let item = first {
                Text("HU: EP \(item.episode) \(item.cleanTitle)")
            } else {
                Text("CortexAnime: new Hungarian episodes")
            }
        }
    }

    private func caption(_ item: CortexReleaseItem) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(item.airedAt)))
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

// MARK: - Widget + bundle

struct CortexNewReleasesWidget: Widget {
    let kind = "CortexNewReleases"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReleasesProvider()) { entry in
            ReleasesWidgetView(entry: entry).environment(\.locale, Locale(identifier: "en"))
        }
        .configurationDisplayName("New in Hungarian")
        .description("The newest Hungarian-subtitled episodes that CortexAnime published, with cover art and a lock screen version.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main struct CortexEpisodesWidgetBundle: WidgetBundle {
    var body: some Widget {
        CortexSubtitleRadarWidget()
        CortexNewReleasesWidget()
        CortexLatestEpisodesWidget()
        CortexTrendingWidget()
        DownloadLiveActivity()
    }
}
