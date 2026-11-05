import Foundation
import SwiftUI

// MARK: - Personal recommendations

/// A ranked suggestion with the reason it was picked, so the shelf can explain itself.
struct RadarSuggestion: Identifiable, Hashable {
    let anime: Anime
    let reason: String
    let score: Double
    var id: Int { anime.id }
}

/// On-device ranking. No account, no upload: the watch history and the catalog are enough.
enum RadarEngine {
    /// Genre weights from what the viewer actually finished, newest watch counting most.
    static func affinities(history: [WatchRecord], favorites: Set<Int>, pool: [Anime]) -> [String: Double] {
        var weights: [String: Double] = [:]
        for (index, record) in history.enumerated() {
            let recency = 1.0 / (1.0 + Double(index) * 0.18)
            let finisher = record.completed ? 1.4 : 1.0
            for genre in record.anime.genres { weights[genre, default: 0] += recency * finisher }
        }
        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in favorites {
            guard let anime = byID[id] else { continue }
            for genre in anime.genres { weights[genre, default: 0] += 2.0 }
        }
        return weights
    }

    /// Pure ranking so it can be unit tested without any UI.
    static func suggestions(pool: [Anime],
                            history: [WatchRecord],
                            favorites: Set<Int>,
                            limit: Int = 18) -> [RadarSuggestion] {
        guard !pool.isEmpty else { return [] }
        let seen = Set(history.map(\.anime.id))
        let weights = affinities(history: history, favorites: favorites, pool: pool)
        let maximum = max(weights.values.max() ?? 0, 1)
        var rows: [RadarSuggestion] = []
        for anime in pool where !seen.contains(anime.id) && !favorites.contains(anime.id) {
            guard anime.id > 0 else { continue }
            let relevance = anime.genres.reduce(0.0) { $0 + (weights[$1] ?? 0) } / maximum
            let quality = ((anime.score ?? 6.5) / 10.0)
            let hungarian = anime.hasHungarian ? 0.7 : 0
            let airing = anime.status == "RELEASING" ? 0.25 : 0
            let favorite = favorites.contains(anime.id) ? 0.35 : 0
            let score = relevance * 3.2 + quality * 1.1 + hungarian + airing + favorite
            rows.append(RadarSuggestion(anime: anime, reason: reason(for: anime, weights: weights), score: score))
        }
        return Array(rows.sorted { $0.score == $1.score ? $0.anime.id < $1.anime.id : $0.score > $1.score }.prefix(limit))
    }

    private static func reason(for anime: Anime, weights: [String: Double]) -> String {
        let best = anime.genres.compactMap { genre -> (String, Double)? in
            guard let weight = weights[genre], weight > 0 else { return nil }
            return (genre, weight)
        }.max { $0.1 < $1.1 }
        if let best { return "Because you watch \(best.0)" }
        if anime.hasHungarian { return "Hungarian subtitles ready" }
        if anime.status == "RELEASING" { return "Airing right now" }
        return "Popular in the catalog"
    }

    /// Series that share the most genres with `anime`, used by the "More like this" rail.
    static func related(to anime: Anime, pool: [Anime], limit: Int = 8) -> [Anime] {
        let target = Set(anime.genres)
        guard !target.isEmpty else { return [] }
        var scored: [(anime: Anime, overlap: Int, score: Double)] = []
        for candidate in pool where candidate.id != anime.id {
            let overlap = Set(candidate.genres).intersection(target).count
            guard overlap > 0 else { continue }
            scored.append((candidate, overlap, candidate.score ?? 0))
        }
        scored.sort { lhs, rhs in
            if lhs.overlap != rhs.overlap { return lhs.overlap > rhs.overlap }
            return lhs.score > rhs.score
        }
        return scored.prefix(limit).map(\.anime)
    }
}

// MARK: - Screen

struct NativeRadar: View {
    @EnvironmentObject private var catalog: CatalogModel
    @ObservedObject private var library = AnimeLibrary.shared
    @ObservedObject private var releases = ReleaseFeed.shared
    @State private var refreshing = false

    private var pool: [Anime] {
        var seen = Set<Int>()
        return (catalog.titles + catalog.trending + catalog.seasonal).filter { seen.insert($0.id).inserted }
    }

    private var suggestions: [RadarSuggestion] {
        RadarEngine.suggestions(pool: pool, history: library.history, favorites: library.favorites, limit: 20)
    }

    /// The genre the viewer keeps coming back to, for the header line.
    private var strongestGenre: String? {
        RadarEngine.affinities(history: library.history, favorites: library.favorites, pool: pool)
            .max { $0.value < $1.value }?.key
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !releases.items.isEmpty { newInHungarian }
                if suggestions.isEmpty {
                    NativeEmpty(title: "Not enough history yet",
                                detail: "Watch or save a few series and this page fills itself with picks that share their genres.",
                                icon: "sparkles")
                } else {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionHeading(title: "Picked for you")
                        LazyVStack(spacing: 10) {
                            ForEach(suggestions) { suggestion in
                                NavigationLink { NativeDetail(seed: suggestion.anime) } label: { card(suggestion) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("radar.card.\(suggestion.anime.id)")
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.cortexBlack)
        .navigationTitle("For You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cortexBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            refreshing = true
            await catalog.load()
            refreshing = false
        }
        .task { if catalog.titles.isEmpty { await catalog.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.cortexPurple)
                Text("Cortex Radar").font(.system(size: 26, weight: .black)).accessibilityIdentifier("radar.title")
            }
            Text(headerLine).font(.caption).foregroundStyle(.white.opacity(0.6)).accessibilityIdentifier("radar.subtitle")
            HStack(spacing: 6) {
                Pill(text: "\(library.history.count) watched", color: .white)
                Pill(text: "\(library.favorites.count) saved", color: .green)
                if let strongestGenre { Pill(text: strongestGenre, color: .yellow) }
            }
        }
    }

    private var headerLine: String {
        if let strongestGenre {
            return "Ranked on this device from what you watched and saved. Your strongest taste right now is \(strongestGenre.lowercased())."
        }
        return "Ranked on this device from what you watched and saved — no account, no upload."
    }

    private var newInHungarian: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { SectionHeading(title: "Fresh Hungarian episodes"); Spacer(); Pill(text: "\(releases.items.count)", color: .green) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(releases.items.prefix(10)) { release in
                        NavigationLink { NativeLinkedDetail(id: release.animeID) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .top, spacing: 4) {
                                    AnimeArtwork(url: release.cover).frame(width: 116, height: 170)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(alignment: .topLeading) { Pill(text: "EP \(release.episode)", color: .cortexPurple).padding(6) }
                                }
                                Text(release.cleanTitle).font(.system(size: 11, weight: .bold)).lineLimit(2).frame(width: 116, alignment: .leading)
                                Text(release.ageText).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .cortexShelfTilt(strength: 13)
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }

    private func card(_ suggestion: RadarSuggestion) -> some View {
        HStack(spacing: 12) {
            AnimeArtwork(url: suggestion.anime.cover).frame(width: 64, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(suggestion.anime.title).font(.subheadline.bold()).lineLimit(2)
                HStack(spacing: 6) {
                    if let score = suggestion.anime.score { Text(String(format: "%.1f", score)).foregroundStyle(.yellow) }
                    Text(suggestion.anime.genres.prefix(2).joined(separator: " · ")).foregroundStyle(.white.opacity(0.5))
                }
                .font(.caption2)
                Text(suggestion.reason).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.cortexPurple)
                if suggestion.anime.hasHungarian {
                    Text("Hungarian subtitles").font(.system(size: 9)).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.35))
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
    }
}
