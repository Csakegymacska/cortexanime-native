import SwiftUI
import WidgetKit

// 5.0 widget #3: "Trending now". Built straight from the public /api/home-live ranking, so
// it needs no account, no App Group and no app launch — it stays correct after any signing.

struct CortexTrendItem: Codable, Hashable, Identifiable, Sendable {
    let animeID: Int
    let title: String
    let cover: String?
    let score: Double?
    let format: String?
    let aired: String?

    var id: Int { animeID }
    var coverURL: URL? {
        guard let cover, let url = URL(string: cover), url.scheme == "https" else { return nil }
        return url
    }
    var deepLink: URL? {
        guard animeID > 0 else { return nil }
        return URL(string: "\(CortexNativeAddress.scheme)://anime/\(animeID)")
    }
    var prettyFormat: String? {
        guard let format else { return nil }
        switch format {
        case "TV": return "TV"
        case "ONA": return "ONA"
        case "OVA": return "OVA"
        case "MOVIE": return "Movie"
        case "TV_SHORT": return "Short"
        default: return format
        }
    }
}

extension CortexWidgetClient {
    /// Top of the CortexAnime trending ranking, Hungarian catalogue ids preserved.
    func trending(now: Date = Date()) async throws -> [CortexTrendItem] {
        guard let url = URL(string: "https://cortanime.eu/api/home-live") else { throw CortexWidgetFetchError.unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("CortexAnimeWidget/5.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count <= 900_000,
              let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let rows = root["trending"] as? [[String: Any]] else { throw CortexWidgetFetchError.unavailable }
        var seen = Set<Int>()
        let items: [CortexTrendItem] = rows.compactMap { row in
            guard let id = (row["anilistId"] as? NSNumber)?.intValue, id > 0, seen.insert(id).inserted,
                  let rawTitle = [row["titleEnglish"] as? String, row["title"] as? String, row["titleRomaji"] as? String]
                    .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .first(where: { !$0.isEmpty }) else { return nil }
            let cover = (row["cover"] as? String).flatMap { raw -> String? in
                guard let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
                return raw
            }
            let score = (row["score"] as? NSNumber)?.doubleValue
            return CortexTrendItem(animeID: id, title: String(rawTitle.prefix(140)), cover: cover,
                                   score: score.flatMap { $0 > 0 ? $0 : nil },
                                   format: row["format"] as? String,
                                   aired: row["nextAiringAt"] as? String)
        }
        guard !items.isEmpty else { throw CortexWidgetFetchError.unavailable }
        return Array(items.prefix(18))
    }
}

struct TrendingEntry: TimelineEntry {
    let date: Date
    let items: [CortexTrendItem]
    let artwork: [Int: Data]
    static var empty: Self { Self(date: Date(), items: [], artwork: [:]) }
}

struct TrendingProvider: TimelineProvider {
    private let cacheName = "trending-v1"

    func placeholder(in context: Context) -> TrendingEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping (TrendingEntry) -> Void) {
        if context.isPreview { completion(.empty); return }
        Task { completion(await entry(family: context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendingEntry>) -> Void) {
        Task {
            let item = await entry(family: context.family)
            completion(Timeline(entries: [item], policy: .after(Date().addingTimeInterval(45 * 60))))
        }
    }

    private func entry(family: WidgetFamily) async -> TrendingEntry {
        let client = CortexWidgetClient()
        var items: [CortexTrendItem]
        do {
            items = try await client.trending()
            CortexWidgetCache.save(items, name: cacheName)
        } catch {
            items = CortexWidgetCache.load([CortexTrendItem].self, name: cacheName, maxAge: 12 * 3600) ?? []
        }
        guard !items.isEmpty else { return .empty }
        let count = family == .systemSmall || family == .accessoryCircular ? 1 : 3
        let maxPixel = family == .systemLarge || family == .systemExtraLarge ? 700 : 420
        var artwork: [Int: Data] = [:]
        for item in items.prefix(count) {
            if let data = await client.artwork(item.cover, maxPixel: maxPixel) { artwork[item.animeID] = data }
        }
        return TrendingEntry(date: Date(), items: items, artwork: artwork)
    }
}

struct TrendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrendingEntry

    private var first: CortexTrendItem? { entry.items.first }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemSmall: small
            case .systemLarge, .systemExtraLarge: large
            default: medium
            }
        }
        .containerBackground(for: .widget) { CxBackground(accent: CxWidget.mint) }
        .widgetURL(first?.deepLink ?? CortexNativeAddress.home)
    }

    // MARK: Home screen

    private var small: some View {
        Group {
            if let first {
                ZStack(alignment: .topLeading) {
                    CxArtwork(data: entry.artwork[first.animeID], rgb: 0x2fb3a0, cornerRadius: 0, symbol: "flame.fill")
                    LinearGradient(colors: [.black.opacity(0.15), .clear, .black.opacity(0.35), .black.opacity(0.92)],
                                   startPoint: .top, endPoint: .bottom)
                    LinearGradient(colors: [CxWidget.mint.opacity(0.35), .clear],
                                   startPoint: .topLeading, endPoint: .center)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            CxBrandMark()
                            Spacer(minLength: 0)
                            Text("TOP 1").font(.system(size: 8.5, weight: .black)).tracking(0.5)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2.5)
                                .background(CxWidget.mint, in: Capsule())
                        }
                        Spacer(minLength: 0)
                        Text(first.title)
                            .font(.system(size: 14, weight: .heavy))
                            .lineLimit(2).minimumScaleFactor(0.8)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.65), radius: 4, y: 1)
                        HStack(spacing: 5) {
                            if let score = first.score {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill").font(.system(size: 7))
                                    Text(String(format: "%.1f", score)).font(.system(size: 9, weight: .heavy)).monospacedDigit()
                                }
                                .foregroundStyle(CxWidget.mint)
                            }
                            if let format = first.prettyFormat {
                                Text(format).font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                    .padding(11)
                }
            } else {
                CxEmptyState(headline: "Trending", detail: "The ranking is loading.")
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            CxBrandMark(trailing: "TRENDING NOW")
            HStack(spacing: 8) {
                ForEach(Array(entry.items.prefix(3).enumerated()), id: \.element.animeID) { index, item in
                    VStack(alignment: .leading, spacing: 4) {
                        ZStack(alignment: .topLeading) {
                            CxArtwork(data: entry.artwork[item.animeID], rgb: rankTint(index), cornerRadius: 12, symbol: "flame.fill")
                                .aspectRatio(0.7, contentMode: .fit)
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.black.opacity(0.75))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(CxWidget.mint))
                                .padding(4)
                        }
                        .frame(maxWidth: .infinity)
                        Text(item.title).font(.system(size: 9.5, weight: .semibold)).lineLimit(2)
                        if let score = item.score {
                            Text(String(format: "%.1f", score)).font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(CxWidget.mint).monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .widgetURL(item.deepLink)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                CxBrandMark()
                Spacer(minLength: 0)
                CxInfoChip(text: "Cortex ranking", color: CxWidget.mint)
            }
            if let first {
                ZStack(alignment: .bottomLeading) {
                    CxArtwork(data: entry.artwork[first.animeID], rgb: 0x2fb3a0, cornerRadius: 16, symbol: "flame.fill")
                        .frame(height: 132).clipped()
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                                startPoint: .center, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(first.title).font(.system(size: 14, weight: .heavy)).lineLimit(2)
                        HStack(spacing: 6) {
                            CxInfoChip(text: "No. 1", color: CxWidget.mint)
                            if let format = first.prettyFormat { Text(format).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                            if let score = first.score { Text(String(format: "%.1f", score)).font(.system(size: 9, weight: .heavy)).foregroundStyle(CxWidget.mint) }
                        }
                    }
                    .padding(10)
                }
                .widgetURL(first.deepLink)
            }
            ForEach(Array(entry.items.dropFirst().prefix(family == .systemExtraLarge ? 5 : 3).enumerated()), id: \.element.animeID) { index, item in
                HStack(spacing: 8) {
                    Text("\(index + 2)").font(.system(size: 11, weight: .black)).foregroundStyle(CxWidget.mint).frame(width: 14)
                    CxArtwork(data: entry.artwork[item.animeID], rgb: rankTint(index + 1), cornerRadius: 7, symbol: "flame.fill")
                        .frame(width: 26, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            if let format = item.prettyFormat { Text(format).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                            if let score = item.score { Text(String(format: "%.1f", score)).font(.system(size: 8, weight: .heavy)).foregroundStyle(CxWidget.mint) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .widgetURL(item.deepLink)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Lock screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(CxWidget.mint)
                Text(first?.score.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 15, weight: .heavy)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(first.map { "Trending: \($0.title)" } ?? "CortexAnime trending")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let first {
                Text("CORTEX · TRENDING").font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                Text(first.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                Text(first.score.map { String(format: "%.1f", $0) } ?? (first.prettyFormat ?? "Top 1"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("CORTEX ANIME").font(.system(size: 11, weight: .heavy))
                Text("Trending ranking unavailable").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(first?.deepLink)
    }

    private var inline: some View {
        Group {
            if let first { Text("Trending: \(first.title)") } else { Text("CortexAnime trending") }
        }
    }

    private func rankTint(_ index: Int) -> Int {
        let palette = [0x2fb3a0, 0x3f6ee0, 0x8f52f0, 0xd05a8a]
        return palette[min(index, palette.count - 1)]
    }
}

struct CortexTrendingWidget: Widget {
    let kind = "CortexTrending"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrendingProvider()) { entry in
            TrendingWidgetView(entry: entry).environment(\.locale, Locale(identifier: "en"))
        }
        .configurationDisplayName("Trending now")
        .description("What the CortexAnime catalogue is watching right now, ranked, with a lock screen family.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
