import SwiftUI

// MARK: - Experience layer (3.0)
// Small, self-contained pieces that the profile, the player and the settings screen use.

/// Level-up celebration. Shown over the profile and the player, dismissed by the viewer.
struct LevelUpOverlay: View {
    let level: Int
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color.cortexPurple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 92, height: 92)
                        .scaleEffect(shown ? 1 : 0.6)
                    Text("\(level)").font(.system(size: 40, weight: .black)).foregroundStyle(.white)
                }
                Text("Level \(level)").font(.system(size: 26, weight: .black))
                Text("You reached a new level. Your credit reward is already in your balance.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                PrimaryButton(title: "Nice", icon: "sparkles") { close() }.frame(maxWidth: 220)
            }
            .padding(26)
            .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.cortexPurple.opacity(0.4)))
            .padding(30)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
        }
        .accessibilityIdentifier("levelup.overlay")
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)) { shown = true }
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { shown = false }
        onClose()
    }
}

/// Weekly recap: how much was watched in the last seven days, per day.
struct WeeklyRecapCard: View {
    @ObservedObject var store: CreditStore

    @MainActor private var buckets: [WatchDay] { store.weeklyBuckets() }
    @MainActor private var peak: Double { max(60, buckets.map(\.seconds).max() ?? 0) }
    @MainActor private var weekSeconds: Double { store.seconds(inLast: 7) }
    @MainActor private var weekEpisodes: Int { store.episodes(inLast: 7) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: "This week")
                Spacer()
                Pill(text: "\(Int(weekSeconds / 60)) min")
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(buckets) { bucket in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(bucket.seconds > 0 ? LinearGradient(colors: [Color.cortexPurple, .cyan], startPoint: .bottom, endPoint: .top) : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)], startPoint: .bottom, endPoint: .top))
                            .frame(height: max(6, CGFloat(bucket.seconds / peak) * 76))
                        Text(bucket.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            Text(weekEpisodes == 1 ? "1 episode finished" : "\(weekEpisodes) episodes finished").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("profile.weeklyRecap")
    }
}

/// Badge row with a real progress bar instead of a plain locked state.
struct BadgeProgressRow: View {
    let badge: ProfileBadge
    @ObservedObject var store: CreditStore

    @MainActor private var earned: Bool { store.badgesEarned.contains(badge.id) }
    @MainActor private var fraction: Double { badge.fraction(store: store) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: badge.icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(earned ? rarityColor : .white.opacity(0.35))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(badge.name).font(.system(size: 13, weight: .bold))
                    if earned { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(Color.cortexPurple) }
                }
                Text(badge.detail).font(.caption2).foregroundStyle(.secondary)
                if !earned {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08)).frame(height: 5)
                            Capsule().fill(Color.cortexPurple).frame(width: max(5, geo.size.width * fraction), height: 5)
                        }
                    }.frame(height: 5)
                }
            }
            Spacer(minLength: 0)
            if !earned {
                Text("\(Int(fraction * 100))%").font(.caption2.bold()).foregroundStyle(.white.opacity(0.45)).monospacedDigit()
            }
        }
        .padding(11)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("badge.row.\(badge.id)")
    }

    private var rarityColor: Color {
        switch badge.rarity {
        case 3: return .yellow
        case 2: return Color.cortexPurple
        case 1: return .cyan
        default: return .white.opacity(0.75)
        }
    }
}

/// Recent search terms, stored per device. Used by the search screen.
@MainActor final class RecentSearches: ObservableObject {
    static let shared = RecentSearches()
    @Published private(set) var terms: [String]
    private let key = "search.recents"
    private let defaults = UserDefaults.standard
    private let limit = 8

    init() {
        terms = (UserDefaults.standard.array(forKey: "search.recents") as? [String]) ?? []
    }

    func remember(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        var next = terms.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        next.insert(term, at: 0)
        terms = Array(next.prefix(limit))
        defaults.set(terms, forKey: key)
    }

    func forget(_ term: String) {
        terms.removeAll { $0 == term }
        defaults.set(terms, forKey: key)
    }

    func clear() {
        terms = []
        defaults.removeObject(forKey: key)
    }
}

