import SwiftUI
import WidgetKit

// "Latest airings" widget, rebuilt for 4.0: one hero for small, two posters for medium,
// a dense list for large/extra large and three lock screen styles.

struct AiringsEntry: TimelineEntry {
    let date: Date
    let items: [CortexAiringItem]
    let artwork: [Int: Data]
    let accent: [Int: Int]
    let saved: Bool
    static var empty: Self { Self(date: Date(), items: [], artwork: [:], accent: [:], saved: false) }
}

struct AiringsProvider: TimelineProvider {
    private let cacheName = "airings-v2"

    func placeholder(in context: Context) -> AiringsEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping (AiringsEntry) -> Void) {
        if context.isPreview { completion(.empty); return }
        Task { completion(await entry(family: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AiringsEntry>) -> Void) {
        Task {
            let item = await entry(family: context.family)
            completion(Timeline(entries: [item], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    private func entry(family: WidgetFamily) async -> AiringsEntry {
        let client = CortexWidgetClient()
        var items: [CortexAiringItem]
        var saved = false
        do {
            items = try await client.airings()
            CortexWidgetCache.save(items, name: cacheName)
        } catch {
            guard let cached = CortexWidgetCache.load([CortexAiringItem].self, name: cacheName, maxAge: 6 * 3600),
                  !cached.isEmpty else { return .empty }
            items = cached; saved = true
        }
        let limit = family == .systemSmall ? 1 : family == .systemMedium ? 2 : family == .systemLarge ? 5 : 9
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
        return AiringsEntry(date: Date(), items: shown, artwork: artwork, accent: accent, saved: saved)
    }
}

// MARK: - Views

struct AiringsWidgetView: View {
    let entry: AiringsEntry
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

    private var first: CortexAiringItem? { entry.items.first }

    private var small: some View {
        Group {
            if let item = first {
                CxHeroBanner(title: item.title, episode: item.episode, caption: item.relativeAge,
                             artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                             badge: item.relativeAge.uppercased())
                    .widgetURL(item.deepLink)
            } else {
                CxEmptyState(headline: "Latest airings", detail: "Waiting for current airing data.")
                    .widgetURL(CortexNativeAddress.home)
            }
        }
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.indigo) }
    }
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            CxBrandMark(trailing: entry.saved ? "SAVED" : "AIRING")
            if entry.items.isEmpty {
                CxEmptyState(headline: "Latest airings", detail: "Waiting for current airing data.")
            } else {
                HStack(spacing: 10) {
                    if let item = first, let link = item.deepLink {
                        Link(destination: link) {
                            CxHeroBanner(title: item.title, episode: item.episode, caption: item.relativeAge,
                                         artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                         badge: "ON AIR", showsAction: false)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(entry.items.dropFirst().prefix(2)) { item in
                            if let link = item.deepLink {
                                Link(destination: link) {
                                    CxMiniRow(title: item.title, episode: item.episode, caption: item.relativeAge,
                                              artwork: entry.artwork[item.id], rgb: entry.accent[item.id])
                                }.buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.indigo) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            CxBrandMark(trailing: entry.saved ? "SAVED" : "LATEST")
            if entry.items.isEmpty {
                CxEmptyState(headline: "Latest airings", detail: "Waiting for current airing data.")
            } else {
                if let item = first, let link = item.deepLink {
                    Link(destination: link) {
                        CxHeroBanner(title: item.title, episode: item.episode, caption: item.relativeAge,
                                     artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                     badge: item.relativeAge.uppercased())
                            .frame(height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain)
                }
                VStack(spacing: 7) {
                    ForEach(entry.items.dropFirst().prefix(3)) { item in
                        if let link = item.deepLink {
                            Link(destination: link) {
                                CxMiniRow(title: item.title, episode: item.episode, caption: item.relativeAge,
                                          artwork: entry.artwork[item.id], rgb: entry.accent[item.id])
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.indigo) }
        .widgetURL(CortexNativeAddress.home)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "tv.fill").font(.system(size: 13, weight: .semibold))
                Text("\(entry.items.count)").font(.system(size: 17, weight: .heavy)).monospacedDigit()
            }
        }
        .widgetAccessible(label: entry.items.isEmpty ? "No recent airings"
                          : "\(entry.items.count) recent airings, newest \(entry.items[0].title)")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let item = first {
                Text("CORTEX · LATEST").font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                Text(item.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text("EP \(item.episode) · \(item.relativeAge)").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("CORTEX ANIME").font(.system(size: 11, weight: .heavy))
                Text("No airing data yet").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(first?.deepLink)
    }

    private var inline: some View {
        Group {
            if let item = first {
                Text("EP \(item.episode) \(item.title): \(item.relativeAge)")
            } else {
                Text("CortexAnime: latest airings")
            }
        }
    }
}

// MARK: - Widget

struct CortexLatestEpisodesWidget: Widget {
    let kind = "CortexLatestEpisodes"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AiringsProvider()) { entry in
            AiringsWidgetView(entry: entry).environment(\.locale, Locale(identifier: "en"))
        }
        .configurationDisplayName("Latest airings")
        .description("Recent anime airings with cover art, plus a lock screen version. Airing data does not guarantee a playable stream or Hungarian subtitles.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private extension View {
    /// Lock screen widgets need an explicit accessibility label; widgetURL is ignored there.
    func widgetAccessible(label: String) -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}
