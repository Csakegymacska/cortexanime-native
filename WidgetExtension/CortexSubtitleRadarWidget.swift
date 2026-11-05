import SwiftUI
import WidgetKit

// 6.0 widget: "Subtitle radar". Where "New in Hungarian" only ever knew about one language,
// this one reads the combined feed and badges every row with the language it landed in.
// Same rules as the others: public endpoints only, no App Group, caches the last good list.

struct SubtitleRadarEntry: TimelineEntry {
    let date: Date
    let items: [CortexSubtitleItem]
    let artwork: [Int: Data]
    let accent: [Int: Int]
    let saved: Bool
    let todayCount: Int
    static var empty: Self { Self(date: Date(), items: [], artwork: [:], accent: [:], saved: false, todayCount: 0) }
}

struct SubtitleRadarProvider: TimelineProvider {
    private let cacheName = "subtitles-v3"

    func placeholder(in context: Context) -> SubtitleRadarEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping (SubtitleRadarEntry) -> Void) {
        if context.isPreview { completion(.empty); return }
        Task { completion(await entry(family: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SubtitleRadarEntry>) -> Void) {
        Task {
            let item = await entry(family: context.family)
            completion(Timeline(entries: [item], policy: .after(Date().addingTimeInterval(20 * 60))))
        }
    }

    private func entry(family: WidgetFamily) async -> SubtitleRadarEntry {
        let client = CortexWidgetClient()
        var items: [CortexSubtitleItem]
        var saved = false
        do {
            items = try await client.subtitles()
            CortexWidgetCache.save(items, name: cacheName)
        } catch {
            guard let cached = CortexWidgetCache.load([CortexSubtitleItem].self, name: cacheName, maxAge: 24 * 3600),
                  !cached.isEmpty else { return .empty }
            items = cached
            saved = true
        }
        let limit = family == .systemSmall ? 1 : family == .systemMedium ? 3 : family == .systemLarge ? 5 : 9
        let shown = Array(items.prefix(limit))
        let pixel = family == .systemSmall ? 380 : family == .systemMedium ? 240 : 150
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
        let today = items.filter { $0.at >= startOfDay }.count
        return SubtitleRadarEntry(date: Date(), items: shown, artwork: artwork, accent: accent,
                                  saved: saved, todayCount: today)
    }
}

// MARK: - Views

struct SubtitleRadarWidgetView: View {
    let entry: SubtitleRadarEntry
    @Environment(\.widgetFamily) private var family

    private var first: CortexSubtitleItem? { entry.items.first }

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

    private var small: some View {
        Group {
            if let item = first {
                CxHeroBanner(title: item.title, episode: item.episode,
                             caption: item.languageName + " · " + item.ageText,
                             artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                             badge: item.badge)
                    .widgetURL(item.deepLink)
            } else {
                CxEmptyState(headline: "Subtitle radar", detail: "No subtitle published yet.")
                    .widgetURL(CortexNativeAddress.home)
            }
        }
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.purple) }
    }
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            CxBrandMark(trailing: entry.saved ? "SAVED" : "HU · EN")
            if entry.items.isEmpty {
                CxEmptyState(headline: "Subtitle radar", detail: "No subtitle published yet.")
            } else {
                HStack(spacing: 10) {
                    if let item = first, let link = item.deepLink {
                        Link(destination: link) {
                            CxHeroBanner(title: item.title, episode: item.episode,
                                         caption: item.languageName, artwork: entry.artwork[item.id],
                                         rgb: entry.accent[item.id], badge: item.badge, showsAction: false)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(entry.items.dropFirst().prefix(2)) { item in
                            if let link = item.deepLink {
                                Link(destination: link) {
                                    CxMiniRow(title: item.title, episode: item.episode, caption: item.ageText,
                                              artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                              badge: item.badge)
                                }.buttonStyle(.plain)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.purple) }
        .widgetURL(CortexNativeAddress.home)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                CxBrandMark(trailing: nil)
                Spacer(minLength: 0)
                if entry.todayCount > 0 {
                    CxInfoChip(text: "\(entry.todayCount) TODAY", color: CxWidget.mint)
                }
            }
            if entry.items.isEmpty {
                CxEmptyState(headline: "Subtitle radar", detail: "No subtitle published yet.")
            } else {
                if let item = first, let link = item.deepLink {
                    Link(destination: link) {
                        CxHeroBanner(title: item.title, episode: item.episode,
                                     caption: item.languageName + " · " + item.ageText,
                                     artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                     badge: item.badge)
                            .frame(height: 114)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain)
                }
                VStack(spacing: 7) {
                    ForEach(entry.items.dropFirst().prefix(3)) { item in
                        if let link = item.deepLink {
                            Link(destination: link) {
                                CxMiniRow(title: item.title, episode: item.episode, caption: item.ageText,
                                          artwork: entry.artwork[item.id], rgb: entry.accent[item.id],
                                          badge: item.badge)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
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
                Image(systemName: "captions.bubble.fill").font(.system(size: 13, weight: .semibold))
                Text("\(entry.todayCount)").font(.system(size: 17, weight: .heavy)).monospacedDigit()
            }
        }
        .subtitleWidgetLabel( entry.todayCount == 0 ? "No subtitle today"
                          : "\(entry.todayCount) subtitles today, newest \(first?.title ?? "")")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let item = first {
                Text("CORTEX · \(item.badge) SUB").font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                Text(item.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text("EP \(item.episode) · \(item.ageText)").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("CORTEX ANIME").font(.system(size: 11, weight: .heavy))
                Text("No subtitle yet").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .subtitleWidgetLabel( first.map { "\($0.badge) subtitle, \($0.title), episode \($0.episode)" } ?? "No subtitle yet")
    }

    private var inline: some View {
        Group {
            if let item = first {
                Text("\(item.badge) EP \(item.episode) \(item.title)")
            } else {
                Text("CortexAnime subtitle radar")
            }
        }
    }
}

// MARK: - Widget

struct CortexSubtitleRadarWidget: Widget {
    let kind = "CortexSubtitleRadar"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SubtitleRadarProvider()) { entry in
            SubtitleRadarWidgetView(entry: entry).environment(\.locale, Locale(identifier: "en"))
        }
        .configurationDisplayName("Subtitle radar")
        .description("The newest Hungarian and English subtitles in one widget, with the language on every row and a lock screen version.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private extension View {
    /// The same idea as the episode widget's helper, kept local so the two extension files
    /// stay independent. Lock screen widgets ignore widgetURL, so they need a spoken label.
    func subtitleWidgetLabel(_ label: String) -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}