/// Horizontal chip row for recent searches.
struct RecentSearchChips: View {
    @ObservedObject var store: RecentSearches
    var onPick: (String) -> Void

    var body: some View {
        if !store.terms.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent searches").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("Clear") { store.clear() }.font(.system(size: 12, weight: .semibold)).frame(minHeight: 32)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.terms, id: \.self) { term in
                            Button { onPick(term) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                                    Text(term).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(.white.opacity(0.05), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search.recent.\(term)")
                        }
                    }
                }
            }
        }
    }
}

/// Local storage report for the settings screen: captions and downloaded media.
enum StorageReport {
    static func captionCount() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: SubtitleCache.folder, includingPropertiesForKeys: nil)) ?? []
        return files.count
    }

    static func captionBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: SubtitleCache.folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in sum + OfflineStorage.bytes(at: url) }
    }

    static func mediaBytes() -> Int64 {
        OfflineStorage.bytes(at: OfflineFiles.mediaFolder)
    }

    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @discardableResult
    static func clearCaptions() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: SubtitleCache.folder, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for url in files where (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        return removed
    }
}

/// Settings section that shows what the app keeps on this device.
struct StorageSection: View {
    @State private var captions = 0
    @State private var captionBytes: Int64 = 0
    @State private var mediaBytes: Int64 = 0
    @State private var cleared: String?

    var body: some View {
        Section("Storage on this device") {
            LabeledContent("Cached subtitles", value: "\(captions) files · \(StorageReport.formatted(captionBytes))")
            LabeledContent("Downloaded episodes", value: StorageReport.formatted(mediaBytes))
            Button("Clear cached subtitles", role: .destructive) {
                let removed = StorageReport.clearCaptions()
                cleared = "Removed \(removed) cached subtitle files."
                refresh()
            }
            if let cleared { Text(cleared).font(.caption).foregroundStyle(.secondary) }
            Text("Downloaded episodes are managed on the Downloads screen so you can see what is removed.").font(.caption).foregroundStyle(.secondary)
        }
        .task { refresh() }
    }

    private func refresh() {
        captions = StorageReport.captionCount()
        captionBytes = StorageReport.captionBytes()
        mediaBytes = StorageReport.mediaBytes()
    }
}

/// Most-watched series on this device, derived from the credit store's watch log.
/// The library keeps only the latest position per series, so it cannot rank by time.
private struct TopSeriesRow: Identifiable {
    let anime: Anime
    let minutes: Int
    var id: Int { anime.id }
}

struct TopSeriesCard: View {
    @ObservedObject var library: AnimeLibrary
    @ObservedObject var store: CreditStore

    @MainActor private var rows: [TopSeriesRow] {
        var totals: [Int: Double] = [:]
        for tick in store.watchLog { totals[tick.animeID, default: 0] += max(0, tick.seconds) }
        var result: [TopSeriesRow] = []
        for pair in totals.sorted(by: { $0.value > $1.value }) {
            guard let anime = library.history.first(where: { $0.anime.id == pair.key })?.anime else { continue }
            result.append(TopSeriesRow(anime: anime, minutes: Int(pair.value / 60)))
            if result.count == 3 { break }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Most watched")
            if rows.isEmpty {
                Text("Watch a few episodes and your top series appear here.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink { NativeDetail(seed: row.anime) } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(index == 0 ? Color.yellow : Color.white.opacity(0.4)).frame(width: 22)
                            AnimeArtwork(url: row.anime.cover).frame(width: 38, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.anime.title).font(.caption.bold()).lineLimit(1)
                                Text("\(row.minutes) min watched").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(10)
                        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Shareable one-line summary of the local statistics.
struct ShareStatsButton: View {
    @ObservedObject var store: CreditStore

    @MainActor private var summary: String {
        let hours = String(format: "%.1f", store.totalSeconds / 3600)
        return "CortexAnime · Level \(store.level) · \(store.episodesCompleted) episodes watched · \(hours) hours · \(store.seriesCompleted) series finished"
    }

    var body: some View {
        ShareLink(item: summary) {
            Label("Share my stats", systemImage: "square.and.arrow.up")
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier("profile.shareStats")
    }
}
